//
//  AuthenticationService.swift
//  eduVPN
//
//  Created by Johan Kool on 06/07/2017.
//  Copyright © 2017 eduVPN. All rights reserved.
//

import Foundation
import AppKit
import AppAuth

/// Authorizes user with provider
class AuthenticationService {
    
    enum Error: Swift.Error, LocalizedError {
        case unknown
        case noToken
        
        var errorDescription: String? {
            switch self {
            case .unknown:
                return NSLocalizedString("Authorization failed for unknown reason", comment: "")
            case .noToken:
                return NSLocalizedString("Authorization failed", comment: "")
            }
        }
        
        var recoverySuggestion: String? {
            switch self {
            case .unknown:
                return NSLocalizedString("Try to authorize again with your provider.", comment: "")
            case .noToken:
                return NSLocalizedString("Try to add your provider again.", comment: "")
            }
        }
    }
    
    /// Notification posted when authentication starts
    static let authenticationStarted = NSNotification.Name("AuthenticationService.authenticationStarted")
   
    /// Notification posted when authentication finishes
    static let authenticationFinished = NSNotification.Name("AuthenticationService.authenticationFinished")
    
    private var redirectHTTPHandler: OIDRedirectHTTPHandler?
    private let appConfig: AppConfigType
    
    init(appConfig: AppConfigType) {
        self.appConfig = appConfig
        readFromDisk()
    }
    
