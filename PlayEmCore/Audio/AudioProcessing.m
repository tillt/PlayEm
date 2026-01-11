//
//  AudioProcessing.m
//  PlayEm
//
//  Created by Till Toenshoff on 10.12.22.
//  Copyright © 2022 Till Toenshoff. All rights reserved.
//

#import "AudioProcessing.h"

#import <Foundation/Foundation.h>

#include <float.h>
#include <math.h>
#import <simd/simd.h>
#include <stdlib.h>

const size_t kScaledFrequencyDataLength = 256;
const size_t kFrequencyDataLength = kScaledFrequencyDataLength * 4;

/// The number of mel filter banks. Align with the downsampled visual spectrum.
static const int kFilterBankCount = (int) kScaledFrequencyDataLength;

static const float kFFTHighestFrequencyScaleFactor = 20.0f;

// This is wrong but beautiful. It should be times 4. As a result, we only see
// half the frequency band - that is, only the lower 11khz.
const size_t kWindowSamples = kFrequencyDataLength * 4;

typedef struct {
    float* data;
    size_t size;
} APWindowCache;

static APWindowCache gHanningCache = {NULL, 0};
static APWindowCache gHammingCache = {NULL, 0};
static APWindowCache gBlackmanCache = {NULL, 0};

static void freeWindowCache(APWindowCache* cache)
{
    if (cache->data) {
        free(cache->data);
        cache->data = NULL;
        cache->size = 0;
    }
}

static float* windowBufferForType(APWindowType type, size_t numberOfFrames)
{
    APWindowCache* cache = NULL;
    void (*generator)(float*, vDSP_Length, int) = NULL;

    switch (type) {
    case APWindowTypeHanning:
        cache = &gHanningCache;
        generator = vDSP_hann_window;
        break;
    case APWindowTypeHamming:
        cache = &gHammingCache;
        generator = vDSP_hamm_window;
        break;
    case APWindowTypeBlackman:
        cache = &gBlackmanCache;
        generator = vDSP_blkman_window;
        break;
    case APWindowTypeNone:
    default:
        return NULL;
    }

    if (cache->size != numberOfFrames) {
        freeWindowCache(cache);
        cache->data = (float*) malloc(sizeof(float) * numberOfFrames);
        cache->size = numberOfFrames;
        generator(cache->data, numberOfFrames, 0);
    }
    return cache->data;
}

static void clearWindowCaches(void)
{
    freeWindowCache(&gHanningCache);
    freeWindowCache(&gHammingCache);
    freeWindowCache(&gBlackmanCache);
}

double logVolume(const double input)
{
    // Use a logarithmic scale as that is much closer to what we perceive. Neatly
    // fake ourselves into the slope.
    double absoluteValue = fabs(input);
    if (absoluteValue < DBL_EPSILON) {
        return 0.0;
    }
    double sign = input / absoluteValue;

    return sign * (log10(10.0 + (absoluteValue * 100.0f)) - 1.0f);
}

double dB(double amplitude)
{
    if (amplitude <= 0.0) {
        amplitude = 1e-12;  // avoid -inf and log(0)
    }
    return 20. * log10(amplitude);
}

vDSP_DFT_Setup initDCT(void)
{
    // vDSP_Length(
    return vDSP_DCT_CreateSetup(NULL, 1 << (unsigned int) (round(log2((float) kFilterBankCount))), vDSP_DCT_II);
}

FFTSetup initFFT(void)
{
    return vDSP_create_fftsetup(round(log2(kWindowSamples)), kFFTRadix2);
}

static void clearFFTCache(void);
static void clearLogscaleBuffers(void);

void destroyFFT(FFTSetup setup)
{
    vDSP_destroy_fftsetup(setup);
    clearFFTCache();
    clearWindowCaches();
    clearLogscaleBuffers();
}

void destroyLogMap(float* map)
{
    assert(map);
    free(map);
}

