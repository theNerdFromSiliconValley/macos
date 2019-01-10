//
//  OpenVPNHelper.m
//  eduVPN
//
//  Created by Johan Kool on 03/07/2017.
//  Copyright © 2017 eduVPN. All rights reserved.
//

#import "OpenVPNHelper.h"
#include <syslog.h>

@interface OpenVPNHelper () <NSXPCListenerDelegate, OpenVPNHelperProtocol>

@property (atomic, strong, readwrite) NSXPCListener *listener;
@property (atomic, strong) NSTask *openVPNTask;
@property (atomic, copy) NSString *logFilePath;
@property (atomic, strong) id <ClientProtocol> remoteObject;

@end

@implementation OpenVPNHelper

- (id)init {
    self = [super init];
    if (self != nil) {
        // Set up our XPC listener to handle requests on our Mach service.
        self->_listener = [[NSXPCListener alloc] initWithMachServiceName:kHelperToolMachServiceName];
        self->_listener.delegate = self;
    }
    return self;
}

- (void)run {
    // Tell the XPC listener to start processing requests.
    [self.listener resume];
    
    // Run the run loop forever.
    [[NSRunLoop currentRunLoop] run];
}

// Called by our XPC listener when a new connection comes in.  We configure the connection
// with our protocol and ourselves as the main object.
- (BOOL)listener:(NSXPCListener *)listener shouldAcceptNewConnection:(NSXPCConnection *)newConnection {
    assert(listener == self.listener);
    assert(newConnection != nil);
    
    newConnection.exportedInterface = [NSXPCInterface interfaceWithProtocol:@protocol(OpenVPNHelperProtocol)];
    newConnection.exportedObject = self;
    newConnection.remoteObjectInterface = [NSXPCInterface interfaceWithProtocol:@protocol(ClientProtocol)];
    self.remoteObject = newConnection.remoteObjectProxy;
    [newConnection resume];
    
    return YES;
}

- (void)getVersionWithReply:(void(^)(NSString * version))reply {
    NSString *version = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"?";
    NSString *buildVersion = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleVersion"] ?: @"?";
    reply([NSString stringWithFormat:@"%@-%@", version, buildVersion]);
}

- (BOOL)verify:(NSString *)identifier atURL:(NSURL *)fileURL {
    SecStaticCodeRef staticCodeRef = 0;
    OSStatus status = SecStaticCodeCreateWithPath((__bridge CFURLRef _Nonnull)(fileURL), kSecCSDefaultFlags, &staticCodeRef);
    if (status != errSecSuccess) {
        syslog(LOG_ERR, "Static code error %d", status);
        return NO;
    }
    
    NSString *requirement = [NSString stringWithFormat:@"anchor apple generic and identifier %@ and certificate leaf[subject.OU] = %@", identifier, TEAM];
    SecRequirementRef requirementRef = 0;
    status = SecRequirementCreateWithString((__bridge CFStringRef _Nonnull)requirement, kSecCSDefaultFlags, &requirementRef);
    if (status != errSecSuccess) {
        syslog(LOG_ERR, "Requirement error %d", status);
        return NO;
    }
    
    status = SecStaticCodeCheckValidity(staticCodeRef, kSecCSDefaultFlags, requirementRef);
    if (status != errSecSuccess) {
        syslog(LOG_ERR, "Validity error %d", status);
        return NO;
    }
    
    return YES;
}

