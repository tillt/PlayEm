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

/*! @brief Create a DCT setup for 1D transforms over the mel filter count. */
vDSP_DFT_Setup initDCT(void);

/*! @brief Log-scale helper for waveform magnitudes. */
double logVolume(const double input);

/*! @brief Convert amplitude to decibels, clamping non-positive inputs. */
double dB(double amplitude);

/*! @brief Create/destroy FFT setup for windowed FFT operations. */
FFTSetup initFFT(void);
void destroyFFT(FFTSetup setup);

/*! @brief Convert linear FFT magnitudes into a logarithmically scaled vector.
 */
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

/*! @brief Convert FFT magnitudes into a mel vector (length
   kScaledFrequencyDataLength).
    @discussion Uses a wide mel bank (~20 Hz–20 kHz) and assumes input
   magnitudes of length kFrequencyDataLength (as produced by performFFT);
   overwrites the buffer with mel bins. No band remapping, tilt, or resampling
   is applied here. */
void melScaleFFT(float* frequencyData);

#endif /* AudioProcessing_h */
