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

typedef NS_ENUM(NSInteger, APWindowType) { APWindowTypeNone = 0, APWindowTypeHanning, APWindowTypeHamming, APWindowTypeBlackman };

/// Create a DCT setup for 1D transforms over the mel filter count.
vDSP_DFT_Setup initDCT(void);

/// Log-scale helper for waveform magnitudes.
double logVolume(const double input);

/// Convert amplitude to decibels, clamping non-positive inputs.
double dB(double amplitude);

/// Create/destroy FFT setup for windowed FFT operations.
FFTSetup initFFT(void);
void destroyFFT(FFTSetup setup);

/// Convert linear FFT magnitudes into a logarithmically scaled vector.
float* initLogMap(void);
void destroyLogMap(float* map);
void logscaleFFT(float* map, float* frequencyData);

/// Perform an in-place FFT on a window of audio samples.
///
/// - Parameters:
///   - fft: vDSP FFT setup.
///   - data: Time-domain samples (overwritten by windowing).
///   - numberOfFrames: Frame count (power-of-two, matches kWindowSamples).
///   - frequencyData: Output magnitudes (length kFrequencyDataLength).
///   - windowType: Windowing function to apply before the FFT.
void performFFT(FFTSetup fft, float* data, size_t numberOfFrames, float* frequencyData, APWindowType windowType);

/// Convert FFT magnitudes into a mel vector (length kScaledFrequencyDataLength).
///
/// Uses a wide mel bank (~20 Hz–20 kHz) and assumes input magnitudes of length kFrequencyDataLength (as produced by performFFT);
/// overwrites the buffer with mel bins. No band remapping, tilt, or resampling is applied here.
void melScaleFFT(float* frequencyData);

#endif /* AudioProcessing_h */
