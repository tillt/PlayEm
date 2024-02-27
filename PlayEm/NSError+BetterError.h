//
//  NSError+BetterError.h
//  PlayEm
//
//  Created by Till Toenshoff on 27.02.24.
//  Copyright © 2024 Till Toenshoff. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface NSError (BetterError)

+ (NSError*)betterErrorWithError:(NSError*)error;
+ (NSError*)betterErrorWithError:(NSError*)error url:(nullable NSURL*)url;
+ (NSError*)betterErrorWithError:(NSError*)error action:(nullable NSString*)action url:(nullable NSURL*)url;

@end

NS_ASSUME_NONNULL_END
