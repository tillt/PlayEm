//
//  NSData+Hashing.m
//  PlayEm
//
//  Created by Till Toenshoff on 01/10/26.
//  Copyright © 2026 Till Toenshoff. All rights reserved.
//

#import "NSData+Hashing.h"

#import <CommonCrypto/CommonDigest.h>
#import <objc/runtime.h>

static const void* kShortSHA256AssociationKey = &kShortSHA256AssociationKey;

@implementation NSData (Hashing)

- (NSString*)shortSHA256
{
    NSString* cached = objc_getAssociatedObject(self, kShortSHA256AssociationKey);
    if (cached != nil) {
        return cached;
    }

    unsigned char digest[CC_SHA256_DIGEST_LENGTH] = {0};
    CC_SHA256(self.bytes, (CC_LONG) self.length, digest);

    NSMutableString* hash = [NSMutableString stringWithCapacity:24];
    for (int i = 0; i < 12; i++) {
        [hash appendFormat:@"%02x", digest[i]];
    }

    objc_setAssociatedObject(self, kShortSHA256AssociationKey, hash, OBJC_ASSOCIATION_COPY_NONATOMIC);
    return hash;
}

@end
