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

const size_t kKernelSize = 10;

enum Index { B0 = 0, B1, B2, A1, A2 };

double F[kKernelSize];

@interface AcceleratedBiquadFilter()
{
    vDSP_biquadm_Setup setup;

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
        setup = NULL;
        memset(F, kKernelSize, sizeof(double));

        lastFrequency = -1.0;
        lastResonance = 1E10;
        lastNumChannels = 0;

        threshold = 0.05;
        updateRate = 0.4;

        lastFrequency = 123;
    }
    return self;
}

static inline float filterBadValues(float x) 
{
  return fabs(x) > 1e-15 && fabs(x) < 1e15 && x != 0.0 ? x : 1.0;
}

static inline float squared(float x) { return x * x; }

- (void)calculateParamsWithCutoff:(float)frequency resonance:(float)resonance nyquistPeriod:(float)nyquistPeriod
{
    if (lastFrequency == frequency && lastResonance == resonance && _sample.channels == lastNumChannels) {
        return;
    }
  
    const double frequencyRads = M_PI * frequency * nyquistPeriod;
    const double r = powf(10.0, 0.05 * -resonance);
    const double k  = 0.5 * r * sinf(frequencyRads);
    const double c1 = (1.0 - k) / (1.0 + k);
    const double c2 = (1.0 + c1) * cosf(frequencyRads);
    const double c3 = (1.0 + c1 - c2) * 0.25;
  
    memset(F, kKernelSize, sizeof(double));
    
    int index = 0;
    for (int channel = 0; channel < _sample.channels; channel++) {
        F[index++] = c3;
        F[index++] = c3 + c3;
        F[index++] = c3;
        F[index++] = -c2;
        F[index++] = c1;
    }
    
    // As long as we have the same number of channels, we can use Accelerate's function to update the filter.
    if (setup != NULL && _sample.channels == lastNumChannels) {
        vDSP_biquadm_SetTargetsDouble(setup, 
                                      F,
                                      updateRate,
                                      threshold,
                                      0,
                                      0,
                                      1,
                                      _sample.channels);
    } else {
        // Otherwise, we need to deallocate and create new storage for the filter definition. 
        // NOTE: this should never be done from within the audio render thread.
        if (setup != NULL) {
            vDSP_biquadm_DestroySetup(setup);
        }
        setup = vDSP_biquadm_CreateSetup(F, 1, _sample.channels);
  }
  
  lastFrequency = frequency;
  lastResonance = resonance;
  lastNumChannels = _sample.channels;
}


/**
   Apply the filter to a collection of audio samples.

   @param input  the array of samples to process
   @param output the storage for the filtered results
   @param frameCount the number of samples to process in the sequences
   */
- (void)applyToInput:(const float*)input output:(float*)output frames:(size_t)frameCount
{
    //assert(lastNumChannels_ == ins.size() && lastNumChannels_ == outs.size());
    vDSP_biquadm(setup,
                 (float const* __nonnull* __nonnull)input, (vDSP_Stride)1,
                 (float * __nonnull * __nonnull)output, (vDSP_Stride)1,
                 (vDSP_Length)frameCount);
}

void magnitudes(float const* frequencies, size_t count, float inverseNyquist, float* magnitudes)
{
    float scale = M_PI * inverseNyquist;
    while (count-- > 0) {
        float theta = scale * *frequencies++;
        float zReal = cosf(theta);
        float zImag = sinf(theta);

        float zReal2 = squared(zReal);
        float zImag2 = squared(zImag);
        float numerReal = F[B0] * (zReal2 - zImag2) + F[B1] * zReal + F[B2];
        float numerImag = 2.0 * F[B0] * zReal * zImag + F[B1] * zImag;
        float numerMag = sqrt(squared(numerReal) + squared(numerImag));

        float denomReal = zReal2 - zImag2 + F[A1] * zReal + F[A2];
        float denomImag = 2.0 * zReal * zImag + F[A1] * zImag;
        float denomMag = sqrt(squared(denomReal) + squared(denomImag));

        float value = numerMag / denomMag;

        *magnitudes++ = 20.0 * log10(filterBadValues(value));
    }
}

@end
