//
//  AudioProcessing.m
//  PlayEm
//
//  Created by Till Toenshoff on 10.12.22.
//  Copyright © 2022 Till Toenshoff. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <simd/simd.h>
#import "AudioProcessing.h"

const size_t kScaledFrequencyDataLength = 256;
const size_t kFrequencyDataLength = kScaledFrequencyDataLength * 4;

/// The number of mel filter banks. UNUSED ATM!
const int kFilterBankCount = 40;

// This is wrong but beautiful. It should be times 4. As a result, we only see
// half the frequency band - that is, only the lower 11khz.
const size_t kWindowSamples = kFrequencyDataLength * 8;

double logVolume(const double input)
{
    // Use a logarithmic scale as that is much closer to what we perceive. Neatly fake
    // ourselves into the slope.
    return log10(10.0 + (input * 100.0f)) - 1.0f;
}

vDSP_DFT_Setup initDCT(void)
{
    //vDSP_Length(
    return vDSP_DCT_CreateSetup(NULL, 1 << (unsigned int)(round(log2((float)kFilterBankCount))), vDSP_DCT_II);
}

FFTSetup initFFT(void)
{
    return vDSP_create_fftsetup(round(log2(kWindowSamples)), kFFTRadix2);
}

void destroyFFT(FFTSetup setup)
{
    vDSP_destroy_fftsetup(setup);
}

void destroyLogMap(float* map)
{
    assert(map);
    free(map);
}

float* initLogMap(void)
{
    float* map = malloc(sizeof(float) * kFrequencyDataLength);
    /*
                  /  x - x0                                \
          y = 10^|  ------- * (log(y1) - log(y0)) + log(y0) |
                  \ x1 - x0                                /
     */
    for (int i=0; i < kFrequencyDataLength;i++) {
        float fraction = (float)((kFrequencyDataLength-1) - i) / kFrequencyDataLength;
        map[i] = (kScaledFrequencyDataLength-1) - powf(10.0f, fraction * log10f(kScaledFrequencyDataLength));
    }
    return map;
}

COMPLEX_SPLIT* allocComplexSplit(size_t strideLength)
{
    // Altivec's functions rely on 16-byte aligned memory locations. We use `malloc` here to make
    // sure the buffers fit that limit.
    float* outReal = (float*)malloc(sizeof(float) * strideLength);
    float* outImaginary = (float*)malloc(sizeof(float) * strideLength);
    COMPLEX_SPLIT* output = (COMPLEX_SPLIT*)malloc(sizeof(COMPLEX_SPLIT));
    output->realp = outReal;
    output->imagp = outImaginary;
    return output;
}

void performDFT(vDSP_DFT_Setup dct, float* data, size_t numberOfFrames, float* frequencyData)
{
    static float* hanningWindow = NULL;
    if (hanningWindow == NULL) {
        hanningWindow = (float*)malloc(sizeof(float) * numberOfFrames);
        vDSP_hann_window(hanningWindow, numberOfFrames, vDSP_HANN_DENORM);
    }
 
    vDSP_vmul(data, 1,
              hanningWindow, 1,
              data, 1,
              numberOfFrames);

    vDSP_DCT_Execute(dct, data, frequencyData);
}

typedef void(^windowingFunction)(int numberOfFrames, float* data);

static windowingFunction kNoWindowingBlock = ^(int numberOfFrames, float* data){};

static windowingFunction kHanningBlock = ^(int numberOfFrames, float* data){
    static float* window = NULL;
    if (window == NULL) {
        window = (float*)malloc(sizeof(float) * numberOfFrames);
        vDSP_hann_window(window, numberOfFrames, vDSP_HANN_DENORM);
    }
    // Apply hanning window function vector.
    vDSP_vmul(data, 1,
              window, 1,
              data, 1,
              numberOfFrames);
};

static windowingFunction kHammingBlock = ^(int numberOfFrames, float* data){
    static float* window = NULL;
    if (window == NULL) {
        window = (float*)malloc(sizeof(float) * numberOfFrames);
        vDSP_hamm_window(window, numberOfFrames, 0);
    }
    // Apply hamming window function vector.
    vDSP_vmul(data, 1,
              window, 1,
              data, 1,
              numberOfFrames);
};

static windowingFunction kBlackmanBlock = ^(int numberOfFrames, float* data){
    static float* window = NULL;
    if (window == NULL) {
        window = (float*)malloc(sizeof(float) * numberOfFrames);
        vDSP_blkman_window(window, numberOfFrames, 0);
    }
    // Apply blackman window function vector.
    vDSP_vmul(data, 1,
              window, 1,
              data, 1,
              numberOfFrames);
};

