//
//  NSAlert+BetterError.h
//  PlayEm
//
//  Created by Till Toenshoff on 27.02.24.
//  Copyright © 2024 Till Toenshoff. All rights reserved.
//

#import <AudioToolbox/AudioToolbox.h>

#import "NSAlert+BetterError.h"
#import "NSError+BetterError.h"

@implementation NSAlert (BetterError)

/// Creates an alert panel showing an enhanced error message.
///
/// - Parameters:
///   - error: the original error
///   - url: location of a resource
///
/// - Returns: alert panel
///
+ (NSAlert*)betterAlertWithError:(NSError*)error url:(NSURL*)url
{
    NSError* betterError = [NSError betterErrorWithError:error url:url];
    NSAlert* alert = [NSAlert alertWithError:betterError];
    alert.informativeText = betterError.localizedFailureReason;

    return alert;
}

/// Creates an alert panel showing an enhanced error message.
///
/// - Parameters:
///   - error: the original error
///   - action: description of the action leading to the error
///   - url: location of the resource connected to the given action
///
/// - Returns: alert panel
///
+ (NSAlert*)betterAlertWithError:(NSError*)error action:(NSString*)action url:(NSURL*)url
{
    NSError* betterError = [NSError betterErrorWithError:error action:action url:url];
    NSAlert* alert = [NSAlert alertWithError:betterError];
    alert.informativeText = betterError.localizedFailureReason;

    return alert;
}

@end
