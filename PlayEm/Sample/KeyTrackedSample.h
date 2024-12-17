//
//  KeyTrackedSample.h
//  PlayEm
//
//  Created by Till Toenshoff on 06.08.23.
//  Copyright © 2023 Till Toenshoff. All rights reserved.
//

#import <Foundation/Foundation.h>

#ifndef KeyTrackedSample_h
#define KeyTrackedSample_h

NS_ASSUME_NONNULL_BEGIN

@class LazySample;

@interface KeyTrackedSample : NSObject

@property (strong, nonatomic) LazySample* sample;
@property (assign, readonly, nonatomic) BOOL ready;
@property (copy, nonatomic) NSString* key;

- (void)abortWithCallback:(nonnull void (^)(void))block;

- (id)initWithSample:(LazySample*)sample;
- (void)trackKeyAsyncWithCallback:(void (^)(BOOL))callback;

@end

NS_ASSUME_NONNULL_END
#endif /* KeyTrackedSample_h */