void performFFT(FFTSetup fft, float* data, size_t numberOfFrames, float* frequencyData)
{
    const windowingFunction windowing = kBlackmanBlock;

    const float fftNormFactor = 1.0f / kFrequencyDataLength;

    // 2^(round(log2(numberOfFrames)).
    const size_t framesOver2 = numberOfFrames / 2;
    //const size_t framesOver2 = numberOfFrames;
    const int bufferLog2 = round(log2(numberOfFrames));

    windowing((int)numberOfFrames, data);
  
    static COMPLEX_SPLIT* output = NULL;
    static COMPLEX_SPLIT* computeBuffer = NULL;
    if (output == NULL) {
        // Altivec's functions rely on 16-byte aligned memory locations. We use `malloc` here to make
        // sure the buffers fit that limit.
        output = allocComplexSplit(framesOver2);
        computeBuffer = allocComplexSplit(framesOver2);
    }

    // Put all of the even numbered elements into out.real and odd numbered into out.imag.
    vDSP_ctoz((COMPLEX*)data, 2, output, 1, framesOver2);
    // For best possible speed, we are using the buffered variant of that FFT calculation.
    vDSP_fft_zript(fft, output, 1, computeBuffer, bufferLog2, kFFTDirection_Forward);
    // Scale the FFT data.
    vDSP_vsmul(output->realp, 1, &fftNormFactor, output->realp, 1, kFrequencyDataLength);
    vDSP_vsmul(output->imagp, 1, &fftNormFactor, output->imagp, 1, kFrequencyDataLength);
    // Take the absolute value of the output to get in range of 0 to 1.
    vDSP_zvabs(output, 1, frequencyData, 1, kFrequencyDataLength);
}

// Scales the linear frequency domain over into a logarithmic one. Or at least something
// close to that.
void logscaleFFT(float* map, float* frequencyData)
{
    float counters[kScaledFrequencyDataLength+1] = { 0.0f };
    float buffer[kScaledFrequencyDataLength+1] = { 0.0f };
    
    // FIXME: This doesnt seem to result in a homogenous distribution!
    //
    // Distribute velocity in two neighbouring buckets. The right gets the
    // fragment beyond the left position. The one on the left gets 1 - right
    // fragment.
    //
    // Example:
    //  map[i] = 7.26
    //  => rightFragment = 0.26
    //  => leftFragment = 0.74
    //    => buffer[7] = freq[i] * 0.74
    //    => buffer[8] = freq[i] * 0.26
    for (int i=0; i < kFrequencyDataLength;i++) {
        double preComma;
        const double postComma = modf(map[i], &preComma);
        const unsigned int leftIndex = preComma;
        const unsigned int rightIndex =  leftIndex + 1;
        const double rightFragment = postComma;
        const double leftFragment = 1.0f - rightFragment;
        buffer[leftIndex] += frequencyData[i] * leftFragment;
        counters[leftIndex] += leftFragment;
        buffer[rightIndex] += frequencyData[i] * rightFragment;
        counters[rightIndex] += rightFragment;
    }
    buffer[kScaledFrequencyDataLength-1] += buffer[kScaledFrequencyDataLength];
    counters[kScaledFrequencyDataLength-1] += counters[kScaledFrequencyDataLength];
    // Normalize values.
    for (int i=0; i < kScaledFrequencyDataLength;i++) {
        if (counters[i] > 0.0f) {
            buffer[i] /= counters[i];
        }
    }
    memcpy(frequencyData, buffer, kScaledFrequencyDataLength * sizeof(float));
}

float hz2mel(float frequency)
{
    return 2595.0f * log10f(1 + (frequency / 700.0f));
}

float mel2hz(float mel)
{
    return 700.0f * (powf(10, mel / 2595.0f) - 1.0f);
}

/// Populates the specified `melFilterBankFrequencies` with a monotonically increasing series
/// of indices into `frequencyDomainBuffer` that represent evenly spaced mels.
void populateMelFilterBankFrequencies(NSRange frequencyRange, int filterBankCount, int sampleCount, NSMutableArray* melFilterBankFrequencies)
{
    float minMel = hz2mel(frequencyRange.location);
    float maxMel = hz2mel(frequencyRange.location + frequencyRange.length);
    float bankWidth = (maxMel - minMel) / ((float)filterBankCount - 1);

    float mel = minMel;
    for (int i = 0; i  < filterBankCount; i++) {
        float frequency = mel2hz(mel);
        melFilterBankFrequencies[i] = @((int)((frequency / (frequencyRange.location + frequencyRange.length)) * (float)sampleCount));
        mel += bankWidth;
    }
}

