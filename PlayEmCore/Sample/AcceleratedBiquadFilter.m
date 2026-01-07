//
//  AcceleratedBiquadFilter.m
//  PlayEm
//
//  Created by Till Toenshoff on 06.10.23.
//  Copyright © 2023 Till Toenshoff. All rights reserved.
//

#import "AcceleratedBiquadFilter.h"

#include <Accelerate/Accelerate.h>

#import "LazySample.h"

static const size_t kCoeffsPerChannel = 5;  // B0, B1, B2, A1, A2

@interface AcceleratedBiquadFilter () {
    vDSP_biquadm_Setup setup;

    double* coeffs;
    size_t coeffCount;

    float lastFrequency;
    float lastResonance;
    size_t lastNumChannels;

    float threshold;
    float updateRate;
}

@end

@implementation AcceleratedBiquadFilter

- (id)initWithSample:(LazySample*)sample
{
    self = [super init];
    if (self) {
        _sample = sample;
        setup = NULL;
        coeffs = NULL;
        coeffCount = 0;

        lastFrequency = -1.0;
        lastResonance = 1E10;
        lastNumChannels = 0;

        threshold = 0.05;
        updateRate = 0.4;

        lastFrequency = 123;
    }
    return self;
}

- (void)dealloc
{
    if (setup != NULL) {
        vDSP_biquadm_DestroySetup(setup);
        setup = NULL;
    }
    if (coeffs != NULL) {
        free(coeffs);
        coeffs = NULL;
    }
}

- (void)calculateParamsWithCutoff:(float)frequency resonance:(float)resonance nyquistPeriod:(float)nyquistPeriod
{
    if (lastFrequency == frequency && lastResonance == resonance && _sample.sampleFormat.channels == lastNumChannels) {
        return;
    }

    const double frequencyRads = M_PI * frequency * nyquistPeriod;
    const double r = powf(10.0, 0.05 * -resonance);
    const double k = 0.5 * r * sinf(frequencyRads);
    const double c1 = (1.0 - k) / (1.0 + k);
    const double c2 = (1.0 + c1) * cosf(frequencyRads);
    const double c3 = (1.0 + c1 - c2) * 0.25;

    const size_t neededCoeffs = (size_t) _sample.sampleFormat.channels * kCoeffsPerChannel;
    if (neededCoeffs != coeffCount) {
        free(coeffs);
        coeffs = calloc(neededCoeffs, sizeof(double));
        coeffCount = neededCoeffs;
    }
    if (coeffs == NULL) {
        return;
    }
    memset(coeffs, 0, neededCoeffs * sizeof(double));

    size_t index = 0;
    for (int channel = 0; channel < _sample.sampleFormat.channels; channel++) {
        coeffs[index++] = c3;
        coeffs[index++] = c3 + c3;
        coeffs[index++] = c3;
        coeffs[index++] = -c2;
        coeffs[index++] = c1;
    }

    // As long as we have the same number of channels, we can use Accelerate's
    // function to update the filter.
    if (setup != NULL && _sample.sampleFormat.channels == lastNumChannels) {
        vDSP_biquadm_SetTargetsDouble(setup, coeffs, updateRate, threshold, 0, 0, 1, _sample.sampleFormat.channels);
    } else {
        // Otherwise, we need to deallocate and create new storage for the filter
        // definition. NOTE: this should never be done from within the audio render
        // thread.
        if (setup != NULL) {
            vDSP_biquadm_DestroySetup(setup);
        }
        setup = vDSP_biquadm_CreateSetup(coeffs, 1, _sample.sampleFormat.channels);
    }

    lastFrequency = frequency;
    lastResonance = resonance;
    lastNumChannels = _sample.sampleFormat.channels;
}

/**
   Apply the filter to a collection of deinterleaved audio samples.

   @param inputs  array of per-channel input pointers (length = channel count)
   @param outputs array of per-channel output pointers (length = channel count)
   @param frameCount the number of frames to process
   */
- (void)applyToInputs:(float const* const _Nonnull* _Nonnull)inputs outputs:(float* const _Nonnull* _Nonnull)outputs frames:(size_t)frameCount
{
    if (setup == NULL) {
        return;
    }
    vDSP_biquadm(setup, inputs, (vDSP_Stride) 1, outputs, (vDSP_Stride) 1, (vDSP_Length) frameCount);
}

@end
