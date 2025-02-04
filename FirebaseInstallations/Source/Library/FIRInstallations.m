/*
 * Copyright 2019 Google
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

#import "FIRInstallations.h"

#if __has_include(<FBLPromises/FBLPromises.h>)
#import <FBLPromises/FBLPromises.h>
#else
#import "FBLPromises.h"
#endif

#import <FirebaseCore/FIRAppInternal.h>
#import <FirebaseCore/FIRComponent.h>
#import <FirebaseCore/FIRComponentContainer.h>
#import <FirebaseCore/FIRLibrary.h>
#import <FirebaseCore/FIRLogger.h>
#import <FirebaseCore/FIROptions.h>

#import "FIRInstallationsAuthTokenResultInternal.h"

#import "FIRInstallationsErrorUtil.h"
#import "FIRInstallationsIDController.h"
#import "FIRInstallationsItem.h"
#import "FIRInstallationsStoredAuthToken.h"
#import "FIRInstallationsVersion.h"

NS_ASSUME_NONNULL_BEGIN

@protocol FIRInstallationsInstanceProvider <FIRLibrary>
@end

@interface FIRInstallations () <FIRInstallationsInstanceProvider>
@property(nonatomic, readonly) FIROptions *appOptions;
@property(nonatomic, readonly) NSString *appName;

@property(nonatomic, readonly) FIRInstallationsIDController *installationsIDController;

@end

@implementation FIRInstallations

#pragma mark - Firebase component

+ (void)load {
  [FIRApp registerInternalLibrary:(Class<FIRLibrary>)self
                         withName:@"fire-install"
                      withVersion:[NSString stringWithUTF8String:FIRInstallationsVersionStr]];
}

+ (nonnull NSArray<FIRComponent *> *)componentsToRegister {
  FIRComponentCreationBlock creationBlock =
      ^id _Nullable(FIRComponentContainer *container, BOOL *isCacheable) {
    *isCacheable = YES;
    FIRInstallations *installations = [[FIRInstallations alloc] initWithApp:container.app];
    return installations;
  };

  FIRComponent *installationsProvider =
      [FIRComponent componentWithProtocol:@protocol(FIRInstallationsInstanceProvider)
                      instantiationTiming:FIRInstantiationTimingAlwaysEager
                             dependencies:@[]
                            creationBlock:creationBlock];
  return @[ installationsProvider ];
}

- (instancetype)initWithApp:(FIRApp *)app {
  return [self initWitAppOptions:app.options appName:app.name];
}

- (instancetype)initWitAppOptions:(FIROptions *)appOptions appName:(NSString *)appName {
  FIRInstallationsIDController *IDController =
      [[FIRInstallationsIDController alloc] initWithGoogleAppID:appOptions.googleAppID
                                                        appName:appName
                                                         APIKey:appOptions.APIKey
                                                      projectID:appOptions.projectID];
  return [self initWithAppOptions:appOptions
                          appName:appName
        installationsIDController:IDController
                prefetchAuthToken:YES];
}

/// The initializer is supposed to be used by tests to inject `installationsStore`.
- (instancetype)initWithAppOptions:(FIROptions *)appOptions
                           appName:(NSString *)appName
         installationsIDController:(FIRInstallationsIDController *)installationsIDController
                 prefetchAuthToken:(BOOL)prefetchAuthToken {
  self = [super init];
  if (self) {
    _appOptions = [appOptions copy];
    _appName = [appName copy];
    _installationsIDController = installationsIDController;

    // Pre-fetch auth token.
    if (prefetchAuthToken) {
      [self authTokenWithCompletion:^(FIRInstallationsAuthTokenResult *_Nullable tokenResult,
                                      NSError *_Nullable error){
      }];
    }
  }
  return self;
}

#pragma mark - Public

+ (FIRInstallations *)installations {
  FIRApp *defaultApp = [FIRApp defaultApp];
  if (!defaultApp) {
    [NSException raise:NSInternalInconsistencyException
                format:@"The default FirebaseApp instance must be configured before the default"
                       @"FirebaseApp instance can be initialized. One way to ensure that is to "
                       @"call `[FIRApp configure];` (`FirebaseApp.configure()` in Swift) in the App"
                       @" Delegate's `application:didFinishLaunchingWithOptions:` "
                       @"(`application(_:didFinishLaunchingWithOptions:)` in Swift)."];
  }

  return [self installationsWithApp:defaultApp];
}

+ (FIRInstallations *)installationsWithApp:(FIRApp *)app {
  id<FIRInstallationsInstanceProvider> installations =
      FIR_COMPONENT(FIRInstallationsInstanceProvider, app.container);
  return (FIRInstallations *)installations;
}

- (void)installationIDWithCompletion:(FIRInstallationsIDHandler)completion {
  [self.installationsIDController getInstallationItem]
      .then(^id(FIRInstallationsItem *installation) {
        completion(installation.firebaseInstallationID, nil);
        return nil;
      })
      .catch(^(NSError *error) {
        completion(nil, [FIRInstallationsErrorUtil publicDomainErrorWithError:error]);
      });
}

- (void)authTokenWithCompletion:(FIRInstallationsTokenHandler)completion {
  [self authTokenForcingRefresh:NO completion:completion];
}

- (void)authTokenForcingRefresh:(BOOL)forceRefresh
                     completion:(FIRInstallationsTokenHandler)completion {
  [self.installationsIDController getAuthTokenForcingRefresh:forceRefresh]
      .then(^FIRInstallationsAuthTokenResult *(FIRInstallationsItem *installation) {
        FIRInstallationsAuthTokenResult *result = [[FIRInstallationsAuthTokenResult alloc]
             initWithToken:installation.authToken.token
            expirationDate:installation.authToken.expirationDate];
        return result;
      })
      .then(^id(FIRInstallationsAuthTokenResult *token) {
        completion(token, nil);
        return nil;
      })
      .catch(^void(NSError *error) {
        completion(nil, [FIRInstallationsErrorUtil publicDomainErrorWithError:error]);
      });
}

- (void)deleteWithCompletion:(void (^)(NSError *__nullable error))completion {
  [self.installationsIDController deleteInstallation]
      .then(^id(id result) {
        completion(nil);
        return nil;
      })
      .catch(^void(NSError *error) {
        completion([FIRInstallationsErrorUtil publicDomainErrorWithError:error]);
      });
}

@end

NS_ASSUME_NONNULL_END
