//
//  ReducedVisualSample.h
//  PlayEm
//
//  Created by Till Toenshoff on 29.09.24.
//  Copyright © 2024 Till Toenshoff. All rights reserved.
//

#import "VisualSample.h"

NS_ASSUME_NONNULL_BEGIN

@interface ReducedVisualSample : VisualSample

- (void)prepareWithCallback:(nonnull void (^)(void))callback;

@end

NS_ASSUME_NONNULL_END
