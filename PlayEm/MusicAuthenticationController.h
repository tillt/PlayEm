//
//  MusicAuthenticationController.h
//  PlayEm
//
//  Created by Till Toenshoff on 28.02.24.
//  Copyright © 2024 Till Toenshoff. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface MusicAuthenticationController : NSObject

- (void)requestAppleMusicUserTokenWithCompletion:(void(^)(BOOL success, NSString *appleMusicUserToken))completionBlock;
- (void)requestAppleMusicDeveloperTokenWithCompletion:(void(^)(NSString *appleMusicDeveloperToken))completionBlock;

@end

NS_ASSUME_NONNULL_END
