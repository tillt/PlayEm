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
        _isFinished = NO;
    }
    return self;
}

- (BOOL)isCancelled
{
    return dispatch_block_testcancel(_dispatchBlock) != 0;
}

- (void)run:(nonnull void (^)(void))block
{
    self.dispatchBlock = dispatch_block_create(DISPATCH_BLOCK_NO_QOS_CLASS, block);
}

- (void)cancelAndWait
{
    if (_dispatchBlock != nil) {
        dispatch_block_cancel(_dispatchBlock);
        dispatch_block_wait(_dispatchBlock, DISPATCH_TIME_FOREVER);
    }
}

- (void)dealloc
{
//    if (_block != nil) {
//        dispatch_block_cancel(_block);
//        dispatch_block_wait(_block, DISPATCH_TIME_FOREVER);
//    }
}

@end