float* initLogMap(void)
{
    float* map = malloc(sizeof(float) * kFrequencyDataLength);
    // Map each linear FFT bin onto a fractional logarithmic bin index in the
    // compressed spectrum. For visuals, use a mild easing to keep lows present
    // without overemphasizing highs.
    const float targetBins = (float) (kScaledFrequencyDataLength - 1);
    const float gamma = 0.95f;  // <1 slightly lifts the lower bins
    for (int i = 0; i < kFrequencyDataLength; i++) {
        float fraction = (float) i / (float) (kFrequencyDataLength - 1);  // 0..1 across linear bins
        float eased = powf(fraction, gamma);
        map[i] = targetBins * eased;
    }
    return map;
}

COMPLEX_SPLIT* allocComplexSplit(size_t strideLength)
{
    // Altivec's functions rely on 16-byte aligned memory locations. We use
    // `malloc` here to make sure the buffers fit that limit.
    float* outReal = (float*) malloc(sizeof(float) * strideLength);
    float* outImaginary = (float*) malloc(sizeof(float) * strideLength);
    COMPLEX_SPLIT* output = (COMPLEX_SPLIT*) malloc(sizeof(COMPLEX_SPLIT));
    output->realp = outReal;
    output->imagp = outImaginary;
    return output;
}

void performDFT(vDSP_DFT_Setup dct, float* data, size_t numberOfFrames, float* frequencyData)
{
    float* hanningWindow = windowBufferForType(APWindowTypeHanning, numberOfFrames);

    vDSP_vmul(data, 1, hanningWindow, 1, data, 1, numberOfFrames);

    vDSP_DCT_Execute(dct, data, frequencyData);
}

typedef struct {
    COMPLEX_SPLIT* output;
    COMPLEX_SPLIT* computeBuffer;
    float* scaleVector;
    size_t framesOver2;
} APFFTCache;

static void freeComplexSplit(COMPLEX_SPLIT* split)
{
    if (!split)
        return;
    free(split->realp);
    free(split->imagp);
    free(split);
}

static APFFTCache* fftCache(void)
{
    static APFFTCache cache = {NULL, NULL, NULL, 0};
    return &cache;
}

static void clearFFTCache(void)
{
    APFFTCache* cache = fftCache();
    freeComplexSplit(cache->output);
    freeComplexSplit(cache->computeBuffer);
    if (cache->scaleVector) {
        free(cache->scaleVector);
    }
    cache->output = NULL;
    cache->computeBuffer = NULL;
    cache->scaleVector = NULL;
    cache->framesOver2 = 0;
}

void performFFT(FFTSetup fft, float* data, size_t numberOfFrames, float* frequencyData, APWindowType windowType)
{
    const size_t framesOver2 = numberOfFrames / 2;
    const int bufferLog2 = round(log2(numberOfFrames));
    NSCAssert((1 << bufferLog2) == numberOfFrames, @"numberOfFrames must be power of two");

    // Apply windowing function if requested.
    float* window = windowBufferForType(windowType, numberOfFrames);
    if (window) {
        vDSP_vmul(data, 1, window, 1, data, 1, numberOfFrames);
    }

    APFFTCache* cache = fftCache();
    if (cache->framesOver2 != framesOver2) {
        clearFFTCache();
        cache->output = allocComplexSplit(framesOver2);
        cache->computeBuffer = allocComplexSplit(framesOver2);
        cache->scaleVector = malloc(framesOver2 * sizeof(float));
        cache->framesOver2 = framesOver2;
        for (size_t i = 0; i < framesOver2; i++) {
            const float factor = 1.0f + (((float) i / (float) framesOver2) * (kFFTHighestFrequencyScaleFactor - 1.0f));
            cache->scaleVector[i] = factor;
        }
    }

    // Put all of the even numbered elements into out.real and odd numbered into
    // out.imag.
    vDSP_ctoz((COMPLEX*) data, 2, cache->output, 1, framesOver2);
    // For best possible speed, we are using the buffered variant of that FFT
    // calculation.
    vDSP_fft_zript(fft, cache->output, 1, cache->computeBuffer, bufferLog2, kFFTDirection_Forward);
    // Take the absolute value of the output.
    // NOTE: We intentionally copy only the first kFrequencyDataLength bins, dropping the upper half
    // of the FFT before visualization/mel-scaling. This keeps the visual focus on lows/mids and
    // reduces workload. melScaleFFT further caps the mel bank to the source Nyquist.
    vDSP_zvabs(cache->output, 1, frequencyData, 1, kFrequencyDataLength);
    // Scale the FFT data.
    float scale = framesOver2 / 2.0f;
    vDSP_vsdiv(frequencyData, 1, &scale, frequencyData, 1, kFrequencyDataLength);
    // Get the power of the values by sqrt(A[n]**2 + A[n]**2).
    vDSP_vdist(frequencyData, 1, frequencyData, 1, frequencyData, 1, kFrequencyDataLength);
}