- (void)startOpenVPNAtURL:(NSURL *_Nonnull)launchURL withConfig:(NSURL *_Nonnull)config upScript:(NSURL *_Nullable)upScript downScript:(NSURL *_Nullable)downScript leasewatchPlist:(NSURL *_Nullable)leasewatchPlist leasewatchScript:(NSURL *_Nullable)leasewatchScript scriptOptions:(NSArray <NSString *>*_Nullable)scriptOptions reply:(void(^_Nonnull)(NSArray))reply {
    
    
    
    NSMutableArray *status = [[NSMutableArray alloc]init];
    
    // stores value if the call is successful
    [status insertObject:[NSNumber numberWithBool: false] atIndex:0];
    
    //Store value of any comments
    [status insertObject:@"Secured Config File" atIndex:1];
    
    //Store value of problem type
    [status insertObject:@"clean" atIndex:2];
    
    
    
    
    syslog(LOG_NOTICE, "Starting filtering file");
    // Get the path of config file
    NSString* path = config.path;
    NSString* content = [NSString stringWithContentsOfFile:path
                                                  encoding:NSUTF8StringEncoding
                                                     error:NULL];
    NSMutableArray *listItems = [content componentsSeparatedByString:@"\n"];
    NSArray *maliciousCommands = @[@"up", @"tls-verify", @"ipchange", @"client-connect", @"route-up",@"route-pre-down",@"client-disconnect",@"down",@"learn-address",@"auth-user-pass-verify"];
    
    // Malicious command index set variable declarion
    NSMutableIndexSet *indexes = [[NSMutableIndexSet alloc] init];
    
    
    //loop through array to check if malicious is command
    for ( int i = 0; i < [listItems count]; i++) {
        NSString *line =[[[listItems objectAtIndex: i] lowercaseString] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        
        // Filter out comment from line
        line =  [line componentsSeparatedByString:@"#"].firstObject;
        line =  [line componentsSeparatedByString:@";"].firstObject;
        
        
        //Loop through malicious commands to check if any of them is present in the line
        for ( int j = 0; j < [maliciousCommands count]; j++) {
            NSString *maliciousCommand = [maliciousCommands objectAtIndex: j];
            
            //Check if malicious command was found
            if ([line rangeOfString:[NSString stringWithFormat:@"%@%@", maliciousCommand,@" "]].location == NSNotFound) {
                
            } else {
                syslog( LOG_NOTICE, "malicious command %s removed", [maliciousCommand UTF8String] );
                
                [status insertObject:[NSNumber numberWithBool: false] atIndex:0];
                [status insertObject:line atIndex:1];
                [status insertObject: @"virus" atIndex:2];
                reply(status);
                //Add malicious command in index
                [indexes addIndex:i];
            }
        }
    }
    
    
    
    
    // Verify that binary at URL is signed by us
    if (![self verify:@"openvpn" atURL:launchURL]) {
        [status insertObject:[NSNumber numberWithBool: false] atIndex:0];
        reply(status);
        return;
    }
    
    // Verify that up script at URL is signed by us
    if (upScript && ![self verify:@"client.up.eduvpn" atURL:upScript]) {
        [status insertObject:[NSNumber numberWithBool: false] atIndex:0];
        reply(status);
        return;
    }
    
    // Verify that down script at URL is signed by us
    if (downScript && ![self verify:@"client.down.eduvpn" atURL:downScript]) {
        [status insertObject:[NSNumber numberWithBool: false] atIndex:0];
        reply(status);
        return;
    }
    
    // Monitoring is enabled
    if ([scriptOptions containsObject:@"-m"]) {
        // Write plist to leasewatch
        NSDictionary *leasewatchPlistContents = @{@"Label": @"org.eduvpn.app.leasewatch",
                                                  @"ProgramArguments": @[leasewatchScript.path],
                                                  @"WatchPaths": @[@"/Library/Preferences/SystemConfiguration"]
                                                  };
        NSError *error;
        NSString *leasewatchPlistDirectory = leasewatchPlist.path.stringByDeletingLastPathComponent;
        if (![[NSFileManager defaultManager] createDirectoryAtPath:leasewatchPlistDirectory withIntermediateDirectories:YES attributes:nil error:&error]) {
            syslog(LOG_WARNING, "Error creating directory for leasewatch plist at %s: %s", leasewatchPlistDirectory.UTF8String, error.description.UTF8String);
        }
        NSString *leasewatchPlistLogsDirectory = [leasewatchPlistDirectory stringByAppendingPathComponent:@"Logs"];;
        if (![[NSFileManager defaultManager] createDirectoryAtPath:leasewatchPlistLogsDirectory withIntermediateDirectories:YES attributes:nil error:&error]) {
            syslog(LOG_WARNING, "Error creating directory for leasewatch Logs at %s: %s", leasewatchPlistLogsDirectory.UTF8String, error.description.UTF8String);
        }
        if (![leasewatchPlistContents writeToURL:leasewatchPlist atomically:YES]) {
            syslog(LOG_WARNING, "Error writing watch plist contents to %s", leasewatchPlist.path.UTF8String);
        }
        
        // Make lease watch file readable
        if (![[NSFileManager defaultManager] setAttributes:@{NSFilePosixPermissions: [NSNumber numberWithShort:0744]} ofItemAtPath:leasewatchPlist.path error:&error]) {
            syslog(LOG_WARNING, "Error making lease watch plist %s exeutable (chmod 744): %s", leasewatchPlist.path.UTF8String, error.description.UTF8String);
        }
    }
    
    syslog(LOG_NOTICE, "Launching task");
    
    NSTask *task = [[NSTask alloc] init];
    task.launchPath = launchURL.path;
    NSString *logFilePath = [config.path stringByAppendingString:@".log"];
    NSString *socketPath = @"/private/tmp/eduvpn.socket";
    
    NSMutableArray *arguments = [NSMutableArray arrayWithArray:@[@"--config", [self pathWithSpacesEscaped:config.path],
                                                                 @"--log", [self pathWithSpacesEscaped:logFilePath],
                                                                 @"--management", [self pathWithSpacesEscaped:socketPath], @"unix",
                                                                 @"--management-external-key",
                                                                 @"--management-external-cert", @"macosx-keychain",
                                                                 @"--management-query-passwords",
                                                                 @"--management-forget-disconnect"]];
    
    if (upScript.path) {
        [arguments addObjectsFromArray:@[@"--up", [self scriptPath:upScript.path withOptions:scriptOptions]]];
    }
    if (downScript.path) {
        [arguments addObjectsFromArray:@[@"--down", [self scriptPath:downScript.path withOptions:scriptOptions]]];
    }
    if (upScript.path || downScript.path) {
        // 2 -- allow calling of built-ins and scripts
        [arguments addObjectsFromArray:@[@"--script-security", @"2"]];
    }
    task.arguments = arguments;
    [task setTerminationHandler:^(NSTask *task){
        [[NSFileManager defaultManager] removeItemAtPath:socketPath error:NULL];
        [self.remoteObject taskTerminatedWithReply:^{
            syslog(LOG_NOTICE, "Terminated task");
        }];
    }];
    [task launch];
    
    // Create and make log file readable
    NSError *error;
    [[NSFileManager defaultManager] createFileAtPath:logFilePath contents:nil attributes:nil];
    if (![[NSFileManager defaultManager] setAttributes:@{NSFilePosixPermissions: [NSNumber numberWithShort:0644]} ofItemAtPath:logFilePath error:&error]) {
        syslog(LOG_WARNING, "Error making log file %s readable (chmod 644): %s", logFilePath.UTF8String, error.description.UTF8String);
    }
    
    self.openVPNTask = task;
    self.logFilePath = logFilePath;
    
    if(task.isRunning){
        [status insertObject:[NSNumber numberWithBool: true] atIndex:0];
    }
    else{
        [status insertObject:[NSNumber numberWithBool: false] atIndex:0];
    }
    
    
    reply(status);
}

- (void)closeWithReply:(void(^)(void))reply {
    [self.openVPNTask interrupt];
    self.openVPNTask = nil;
    reply();
}

- (NSString *)pathWithSpacesEscaped:(NSString *)path {
    return [path stringByReplacingOccurrencesOfString:@" " withString:@"\\ "];
}

- (NSString *)scriptPath:(NSString *)path withOptions:(NSArray <NSString *>*)scriptOptions {
    if (scriptOptions && [scriptOptions count] > 0) {
        NSString *escapedPath = [self pathWithSpacesEscaped:path];
        return [NSString stringWithFormat:@"%@ %@", escapedPath, [scriptOptions componentsJoinedByString:@" "]];
    } else {
        NSString *escapedPath = [self pathWithSpacesEscaped:path];
        return escapedPath;
    }
}

@end
