//
//  IndexedBlockOperation.m
//  PlayEm
//
//  Created by Till Toenshoff on 12.10.22.
//  Copyright © 2022 Till Toenshoff. All rights reserved.
//

#import "IndexedBlockOperation.h"

@implementation IndexedBlockOperation

- (id)initWithIndex:(size_t)index
{
    self = [super init];
    if (self) {
        _index = index;
        _dispatchBlock = nil;
    }
    return self;
}

- (BOOL)isFinished
{
    return  dispatch_block_wait(_dispatchBlock, DISPATCH_TIME_NOW) == 0;
}

- (BOOL)isCancelled
{
    return dispatch_block_testcancel(_dispatchBlock) != 0;
}

- (void)run:(nonnull void (^)(void))block
{
    _dispatchBlock = dispatch_block_create(DISPATCH_BLOCK_NO_QOS_CLASS, block);
}

- (void)cancel
{
    dispatch_block_cancel(_dispatchBlock);
}

- (void)wait
{
    dispatch_block_wait(_dispatchBlock, DISPATCH_TIME_FOREVER);
    _dispatchBlock = nil;
}

- (void)dealloc
{
}


@end
