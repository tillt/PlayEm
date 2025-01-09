//
//  AcceleratedBiquadFilter.h
//  PlayEm
//
//  Created by Till Toenshoff on 06.10.23.
//  Copyright © 2023 Till Toenshoff. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class LazySample;

@interface AcceleratedBiquadFilter : NSObject

@property (strong, nonatomic) LazySample* sample;

- (id)initWithSample:(LazySample*)sample;
- (void)calculateParamsWithCutoff:(float)frequency resonance:(float)resonance nyquistPeriod:(float)nyquistPeriod;
- (void)applyToInput:(const float*)input output:(float*)output frames:(size_t)frameCount;

@end

NS_ASSUME_NONNULL_END