    /// Start authentication process with provider
    ///
    /// - Parameters:
    ///   - info: Provider info
    ///   - handler: Auth state or error
    func authenticate(using info: ProviderInfo, handler: @escaping (Result<Void>) -> ()) {
        // No need to authenticate for local config
        guard info.provider.connectionType != .localConfig else {
            handler(.success(Void()))
            return
        }
        
        handlersAfterAuthenticating.append(handler)
        if isAuthenticating {
            return
        }
        isAuthenticating = true
        
        let configuration = OIDServiceConfiguration(authorizationEndpoint: info.authorizationURL, tokenEndpoint: info.tokenURL)
        
        redirectHTTPHandler = OIDRedirectHTTPHandler(successURL: nil)
        var redirectURL: URL?
        if Thread.isMainThread {
            redirectURL = redirectHTTPHandler!.startHTTPListener(nil)
        } else {
            DispatchQueue.main.sync {
                redirectURL = redirectHTTPHandler!.startHTTPListener(nil)
            }
        }
        redirectURL = URL(string: "callback", relativeTo: redirectURL!)!
        let request = OIDAuthorizationRequest(configuration: configuration, clientId: "org.eduvpn.app.macos", clientSecret: nil, scopes: ["config"], redirectURL: redirectURL!, responseType: OIDResponseTypeCode, additionalParameters: nil)
      
        redirectHTTPHandler!.currentAuthorizationFlow = OIDAuthState.authState(byPresenting: request) { (authState, error) in
            NSRunningApplication.current.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
         
            self.isAuthenticating = false
           
            let success = authState != nil
            NotificationCenter.default.post(name: AuthenticationService.authenticationFinished, object: self, userInfo: ["success": success])
            
            // Little delay to make sure authentication screen is dismissed
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                self.handlersAfterAuthenticating.forEach { handler in
                    if let authState = authState {
                        self.store(for: info.provider, authState: authState)
                        handler(.success(Void()))
                    } else if let error = error {
                        handler(.failure(error))
                    } else {
                        handler(.failure(Error.unknown))
                    }
                }
                self.handlersAfterAuthenticating.removeAll()
            }
        }
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: AuthenticationService.authenticationStarted, object: self)
        }
    }
    
    private var isAuthenticating = false
    private var handlersAfterAuthenticating: [(Result<Void>) -> ()] = []
    
    /// Cancel authentication
    func cancelAuthentication() {
        redirectHTTPHandler?.cancelHTTPListener()
    }
    
    /// Authentication tokens
    private var authStatesByProviderId: [String: OIDAuthState] = [:]
    private var authStatesByConnectionType: [ConnectionType: OIDAuthState] = [:]
    
    /// Finds authentication token
    ///
    /// - Parameter provider: Provider
    /// - Returns: Authentication token if available
    func authState(for provider: Provider) -> OIDAuthState? {
        switch provider.authorizationType {
        case .local:
            return authStatesByProviderId[provider.id]
        case .distributed, .federated:
            return authStatesByConnectionType[provider.connectionType]
        }
    }
    
    enum Behavior {
        case never
        case ifNeeded
        case always
    }
    
    /// Performs an authenticated action
    ///
    /// - Parameters:
    ///   - info: Provider info
    ///   - authenticationBehavior: Whether authentication should be retried when token is revoked or expired
    ///   - action: The action to perform
    func performAction(for info: ProviderInfo, authenticationBehavior: Behavior = .ifNeeded, action: @escaping OIDAuthStateAction) {
        func reauthenticate() {
            authenticate(using: info, handler: { (result) in
                switch result {
                case .success:
                    self.performAction(for: info, authenticationBehavior: .never, action: action)
                case .failure(let error):
                    action(nil, nil, error)
                }
            })
        }
        
        guard let authState = authState(for: info.provider) else {
            switch authenticationBehavior {
            case .always, .ifNeeded:
                 reauthenticate()
            case .never:
                action(nil, nil, Error.noToken)
            }
            return
        }
        
        switch authenticationBehavior {
        case .always:
            reauthenticate()
            return
        case .ifNeeded, .never:
            break
        }
        
        authState.performAction { (accessToken, idToken, error) in
            guard let accessToken = accessToken else {
                switch authenticationBehavior {
                case .always, .ifNeeded:
                    reauthenticate()
                case .never:
                    action(nil, idToken, error)
                }
                return
            }
            action(accessToken, idToken, error)
        }
    }
    
    /// Stores an authentication token
    ///
    /// - Parameters:
    ///   - info: Provider info
    ///   - authState: Authentication token
    private func store(for provider: Provider, authState: OIDAuthState) {
        switch provider.authorizationType {
        case .local:
            authStatesByProviderId[provider.id] = authState
        case .distributed, .federated:
            authStatesByConnectionType[provider.connectionType] = authState
        }
        saveToDisk()
    }
    
    /// URL for saving authentication tokens to disk
    ///
    /// - Returns: URL
    /// - Throws: Error finding or creating directory
    private func storedAuthStatesFileURL() throws -> URL  {
        var applicationSupportDirectory = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        switch Bundle.main.bundleIdentifier! {
        case "org.eduvpn.app":
            applicationSupportDirectory.appendPathComponent("eduVPN")
        case "org.eduvpn.app.home":
            applicationSupportDirectory.appendPathComponent("Let's connect!")
        default:
            fatalError()
        }
        try FileManager.default.createDirectory(at: applicationSupportDirectory, withIntermediateDirectories: true, attributes: nil)
        applicationSupportDirectory.appendPathComponent("AuthenticationTokens.plist")
        return applicationSupportDirectory
    }
    
    /// Reads authentication tokens from disk
    private func readFromDisk() {
        do {
            let url = try storedAuthStatesFileURL()
            let data = try Data(contentsOf: url)
            // OIDAuthState doesn't support Codable, use NSArchiving instead
            if let restoredAuthStates = NSKeyedUnarchiver.unarchiveObject(with: data) as? [String: AnyObject] {
                if let authStatesByProviderId = restoredAuthStates["authStatesByProviderId"] as? [String: OIDAuthState] {
                    self.authStatesByProviderId = authStatesByProviderId
                }
                if let authStatesByConnectionType = restoredAuthStates["authStatesByConnectionType"] as? [String: OIDAuthState] {
                    // Convert String to ConnectionType
                    self.authStatesByConnectionType = authStatesByConnectionType.reduce(into: [ConnectionType: OIDAuthState]()) { (result, entry) in
                        if let type = ConnectionType(rawValue: entry.key) {
                            result[type] = entry.value
                        }
                    }
                }
            } else {
                NSLog("Failed to unarchive stored authentication tokens from disk")
            }
        } catch (let error) {
            NSLog("Failed to read stored authentication tokens from disk: \(error)")
        }
    }
    
    /// Saves authentication tokens to disk
    private func saveToDisk() {
        do {
            // Convert ConnectionType to String
            let authStatesByConnectionType = self.authStatesByConnectionType.reduce(into: [String: OIDAuthState]()) { (result, entry) in
                result[entry.key.rawValue] = entry.value
            }
            let data = NSKeyedArchiver.archivedData(withRootObject: ["authStatesByProviderId": authStatesByProviderId, "authStatesByConnectionType": authStatesByConnectionType])
            let url = try storedAuthStatesFileURL()
            try data.write(to: url, options: .atomic)
        } catch (let error) {
            NSLog("Failed to save stored authentication tokens to disk: \(error)")
        }
    }
    
}