// Scales the linear frequency domain over into a logarithmic one. Or at least
// something close to that.
static float* gLogscaleCounters = NULL;
static float* gLogscaleBuffer = NULL;
static size_t gLogscaleSize = 0;

static void ensureLogscaleBuffers(void)
{
    const size_t needed = kScaledFrequencyDataLength + 1;
    if (gLogscaleSize == needed) {
        return;
    }
    free(gLogscaleCounters);
    free(gLogscaleBuffer);
    gLogscaleCounters = (float*) calloc(needed, sizeof(float));
    gLogscaleBuffer = (float*) calloc(needed, sizeof(float));
    gLogscaleSize = needed;
}

static void clearLogscaleBuffers(void)
{
    free(gLogscaleCounters);
    free(gLogscaleBuffer);
    gLogscaleCounters = NULL;
    gLogscaleBuffer = NULL;
    gLogscaleSize = 0;
}

void logscaleFFT(float* map, float* frequencyData)
{
    ensureLogscaleBuffers();
    if (!gLogscaleCounters || !gLogscaleBuffer) {
        return;
    }
    memset(gLogscaleCounters, 0, gLogscaleSize * sizeof(float));
    memset(gLogscaleBuffer, 0, gLogscaleSize * sizeof(float));

    // FIXME: This doesnt seem to result in a homogenous distribution!
    // One point here may be that the scaling of more than 2
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
    for (int i = 0; i < kFrequencyDataLength; i++) {
        double preComma;
        const double postComma = modf(map[i], &preComma);
        const unsigned int leftIndex = (unsigned int) MIN(preComma, (double) (kScaledFrequencyDataLength - 1));
        const unsigned int rightIndex = MIN(leftIndex + 1, (const unsigned int) kScaledFrequencyDataLength);
        const double rightFragment = postComma;
        const double leftFragment = 1.0f - rightFragment;
        gLogscaleBuffer[leftIndex] += frequencyData[i] * leftFragment;
        gLogscaleCounters[leftIndex] += leftFragment;
        gLogscaleBuffer[rightIndex] += frequencyData[i] * rightFragment;
        gLogscaleCounters[rightIndex] += rightFragment;
    }
    gLogscaleBuffer[kScaledFrequencyDataLength - 1] += gLogscaleBuffer[kScaledFrequencyDataLength];
    gLogscaleCounters[kScaledFrequencyDataLength - 1] += gLogscaleCounters[kScaledFrequencyDataLength];

    // Normalize values.
    for (int i = 0; i < kScaledFrequencyDataLength; i++) {
        if (gLogscaleCounters[i] > 0.0f) {
            gLogscaleBuffer[i] /= gLogscaleCounters[i];
        }
        // Gentle visual companding to lift quieter bins for display without
        // changing dynamics too much.
        gLogscaleBuffer[i] = powf(gLogscaleBuffer[i], 0.8f);
    }
    memcpy(frequencyData, gLogscaleBuffer, kScaledFrequencyDataLength * sizeof(float));
}

float hz2mel(float frequency)
{
    return 2595.0f * log10f(1 + (frequency / 700.0f));
}

float mel2hz(float mel)
{
    return 700.0f * (powf(10, mel / 2595.0f) - 1.0f);
}

/// Populates the specified `melFilterBankFrequencies` with a monotonically
/// increasing series of indices into `frequencyDomainBuffer` that represent
/// evenly spaced mels.
void populateMelFilterBankFrequencies(NSRange frequencyRange, int filterBankCount, int sampleCount, NSMutableArray* melFilterBankFrequencies)
{
    float minMel = hz2mel(frequencyRange.location);
    float maxMel = hz2mel(frequencyRange.location + frequencyRange.length);
    float bankWidth = (maxMel - minMel) / ((float) filterBankCount - 1);

    float mel = minMel;
    for (int i = 0; i < filterBankCount; i++) {
        float frequency = mel2hz(mel);
        melFilterBankFrequencies[i] = @((int) ((frequency / (frequencyRange.location + frequencyRange.length)) * (float) sampleCount));
        mel += bankWidth;
    }
}

