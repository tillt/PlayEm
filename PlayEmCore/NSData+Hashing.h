//
//  NSData+Hashing.h
//  PlayEm
//
//  Created by Till Toenshoff on 01/10/26.
//  Copyright © 2026 Till Toenshoff. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface NSData (Hashing)

/// Returns a short SHA-256 hex digest (first 12 bytes) for the data, cached per instance.
- (NSString*)shortSHA256;

@end
