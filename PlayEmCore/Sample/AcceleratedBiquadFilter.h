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

@property (strong, nonatomic, readonly) LazySample* sample;

/// vDSP-accelerated biquad filter configured from a LazySample’s format.
///
/// - Parameter sample: Source providing the channel count used to size filter state.
- (id)initWithSample:(LazySample*)sample;

/// Configure the biquad coefficients.
///
/// - Parameters:
///   - frequency: Cutoff in Hz.
///   - resonance: Resonance/Q factor in dB.
///   - nyquistPeriod: 1 / nyquistFrequency (i.e. 1 / (sampleRate/2)).
- (void)calculateParamsWithCutoff:(float)frequency resonance:(float)resonance nyquistPeriod:(float)nyquistPeriod;

/// Apply the filter to deinterleaved channel buffers.
///
/// - Parameters:
///   - inputs: Array of per-channel input pointers (length = sample.sampleFormat.channels).
///   - outputs: Array of per-channel output pointers (same length as inputs).
///   - frameCount: Number of frames to process.
- (void)applyToInputs:(float const* const _Nonnull* _Nonnull)inputs outputs:(float* const _Nonnull* _Nonnull)outputs frames:(size_t)frameCount;

@end

NS_ASSUME_NONNULL_END