/// Populates the specified `filterBank` with a matrix of overlapping triangular
/// windows.
///
/// For each frequency in `melFilterBankFrequencies`, the function creates a row
/// in `filterBank` that contains a triangular window starting at the previous
/// frequency, having a response of `1` at the frequency, and ending at the next
/// frequency.
float* makeFilterBank(NSRange frequencyRange, int sampleCount, int filterBankCount)
{
    /// The `melFilterBankFrequencies` array contains `filterBankCount` elements
    /// that are indices of the `frequencyDomainBuffer`. The indices represent
    /// evenly spaced monotonically incrementing mel frequencies; that is, they're
    /// roughly logarithmically spaced as frequency in hertz.
    NSMutableArray<NSNumber*>* melFilterBankFrequencies = [NSMutableArray array];
    populateMelFilterBankFrequencies(frequencyRange, filterBankCount, sampleCount, melFilterBankFrequencies);

    int capacity = sampleCount * filterBankCount;
    float* filterBank = calloc(capacity, sizeof(float));

    float baseValue = 1;
    float endValue = 0;
    for (int i = 0; i < melFilterBankFrequencies.count; i++) {
        int row = i * sampleCount;

        int startFrequency = melFilterBankFrequencies[MAX(0, i - 1)].intValue;
        int centerFrequency = melFilterBankFrequencies[i].intValue;
        int endFrequency = (i + 1) < melFilterBankFrequencies.count ? melFilterBankFrequencies[i + 1].intValue : sampleCount - 1;

        float attackWidth = centerFrequency - startFrequency + 1;
        float decayWidth = endFrequency - centerFrequency + 1;

        // Create the attack phase of the triangle.
        if (attackWidth > 0) {
            vDSP_vgen(&endValue, &baseValue, &filterBank[row + startFrequency], 1, (vDSP_Length) attackWidth);
        }
        // Create the decay phase of the triangle.
        if (decayWidth > 0) {
            vDSP_vgen(&baseValue, &endValue, &filterBank[row + centerFrequency], 1, (vDSP_Length) decayWidth);
        }
    }
    return filterBank;
}

