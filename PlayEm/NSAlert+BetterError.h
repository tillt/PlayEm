//
//  NSAlert+BetterError.h
//  PlayEm
//
//  Created by Till Toenshoff on 27.02.24.
//  Copyright © 2024 Till Toenshoff. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface NSAlert (BetterError)

+ (NSAlert*)betterAlertWithError:(NSError*)error url:(nullable NSURL*)url;
+ (NSAlert*)betterAlertWithError:(NSError*)error action:(nullable NSString*)action url:(nullable NSURL*)url;

@end

NS_ASSUME_NONNULL_END
