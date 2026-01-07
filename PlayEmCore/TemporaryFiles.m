//
//  TemporaryFiles.m
//  PlayEm
//
//  Created by Till Toenshoff on 11/22/25.
//  Copyright © 2025 Till Toenshoff. All rights reserved.
//

#import "TemporaryFiles.h"

NS_ASSUME_NONNULL_BEGIN

@implementation TemporaryFiles

+ (NSString*)pathForTemporaryFileWithPrefix:(NSString*)prefix
{
    NSString* result;
    CFUUIDRef uuid;
    CFStringRef uuidStr;

    uuid = CFUUIDCreate(NULL);
    assert(uuid != NULL);

    uuidStr = CFUUIDCreateString(NULL, uuid);
    assert(uuidStr != NULL);

    result = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"%@-%@", prefix, uuidStr]];
    assert(result != nil);

    CFRelease(uuidStr);
    CFRelease(uuid);

    return result;
}

@end

NS_ASSUME_NONNULL_END