// Variant that biases center frequencies toward the top end (biasExp < 1.0
// increases high-frequency density).
static float* makeBiasedFilterBank(NSRange frequencyRange, int sampleCount, int filterBankCount, float biasExp)
{
    NSMutableArray<NSNumber*>* centers = [NSMutableArray arrayWithCapacity:filterBankCount];
    double minHz = frequencyRange.location;
    double maxHz = frequencyRange.location + frequencyRange.length;
    double span = maxHz - minHz;
    for (int i = 0; i < filterBankCount; i++) {
        double t = (filterBankCount == 1) ? 0.0 : (double) i / (double) (filterBankCount - 1);
        double biased = pow(t, biasExp);
        double hz = minHz + biased * span;
        int bin = (int) ((hz / maxHz) * (double) sampleCount);
        centers[i] = @(bin);
    }

    int capacity = sampleCount * filterBankCount;
    float* filterBank = calloc(capacity, sizeof(float));

    float baseValue = 1.0f;
    float endValue = 0.0f;
    for (int i = 0; i < filterBankCount; i++) {
        int row = i * sampleCount;
        int startFrequency = centers[MAX(0, i - 1)].intValue;
        int centerFrequency = centers[i].intValue;
        int endFrequency = (i + 1) < filterBankCount ? centers[i + 1].intValue : (sampleCount - 1);

        float attackWidth = centerFrequency - startFrequency + 1;
        float decayWidth = endFrequency - centerFrequency + 1;

        if (attackWidth > 0) {
            vDSP_vgen(&endValue, &baseValue, &filterBank[row + startFrequency], 1, (vDSP_Length) attackWidth);
        }
        if (decayWidth > 0) {
            vDSP_vgen(&baseValue, &endValue, &filterBank[row + centerFrequency], 1, (vDSP_Length) decayWidth);
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
/// The matrix multiply effectively creates a  vector of `filterBankCount`
/// elements that summarises the `sampleCount` frequency-domain values.  For
/// example, given a vector of four frequency-domain values:
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
// Convert linear FFT magnitudes into mel-spaced bins of length
// kScaledFrequencyDataLength in-place. sampleRate caps the upper frequency to the source Nyquist.
void melScaleFFT(float* frequencyData, double sampleRate, double renderRate)
{
    static float* filterBank = NULL;
    static float* melBuffer = NULL;
    static float lastMaxHz = 0.0f;
    float maxHz = 20000.0f;  // cap visuals to ~20 kHz regardless of source rate
    size_t sampleCount = kFrequencyDataLength;

    if (filterBank == NULL || fabsf(lastMaxHz - maxHz) > 1.0f) {
        if (filterBank != NULL) {
            free(filterBank);
            filterBank = NULL;
        }
        filterBank = makeFilterBank(NSMakeRange(20.0f, maxHz - 20.0f), (int) sampleCount, kFilterBankCount);
        lastMaxHz = maxHz;
    }
    if (melBuffer == NULL) {
        int err = posix_memalign((void**) &melBuffer, 64, sizeof(float) * kFilterBankCount);
        assert(err == 0 && melBuffer != NULL);
    }

    // Ensure magnitudes are non-negative.
    vDSP_vabs(frequencyData, 1, frequencyData, 1, kFrequencyDataLength);

    // Resample/warp the linear spectrum so 0..maxHz spans the entire buffer.
    static float* warped = NULL;
    static size_t warpedSize = 0;
    if (warpedSize != kFrequencyDataLength) {
        free(warped);
        warped = calloc(kFrequencyDataLength, sizeof(float));
        warpedSize = kFrequencyDataLength;
    }
    size_t activeBins = kFrequencyDataLength;
    if (renderRate > 0.0) {
        double renderNyquist = renderRate / 2.0;
        if (renderNyquist > 0.0) {
            activeBins = (size_t) llrint((maxHz / renderNyquist) * (double) kFrequencyDataLength);
            activeBins = MIN(MAX(activeBins, (size_t) 1), (size_t) kFrequencyDataLength);
        }
    }
    for (size_t j = 0; j < kFrequencyDataLength; j++) {
        double srcPos = ((double) j / (double) (kFrequencyDataLength - 1)) * (double) (activeBins - 1);
        size_t idx = (size_t) floor(srcPos);
        double frac = srcPos - (double) idx;
        float a = frequencyData[idx];
        float b = (idx + 1 < activeBins) ? frequencyData[idx + 1] : a;
        warped[j] = a + (float) (frac * (b - a));
    }
    // Preserve overall energy when expanding a smaller active range across the full buffer.
    if (activeBins > 0 && activeBins < kFrequencyDataLength) {
        // Scale gently to preserve some brightness without overamplifying highs.
        float energyScale = sqrtf((float) activeBins / (float) kFrequencyDataLength);
        vDSP_vsmul(warped, 1, &energyScale, warped, 1, kFrequencyDataLength);
    }

    // Project the warped linear bins into the mel bank.
    cblas_sgemm(CblasRowMajor, CblasNoTrans, CblasTrans, 1, kFilterBankCount, (int) sampleCount, 1.0f, warped, (int) kFrequencyDataLength,
                filterBank, (int) sampleCount, 0.0f, melBuffer, kFilterBankCount);

    // Use RMS of the mel bins as reference so single loud bins (e.g., bass) don't
    // suppress mids/highs.
    float meanSquare = 0.0f;
    vDSP_measqv(melBuffer, 1, &meanSquare, kFilterBankCount);
    float rms = sqrtf(meanSquare);
    float scale = MIN(1.0f / rms, 2.0);
    vDSP_vsmul(melBuffer, 1, &scale, frequencyData, 1, kFilterBankCount);
    float zero = 0.0f;
    float one = 1.0f;
    vDSP_vclip(frequencyData, 1, &zero, &one, frequencyData, 1, kFilterBankCount);
}
