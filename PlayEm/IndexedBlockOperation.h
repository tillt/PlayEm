//
//  IndexedBlockOperation.h
//  PlayEm
//
//  Created by Till Toenshoff on 12.10.22.
//  Copyright © 2022 Till Toenshoff. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface IndexedBlockOperation : NSObject

@property (nonatomic, assign) size_t index;
@property (nonatomic, strong) NSMutableData* data;
@property (nonatomic, copy, nullable) dispatch_block_t dispatchBlock;
@property (nonatomic, assign) BOOL isFinished;
@property (nonatomic, assign) BOOL isCancelled;

- (id)initWithIndex:(size_t)index;
- (void)cancelAndWait;
- (void)run:(nonnull void (^)(void))block;

@end

NS_ASSUME_NONNULL_END
