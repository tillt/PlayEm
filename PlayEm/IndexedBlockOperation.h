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
@property (nonatomic, copy) dispatch_block_t block;
@property (nonatomic, assign) BOOL isFinished;
@property (nonatomic, assign) BOOL isCancelled;

- (id)initWithIndex:(size_t)index;
- (void)cancel;
- (void)run:(nonnull void (^)(void))block;
- (void)wait;

@end

NS_ASSUME_NONNULL_END
