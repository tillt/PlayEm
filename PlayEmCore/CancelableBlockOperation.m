//
//  CancelableBlockOperation.m
//  PlayEm
//
//  Created by Till Toenshoff on 12.10.22.
//  Copyright © 2022 Till Toenshoff. All rights reserved.
//

#import "CancelableBlockOperation.h"

@interface CancelableBlockOperation ()
@property (nonatomic, copy, readwrite, nullable) dispatch_block_t dispatchBlock;
@property (atomic, assign, readwrite) BOOL isCancelled;
@property (atomic, assign, readwrite) BOOL isCompleted;
@property (atomic, assign, readwrite) BOOL isDone;
@end

@implementation CancelableBlockOperation

- (id)init
{
    self = [super init];
    if (self) {
        _dispatchBlock = nil;
        _isCancelled = NO;
        _isCompleted = NO;
        _isDone = NO;
    }
    return self;
}

- (void)run:(nonnull void (^)(void))block
{
    __weak typeof(self) weakSelf = self;
    _dispatchBlock = dispatch_block_create(DISPATCH_BLOCK_NO_QOS_CLASS, ^{
        if (weakSelf) {
            block();
            weakSelf.isCompleted = YES;
            weakSelf.isDone = YES;
        }
    });
}

- (void)cancel
{
    _isCancelled = YES;
    _isDone = YES;
    if (_dispatchBlock) {
        dispatch_block_cancel(_dispatchBlock);
    }
}

- (void)wait
{
    if (_dispatchBlock) {
        dispatch_block_wait(_dispatchBlock, DISPATCH_TIME_FOREVER);
        _dispatchBlock = nil;
    }
}

- (void)dealloc
{
}


@end
