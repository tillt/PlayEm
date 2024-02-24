//
//  ConcurrentAccessDictionary.m
//  PlayEm
//
//  Created by Till Toenshoff on 11.02.24.
//  Copyright © 2024 Till Toenshoff. All rights reserved.
//

#import "ConcurrentAccessDictionary.h"

#import <dispatch/dispatch.h>

@implementation ConcurrentAccessDictionary
{
    dispatch_queue_t _access_queue;
    NSMutableDictionary* _dictionary;
}

- (id)init
{
    self = [super init];
    if (self) {
        _dictionary = [NSMutableDictionary dictionary];
        _access_queue = dispatch_queue_create("tillt.playem.dictionaryaccessqueue", 
                                              DISPATCH_QUEUE_CONCURRENT);
    }
    return self;
}

- (id _Nullable)objectForKey:(id)aKey
{
    __block id obj;
    dispatch_sync(_access_queue, ^{
        obj = [self->_dictionary objectForKey:aKey];
    });
    return obj;
}

- (void)setObject:(id)anObject forKey:(id<NSCopying>)aKey
{
    dispatch_barrier_async(_access_queue, ^{
        [self->_dictionary setObject:anObject forKey:aKey];
    });
}

- (void)removeObjectForKey:(id)aKey
{
    dispatch_barrier_async(_access_queue, ^{
        [self->_dictionary removeObjectForKey:aKey];
    });
}

- (void)removeAllObjects
{
    dispatch_barrier_async(_access_queue, ^{
        [self->_dictionary removeAllObjects];
    });
}

- (NSArray*)allKeys
{
    __block NSArray* keys;
    dispatch_sync(_access_queue, ^{
        keys = [self->_dictionary allKeys];
    });
    return keys;
}

@end
