//
//  NSAlert+BetterError.h
//  PlayEm
//
//  Created by Till Toenshoff on 27.02.24.
//  Copyright © 2024 Till Toenshoff. All rights reserved.
//

#import "NSAlert+BetterError.h"
#import "NSError+BetterError.h"

#import <AudioToolbox/AudioToolbox.h>

@implementation NSAlert (BetterError)

+ (NSAlert*)betterAlertWithError:(NSError*)error url:(NSURL*)url
{
    NSError* betterError = [NSError betterErrorWithError:error url:url];
    NSAlert* betterAlert = [NSAlert alertWithError:betterError];
    betterAlert.informativeText = betterError.localizedFailureReason;
    
    return betterAlert;
}

+ (NSAlert*)betterAlertWithError:(NSError*)error action:(NSString*)action url:(NSURL*)url
{
    NSError* betterError = [NSError betterErrorWithError:error action:action url:url];
    NSAlert* betterAlert = [NSAlert alertWithError:betterError];
    betterAlert.informativeText = betterError.localizedFailureReason;
    
    return betterAlert;
}

@end
