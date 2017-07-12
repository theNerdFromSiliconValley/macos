/*! @file OIDAuthorizationUICoordinatorMac.h
    @brief AppAuth iOS SDK
    @copyright
        Copyright 2016 Google Inc. All Rights Reserved.
    @copydetails
        Licensed under the Apache License, Version 2.0 (the "License");
        you may not use this file except in compliance with the License.
        You may obtain a copy of the License at

        http://www.apache.org/licenses/LICENSE-2.0

        Unless required by applicable law or agreed to in writing, software
        distributed under the License is distributed on an "AS IS" BASIS,
        WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
        See the License for the specific language governing permissions and
        limitations under the License.
 */

#import "OIDAuthorizationUICoordinator.h"

NS_ASSUME_NONNULL_BEGIN

/*! @brief An Mac specific authorization UI Coordinator that uses the default browser to
        present an authorization request.
 */
@interface OIDAuthorizationUICoordinatorMac : NSObject <OIDAuthorizationUICoordinator> {
  // private variables
  BOOL _authorizationFlowInProgress;
  __weak id<OIDAuthorizationFlowSession> _session;
}

@end

NS_ASSUME_NONNULL_END
