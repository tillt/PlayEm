//
//  ConcurrentAccessDictionary.h
//  PlayEm
//
//  Created by Till Toenshoff on 11.02.24.
//  Copyright © 2024 Till Toenshoff. All rights reserved.
//

#import <Foundation/Foundation.h>

/// Concurrent Access Mutable Dictionary
/// session_712__asynchronous_design_patterns_with_blocks_gcd_and_xpc.pdf

NS_ASSUME_NONNULL_BEGIN

@interface ConcurrentAccessDictionary<__covariant KeyType, __covariant ObjectType> : NSObject

- (id _Nullable)objectForKey:(id)aKey;
- (void)setObject:(id)anObject forKey:(id<NSCopying>)aKey;
- (void)removeObjectForKey:(id)aKey;
- (void)removeAllObjects;
- (NSArray*)allKeys;

@end

NS_ASSUME_NONNULL_END
