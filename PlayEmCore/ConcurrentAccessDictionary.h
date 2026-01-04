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
/*!
 @brief A simple thread-safe dictionary wrapper with synchronous write semantics.
 @discussion Reads run synchronously on a concurrent queue. Writes and removals use barrier-sync,
             guaranteeing write-before-read ordering (callers block until the mutation completes).
             Stored objects themselves are not made thread-safe by this container.
 */
- (id _Nullable)objectForKey:(id)aKey;
- (void)setObject:(id)anObject forKey:(id<NSCopying>)aKey;
- (void)removeObjectForKey:(id)aKey;
- (void)removeAllObjects;
- (NSArray*)allKeys;

@end

NS_ASSUME_NONNULL_END
