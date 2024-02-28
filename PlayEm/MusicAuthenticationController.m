//
//  MusicAuthenticationController.m
//  PlayEm
//
//  Created by Till Toenshoff on 28.02.24.
//  Copyright © 2024 Till Toenshoff. All rights reserved.
//

#import "MusicAuthenticationController.h"

#import <StoreKit/StoreKit.h>

@interface MusicAuthenticationController ()
    @property (strong, nonatomic) SKCloudServiceController* cloudServiceController;
@end

@implementation MusicAuthenticationController
{
}

- (id)init
{
    self = [super init];
    if (self) {
        _cloudServiceController = [SKCloudServiceController new];
    }
    return self;
}

- (void)checkPermissions 
{
    SKCloudServiceAuthorizationStatus status = SKCloudServiceController.authorizationStatus;
    switch (status) {
        case SKCloudServiceAuthorizationStatusNotDetermined:{
            // Not determined: ask for permission.
            [SKCloudServiceController requestAuthorization:^(SKCloudServiceAuthorizationStatus status) {
                NSLog(@"status %ld", status);
                [self checkPermissions];
            }];
            break;
        }
        case SKCloudServiceAuthorizationStatusAuthorized:
            // Authorized: proceed.
            NSLog(@"Authorized: proceed");
            break;
        default:
            // Denied or restricted: do not proceed.
            NSLog(@"Denied!");
            break;
    }
}

- (void)requestAppleMusicUserTokenWithCompletion:(void(^)(BOOL success, NSString *appleMusicUserToken))completionBlock
{
    
}

- (void)requestAppleMusicDeveloperTokenWithCompletion:(void(^)(NSString *token))completionBlock
{
    // This needs to move and get a completion handler provided.
    [self checkPermissions];

    NSString* developerToken = @"";

    [_cloudServiceController requestUserTokenForDeveloperToken:developerToken completionHandler:^(NSString * _Nullable userToken, NSError * _Nullable error){
        if (error != nil) {
            NSLog(@"Error requesting user token for developer token: %@", error);
            return;
        }
        NSLog(@"user token: %@", userToken);
    }];
    
    [self capabilities];
    
    //[_cloudServiceController.token]
    
    

    
//    SKCloudServiceController *cloudServiceController = [AppleMusicTokenController sharedInstance].cloudServiceController;
//        [cloudServiceController
//         requestUserTokenForDeveloperToken:[[AppleMusicTokenController sharedInstance] developerToken]  completionHandler:^(NSString * _Nullable userToken, NSError * _Nullable error) {
//             if (error) {
//                 NSLog(@"apple music user token error: %@", [error localizedDescription]);
//                 [[error userInfo] objectForKey:SKErrorDomain];
//                 completionBlock(NO, nil);
//             } else {
//                 NSLog(@"user token is %@", userToken);
//                 completionBlock(YES, userToken);
//             }
//         }];
}

- (void)capabilities
{
    [_cloudServiceController requestCapabilitiesWithCompletionHandler:^(SKCloudServiceCapability capabilities, NSError * _Nullable error) {
        if (error != nil) {
          NSLog(@"Error getting SKCloudServiceController capabilities: %@", error);
        } else if (capabilities & SKCloudServiceCapabilityMusicCatalogPlayback) {
          // The user has an active subscription
          NSLog(@"YES SUBSCRIBED!!!!");
        } else {
          // The user does *not* have an active subscription
          NSLog(@"NOT SUBSCRIBED!!!!");
        }
    }];
}

- (void)catalog
{
//    MPMediaQuery *albumsQuery = [MPMediaQuery albumsQuery];
}

@end
