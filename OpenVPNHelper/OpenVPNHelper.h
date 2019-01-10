//
//  OpenVPNHelper.h
//  eduVPN
//
//  Created by Johan Kool on 03/07/2017.
//  Copyright © 2017 eduVPN. All rights reserved.
//

#import <Foundation/Foundation.h>

// kHelperToolMachServiceName is the Mach service name of the helper tool.  Note that the value
// here has to match the value in the MachServices dictionary in "HelperTool-Launchd.plist".

#define kHelperToolMachServiceName @"org.eduvpn.app.openvpnhelper"

// HelperToolProtocol is the NSXPCConnection-based protocol implemented by the helper tool
// and called by the app.

@protocol OpenVPNHelperProtocol

@required

/**
 Returns the version number of the tool
 
 @param reply Handler taking version number
 */
- (void)getVersionWithReply:(void(^_Nonnull)(NSString *_Nonnull version))reply;

/**
 Strarts OpenVPN connection
 
 @param launchURL URL to openvpn binary
 @param config URL to config file
 @param upScript URL to up script
 @param downScript URL to down script
 @param leasewatchPlist URL to lease watch plist daemon
 @param leasewatchScript URL to lease watch script
 @param scriptOptions Options for scripts
 @param reply Success or not
 */
- (void)startOpenVPNAtURL:(NSURL *_Nonnull)launchURL withConfig:(NSURL *_Nonnull)config upScript:(NSURL *_Nullable)upScript downScript:(NSURL *_Nullable)downScript leasewatchPlist:(NSURL *_Nullable)leasewatchPlist leasewatchScript:(NSURL *_Nullable)leasewatchScript scriptOptions:(NSArray <NSString *>*_Nullable)scriptOptions reply:(void(^_Nonnull)(NSArray))reply;

/**
 Closes OpenVPN connection
 
 @param reply Success
 */
- (void)closeWithReply:(void(^_Nonnull)(void))reply;

@end

@protocol ClientProtocol <NSObject>

@required

- (void)taskTerminatedWithReply:(void(^_Nonnull)(void))reply;

@end


// The following is the interface to the class that implements the helper tool.
// It's called by the helper tool's main() function, but not by the app directly.

@interface OpenVPNHelper : NSObject

- (void)run;

@end