/// Populates the specified `filterBank` with a matrix of overlapping triangular windows.
///
/// For each frequency in `melFilterBankFrequencies`, the function creates a row in `filterBank`
/// that contains a triangular window starting at the previous frequency, having a response of `1` at the
/// frequency, and ending at the next frequency.
float* makeFilterBank(NSRange frequencyRange, int sampleCount, int filterBankCount)
{
    /// The `melFilterBankFrequencies` array contains `filterBankCount` elements
    /// that are indices of the `frequencyDomainBuffer`. The indices represent evenly spaced
    /// monotonically incrementing mel frequencies; that is, they're roughly logarithmically spaced as
    /// frequency in hertz.
    NSMutableArray<NSNumber*>* melFilterBankFrequencies = [NSMutableArray array];
    populateMelFilterBankFrequencies(frequencyRange, filterBankCount, sampleCount, melFilterBankFrequencies);

    int capacity = sampleCount * filterBankCount;
    float* filterBank = calloc(capacity, sizeof(float));

    float baseValue = 1;
    float endValue = 0;
    for (int i = 0; i < melFilterBankFrequencies.count;i++) {
        int row = i * sampleCount;

        int startFrequency = melFilterBankFrequencies[MAX(0, i - 1)].intValue;
        int centerFrequency = melFilterBankFrequencies[i].intValue;
        int endFrequency = (i + 1) < melFilterBankFrequencies.count ?
                melFilterBankFrequencies[i + 1].intValue :
                sampleCount - 1;

        float attackWidth = centerFrequency - startFrequency + 1;
        float decayWidth = endFrequency - centerFrequency + 1;

        // Create the attack phase of the triangle.
        if (attackWidth > 0) {
            vDSP_vgen(&endValue,
                      &baseValue,
                      &filterBank[row + startFrequency],
                      1,
                      (vDSP_Length)attackWidth);
        }
        // Create the decay phase of the triangle.
        if (decayWidth > 0) {
            vDSP_vgen(&baseValue,
                      &endValue,
                      &filterBank[row + centerFrequency],
                      1,
                      (vDSP_Length)decayWidth);
        }
    }
    return filterBank;
}


/// Process a frame of raw audio data:
///
/// 1. Perform a forward DFT on the time-domain values.
/// 2. Multiply the `frequencyDomainBuffer` vector by the `filterBank` matrix
/// to generate `sgemmResult` product.
/// 3. Convert the matrix multiply results to decibels.
///
/// The matrix multiply effectively creates a  vector of `filterBankCount` elements that summarises
/// the `sampleCount` frequency-domain values.  For example, given a vector of four frequency-domain
/// values:
/// ```
///  [ 1, 2, 3, 4 ]
/// ```
/// And a filter bank of three filters with the following values:
/// ```
///  [ 0.5, 0.5, 0.0, 0.0,
///    0.0, 0.5, 0.5, 0.0,
///    0.0, 0.0, 0.5, 0.5 ]
/// ```
/// The result contains three values of:
/// ```
///  [ ( 1 * 0.5 + 2 * 0.5) = 1.5,
///     (2 * 0.5 + 3 * 0.5) = 2.5,
///     (3 * 0.5 + 4 * 0.5) = 3.5 ]
/// ```
void performMel(vDSP_DFT_Setup dct, float* values, int sampleCount, float* melData)
{
    const int signalCount = 1;
    const int sgemmResultCount = signalCount * kFilterBankCount;
    const float one[] = { 20000.0f };

    // A matrix of `filterBankCount` rows and `sampleCount` that contains the triangular overlapping
    // windows for each mel frequency.
    static float* filterBank = NULL;
    if (filterBank == NULL) {
        filterBank = makeFilterBank(NSMakeRange(20.0f, 19980.0f), sampleCount, kFilterBankCount);
    }
    
    static COMPLEX* complexData = NULL;
    if (complexData == NULL) {
        complexData = malloc(sampleCount * sizeof(COMPLEX));
    }

    static float* frequencyData = NULL;
    if (frequencyData == NULL) {
        frequencyData = malloc(sampleCount * sizeof(float));
    }

    performDFT(dct, values, sampleCount, frequencyData);
    
    vDSP_vabs(frequencyData, 1, frequencyData, 1, sampleCount);
    
//    cblas_sgemm(CblasRowMajor,
//                CblasTrans,
//                CblasTrans,
//                Int32(MelSpectrogram.signalCount),
//                Int32(MelSpectrogram.filterBankCount),
//                Int32(MelSpectrogram.sampleCount),
//                1,
//                frequencyDomainValuesPtr.baseAddress,
//                Int32(MelSpectrogram.signalCount),
//                filterBank.baseAddress,
//                Int32(MelSpectrogram.sampleCount),
//                0,
//                sgemmResult.baseAddress,
//                Int32(MelSpectrogram.filterBankCount))
    
    // Multiply two matrices...
    cblas_sgemm(CblasRowMajor,
                CblasTrans,
                CblasTrans,
                signalCount,
                kFilterBankCount,
                sampleCount,
                1,
                frequencyData,
                signalCount,
                filterBank,
                sampleCount,
                0,
                melData,
                kFilterBankCount);

    vDSP_vdbcon(melData,
                1,
                one,
                melData,
                1,
                sgemmResultCount,
                0);

    float max = sqrtf(sampleCount);

    for (int i=0; i < kFilterBankCount; i++) {
        melData[i] = sqrtf(melData[i] / max);
    }
}
