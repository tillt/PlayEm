//
//  NSError+BetterError.h
//  PlayEm
//
//  Created by Till Toenshoff on 27.02.24.
//  Copyright © 2024 Till Toenshoff. All rights reserved.
//

#import "NSError+BetterError.h"

#import <AudioToolbox/AudioToolbox.h>

@implementation NSError (BetterError)

+ (NSString*)stringFromOSStatus:(NSInteger)code
{
    char cString[5];
    
    cString[0] = (code >> 24) & 0xFF;
    cString[1] = (code >> 16) & 0xFF;
    cString[2] = (code >>  8) & 0xFF;
    cString[3] = code         & 0xFF;
    cString[4] = 0;
    
    return [NSString stringWithCString:cString encoding:NSStringEncodingConversionAllowLossy];
}

+ (NSError*)betterErrorWithError:(NSError*)error
{
    return [NSError betterErrorWithError:error action:nil url:nil];
}

+ (NSError*)betterErrorWithError:(NSError*)error url:(NSURL*)url
{
    return [NSError betterErrorWithError:error action:nil url:url];
}

+ (NSError*)betterErrorWithError:(NSError*)error action:(NSString*)action url:(NSURL*)url
{
    NSLog(@"description: %@", error.localizedDescription);
    NSLog(@"reason: %@", error.localizedFailureReason);
    NSLog(@"recovery: %@", error.localizedRecoverySuggestion);
    NSLog(@"domain: %@", error.domain);
    NSLog(@"userInfo: %@", error.userInfo);
    
    NSDictionary* stringMap = @{
        // AudioFile.h
        @(kAudioFileUnspecifiedError): @"unspecified error",
        @(kAudioFileUnsupportedFileTypeError): @"unsupported file type",
        @(kAudioFileUnsupportedDataFormatError): @"unsupported file type",
        @(kAudioFileUnsupportedPropertyError): @"unsupported property",
        @(kAudioFileBadPropertySizeError): @"bad property size",
        @(kAudioFilePermissionsError): @"permissions error",
        @(kAudioFileNotOptimizedError): @"not optimized",
        @(kAudioFileInvalidChunkError): @"invalid chunk",
        @(kAudioFileDoesNotAllow64BitDataSizeError): @"does not allow 64bit data size",
        @(kAudioFileInvalidPacketOffsetError): @"invalid packat offset",
        @(kAudioFileInvalidPacketDependencyError): @"packet dependency error",
        @(kAudioFileInvalidFileError): @"invalid file error",
        @(kAudioFileOperationNotSupportedError): @"operation not supported",
    };

    NSString* description = error.localizedDescription;
    NSString* extendedDescription = stringMap[@(error.code)];
    NSString* failureReason = error.localizedFailureReason;
    NSString* fileName = [[url filePathURL] lastPathComponent];

    NSArray<NSString*>* frameworkComponents = [error.domain componentsSeparatedByString:@"."];
    NSString* frameworkName = frameworkComponents[frameworkComponents.count - 1];
    NSString* frameworkErrorCodePrefix = [NSString stringWithFormat:@"(%@ error ", error.domain];
    NSRange range = [description rangeOfString:frameworkErrorCodePrefix];

    if (action == nil) {
        action = @"process";
    }
    NSString* urlInsert = @"";
    if (fileName != nil) {
        urlInsert = [NSString stringWithFormat:@" the file \'%@\'", fileName];
    }

    // Spare the user the hard to read framework name.
    if (range.length > 0) {
        NSString* goodPart = [description substringToIndex:range.location];
        NSString* trigraph = [NSError stringFromOSStatus:error.code];
        
        if (failureReason == nil) {
            failureReason = [NSString stringWithFormat:@"When trying to %@%@ %@ returned: '%@'",
                             action,
                             urlInsert,
                             frameworkName,
                             extendedDescription];
        }
        description = goodPart;
    }
    if (failureReason == nil) {
        failureReason = [NSString stringWithFormat:@"Tried to %@ \"%@\"", action, fileName];
    }
    failureReason = [failureReason stringByAppendingString:@"."];
    
    NSDictionary* userInfo = @{
        NSLocalizedDescriptionKey: description,
        NSLocalizedFailureReasonErrorKey: failureReason,
    };

    return [NSError errorWithDomain:[[NSBundle bundleForClass:[self class]] bundleIdentifier]
                               code:error.code
                           userInfo:userInfo];
}

@end
