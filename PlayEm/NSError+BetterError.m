//
//  NSError+BetterError.h
//  PlayEm
//
//  Created by Till Toenshoff on 27.02.24.
//  Copyright © 2024 Till Toenshoff. All rights reserved.
//
#include <ctype.h>

#import "NSError+BetterError.h"

#import <AudioToolbox/AudioToolbox.h>

@implementation NSError (BetterError)

+ (NSString*)stringFromOSStatus:(NSInteger)code
{
    const int length = 4;
    char cString[length + 1];

    for (int i = 0; i < length; i++) {
        int shift = (length - (i + 1)) * 8;
        int component = (code >> shift) & 0xFF;
        if (component == 0 || !isascii(component)) {
            return nil;
        }
        cString[i] = component;
    }
    cString[length] = 0;
  
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
        @(kAudioFileInvalidPacketOffsetError): @"invalid packet offset",
        @(kAudioFileInvalidPacketDependencyError): @"packet dependency error",
        @(kAudioFileInvalidFileError): @"invalid file error",
        @(kAudioFileOperationNotSupportedError): @"operation not supported",
    };

    NSString* description = error.localizedDescription;
    NSString* failureReason = error.localizedFailureReason;
    NSString* fileName = [[url filePathURL] lastPathComponent];

    // Reduce the hard to read fully qualified framework name into the last component.
    NSArray<NSString*>* frameworkComponents = [error.domain componentsSeparatedByString:@"."];
    NSString* frameworkName = frameworkComponents[frameworkComponents.count - 1];

    // Remove the framework error code prefix from the description. Example "(com.apple.avfaudio error XXXXXXXX)".
    NSString* frameworkErrorCodePrefix = [NSString stringWithFormat:@"(%@ error ", error.domain];
    NSRange range = [description rangeOfString:frameworkErrorCodePrefix];
    if (range.length > 0) {
        NSString* goodPart = [description substringToIndex:range.location];
        description = goodPart;
    }

    if (failureReason == nil) {
        // Set a default action.
        if (action == nil) {
            action = @"process";
        }

        // Make sure the file we were trying to access is mentioned.
        NSString* urlInsert = @"";
        if (fileName != nil && ![description containsString:fileName]) {
            urlInsert = [NSString stringWithFormat:@" \"%@\"", fileName];
        }

        // Add the trigraph from the error code (OSStatus) if available.
        NSString* trigraphInsert = @"";
        NSString* trigraph = [NSError stringFromOSStatus:error.code];
        if (trigraph != nil) {
            trigraphInsert = [NSString stringWithFormat:@" (%@)", trigraph];
        }
        
        // Add a description derived from the hopefully known error code.
        NSString* extendedDescription = stringMap[@(error.code)];
        if (extendedDescription == nil) {
            extendedDescription = @"";
        }

        // Build a neat failureReason.
        failureReason = [NSString stringWithFormat:@"When trying to %@%@ %@ suggests: %@%@.",
                         action,
                         urlInsert,
                         frameworkName,
                         extendedDescription,
                         trigraphInsert];
    }
    
    NSDictionary* userInfo = @{
        NSLocalizedDescriptionKey: description,
        NSLocalizedFailureReasonErrorKey: failureReason,
    };

    return [NSError errorWithDomain:[[NSBundle bundleForClass:[self class]] bundleIdentifier]
                               code:error.code
                           userInfo:userInfo];
}

@end
