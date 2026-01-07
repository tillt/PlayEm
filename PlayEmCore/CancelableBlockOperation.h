//
//  CancelableBlockOperation.h
//  PlayEm
//
//  Created by Till Toenshoff on 12.10.22.
//  Copyright © 2022 Till Toenshoff. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 A tiny cancelable wrapper around a single dispatch block.

 Call `-run:` to wrap work, enqueue `dispatchBlock` yourself on a queue, and
 observe `isCancelled`, `isCompleted`, and `isDone` to decide whether to use the
 result. `-cancel` marks the operation done and cancels the wrapped block;
 `-wait` joins if enqueued. No indexing or queueing logic is built in.
 */
@interface CancelableBlockOperation : NSObject

/// Optional payload/result buffer owned by the caller (e.g., filled inside the
/// wrapped block).
@property (nonatomic, strong, nullable) NSMutableData* data;
@property (nonatomic, copy, readonly, nullable) dispatch_block_t dispatchBlock;
/// YES if the block was cancelled before running to completion.
@property (atomic, assign, readonly) BOOL isCancelled;
/// YES if the block ran to completion.
@property (atomic, assign, readonly) BOOL isCompleted;
/// YES if the block will not run further (cancelled or completed).
@property (atomic, assign, readonly) BOOL isDone;

- (id)init;
/// Cancel the wrapped block (if enqueued) and mark as done.
- (void)cancel;
/// Wait for the wrapped block to finish if it was enqueued.
- (void)wait;
/// Wrap the provided block; caller must dispatch `dispatchBlock` to a queue.
- (void)run:(nonnull void (^)(void))block;

@end

NS_ASSUME_NONNULL_END
