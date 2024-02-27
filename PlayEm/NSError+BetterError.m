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

//    switch(error.code) {
//        case kAudioFileUnspecifiedError:
//            break;
//            /*
//            kAudioFileUnspecifiedError                        = 'wht?',        // 0x7768743F, 2003334207
//            kAudioFileUnsupportedFileTypeError                 = 'typ?',        // 0x7479703F, 1954115647
//            kAudioFileUnsupportedDataFormatError             = 'fmt?',        // 0x666D743F, 1718449215
//            kAudioFileUnsupportedPropertyError                 = 'pty?',        // 0x7074793F, 1886681407
//            kAudioFileBadPropertySizeError                     = '!siz',        // 0x2173697A,  561211770
//            kAudioFilePermissionsError                         = 'prm?',        // 0x70726D3F, 1886547263
//            kAudioFileNotOptimizedError                        = 'optm',        // 0x6F70746D, 1869640813
//            // file format specific error codes
//            kAudioFileInvalidChunkError                        = 'chk?',        // 0x63686B3F, 1667787583
//            kAudioFileDoesNotAllow64BitDataSizeError        = 'off?',        // 0x6F66663F, 1868981823
//            kAudioFileInvalidPacketOffsetError                = 'pck?',        // 0x70636B3F, 1885563711
//            kAudioFileInvalidPacketDependencyError            = 'dep?',        // 0x6465703F, 1684369471
//            kAudioFileInvalidFileError                        = 'dta?',        // 0x6474613F, 1685348671
//            kAudioFileOperationNotSupportedError            = 0x6F703F3F,     // 'op??', integer used because of trigraph
//             */
//    }
//    if ([statusString isEqualToString:kAudioFileUnspecifiedError]) {
//        
//    }


//    NSError* betterError = [NSError errorWithDomain:NSCocoaErrorDomain
//                                               code:<#(NSInteger)#> userInfo:<#(nullable NSDictionary<NSErrorUserInfoKey,id> *)#>
//
    NSString* description = error.localizedDescription;
    NSString* failureReason = error.localizedFailureReason;
    NSString* fileName = [[url filePathURL] lastPathComponent];

    NSString* avfaudioErrorCodePrefix = @"(com.apple.coreaudio.avfaudio error ";
    NSRange range = [description rangeOfString:avfaudioErrorCodePrefix];

    if (action == nil) {
        action = @"process";
    }

    if (range.length > 0) {
        NSString* goodPart = [description substringToIndex:range.location];
        NSString* trigraph = [NSError stringFromOSStatus:error.code];
        
        if (failureReason == nil) {
            failureReason = [NSString stringWithFormat:@"%@ returned '%@' (%ld) when trying to %@",
                             error.domain,
                             trigraph,
                             error.code,
                             action];
        }
        description = goodPart;
        if (url != nil) {
            failureReason = [failureReason stringByAppendingFormat:@" '%@'.", fileName];
        } else {
            failureReason = [failureReason stringByAppendingString:@"."];
        }
    }
    if (failureReason == nil) {
        failureReason = [NSString stringWithFormat:@"Tried to %@ \"%@\".", action, fileName];
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
