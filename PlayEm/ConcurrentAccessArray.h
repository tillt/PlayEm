//
//  ConcurrentAccessArray.h
//  PlayEm
//
//  Created by Till Toenshoff on 11.02.24.
//  Copyright © 2024 Till Toenshoff. All rights reserved.
//

#import <Foundation/NSArray.h>

/// Concurrent Access Mutable Array
/// session_712__asynchronous_design_patterns_with_blocks_gcd_and_xpc.pdf

NS_ASSUME_NONNULL_BEGIN

@interface ConcurrentAccessArray : NSMutableArray

@end

NS_ASSUME_NONNULL_END
