//
//  ConcurrentAccessArray.m
//  PlayEm
//
//  Created by Till Toenshoff on 11.02.24.
//  Copyright © 2024 Till Toenshoff. All rights reserved.
//

#import "ConcurrentAccessArray.h"

#import <dispatch/dispatch.h>

/// Concurrent Access Mutable Array
/// session_712__asynchronous_design_patterns_with_blocks_gcd_and_xpc.pdf

@implementation ConcurrentAccessArray
{
    dispatch_queue_t _access_queue;
}

- (id)init
{
    self = [super init];
    if (self) {
        _access_queue = dispatch_queue_create("tillt.playem.arrayaccessqueue", DISPATCH_QUEUE_CONCURRENT);
    }
    return self;
}

- (id)objectAtIndex:(NSUInteger)index 
{
    __block id obj;
    dispatch_sync(_access_queue, ^{
        obj = [super objectAtIndex:index];
    });
    return obj;
}

- (void)insertObject:(id)obj atIndex:(NSUInteger)index 
{
    dispatch_barrier_async(_access_queue, ^{
        [super insertObject:obj atIndex:index];
    });
}

- (void)removeObjectAtIndex:(NSUInteger)index 
{
    dispatch_barrier_async(_access_queue, ^{
        [super removeObjectAtIndex:index];
    });
}

@end
