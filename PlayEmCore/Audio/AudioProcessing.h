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

typedef NS_ENUM(NSInteger, APWindowType) {
    APWindowTypeNone = 0,
    APWindowTypeHanning,
    APWindowTypeHamming,
    APWindowTypeBlackman
};

vDSP_DFT_Setup initDCT(void);
double logVolume(const double input);
double dB(double amplitude);

FFTSetup initFFT(void);
void destroyFFT(FFTSetup setup);
void melScaleFFT(float* frequencyData);
float* initLogMap(void);
void destroyLogMap(float* map);
void logscaleFFT(float* map, float* frequencyData);

/*! @brief Perform an in-place FFT on a window of audio samples.
    @param fft vDSP FFT setup.
    @param data Time-domain samples (overwritten by windowing).
    @param numberOfFrames Frame count (power-of-two, matches kWindowSamples).
    @param frequencyData Output magnitudes (length kFrequencyDataLength).
    @param windowType Windowing function to apply before the FFT. */
void performFFT(FFTSetup fft, float* data, size_t numberOfFrames, float* frequencyData, APWindowType windowType);

/*! @brief Convert FFT magnitudes into a mel vector (length kScaledFrequencyDataLength).
    @discussion Uses a wide mel bank (~20 Hz–20 kHz) and assumes input magnitudes of length
    kFrequencyDataLength (as produced by performFFT); overwrites the buffer with mel bins.
    No band remapping, tilt, or resampling is applied here. */
void melScaleFFT(float* frequencyData);

#endif /* AudioProcessing_h */
