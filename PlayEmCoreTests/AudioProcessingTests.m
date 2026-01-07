//
//  AudioProcessingTests.m
//  PlayEmCoreTests
//
//  Created by Codex on 01/04/26.
//

#import <XCTest/XCTest.h>

#import "AudioProcessing.h"

@interface AudioProcessingTests : XCTestCase
@end

@implementation AudioProcessingTests

- (void)testFFTPeakForSine
{
    // Generate a 1 kHz sine at 44.1 kHz, one FFT window long.
    const double sampleRate = 44100.0;
    const double frequency = 1000.0;
    float* samples = calloc(kWindowSamples, sizeof(float));
    for (size_t i = 0; i < kWindowSamples; i++) {
        double t = (double) i / sampleRate;
        samples[i] = (float) sin(2.0 * M_PI * frequency * t);
    }

    float* spectrum = calloc(kFrequencyDataLength, sizeof(float));
    FFTSetup fft = initFFT();
    performFFT(fft, samples, kWindowSamples, spectrum, APWindowTypeHanning);

    // Find peak bin.
    size_t peakIndex = 0;
    float peakValue = 0.0f;
    for (size_t i = 0; i < kFrequencyDataLength; i++) {
        if (spectrum[i] > peakValue) {
            peakValue = spectrum[i];
            peakIndex = i;
        }
    }

    // Expected bin for 1 kHz.
    double expectedBin = (frequency * (double) kWindowSamples) / sampleRate;
    XCTAssertLessThan(peakIndex, kFrequencyDataLength);
    XCTAssertTrue(fabs((double) peakIndex - expectedBin) <= 3.0, @"Peak bin %@ not near expected %.2f", @(peakIndex), expectedBin);
    XCTAssertGreaterThan(peakValue, 0.0f);

    destroyFFT(fft);
    free(samples);
    free(spectrum);
}

@end
