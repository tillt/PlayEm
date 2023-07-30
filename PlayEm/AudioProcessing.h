//
//  AudioProcessing.h
//  PlayEm
//
//  Created by Till Toenshoff on 10.12.22.
//  Copyright © 2022 Till Toenshoff. All rights reserved.
//

#ifndef AudioProcessing_h
#define AudioProcessing_h

#import <Accelerate/Accelerate.h>

extern const size_t kFrequencyDataLength;
extern const size_t kScaledFrequencyDataLength;
extern const size_t kWindowSamples;

vDSP_DFT_Setup initDCT(void);

FFTSetup initFFT(void);
void destroyFFT(FFTSetup setup);
void performFFT(FFTSetup fft, float* data, size_t numberOfFrames, float* frequencyData);

void performMel(FFTSetup fft, float* values, int sampleCount, float* melData);

float* initLogMap(void);
void destroyLogMap(float* map);
void logscaleFFT(float* map, float* frequencyData);

#endif /* AudioProcessing_h */
