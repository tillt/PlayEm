//
//  BeatTrackedSample.m
//  PlayEm
//
//  Created by Till Toenshoff on 06.08.23.
//  Copyright © 2023 Till Toenshoff. All rights reserved.
//
#include <stdatomic.h>
#import <Foundation/Foundation.h>

#import "BeatTrackedSample.h"
#import "LazySample.h"
#import "IndexedBlockOperation.h"

#define BEATS_BY_AUBIO

#ifdef BEATS_BY_AUBIO
#define AUBIO_UNSTABLE 1
#include "aubio/aubio.h"

/* structure to store object state */
struct debug_aubio_tempo_t {
  aubio_specdesc_t * od;         /** onset detection */
  aubio_pvoc_t * pv;             /** phase vocoder */
  aubio_peakpicker_t * pp;       /** peak picker */
  aubio_beattracking_t * bt;     /** beat tracking */
  cvec_t * fftgrain;             /** spectral frame */
  fvec_t * of;                   /** onset detection function value */
  fvec_t * dfframe;              /** peak picked detection function buffer */
  fvec_t * out;                  /** beat tactus candidates */
  fvec_t * onset;                /** onset results */
  smpl_t silence;                /** silence parameter */
  smpl_t threshold;              /** peak picking threshold */
  sint_t blockpos;               /** current position in dfframe */
  uint_t winlen;                 /** dfframe bufsize */
  uint_t step;                   /** dfframe hopsize */
  uint_t samplerate;             /** sampling rate of the signal */
  uint_t hop_size;               /** get hop_size */
  uint_t total_frames;           /** total frames since beginning */
  uint_t last_beat;              /** time of latest detected beat, in samples */
  sint_t delay;                  /** delay to remove to last beat, in samples */
  uint_t last_tatum;             /** time of latest detected tatum, in samples */
  uint_t tatum_signature;        /** number of tatum between each beats */
};
#else
// Effectively downsamples input from 44.1kHz -> 11kHz
static const long kDownsampleFactor = 4;
static const double kSilenceThreshold = 0.1;
static const double kMinimumTempo = 60.0;
static const double kMaximumTempo = 180.0;
static const double kDefaultTempo = 120.0;
static const double kHostTempoLinkToleranceInBpm = 16.0;

static const int kParamToleranceMinValue = 1;
static const int kParamToleranceMaxValue = 100;
static const int kParamToleranceDefaultValue = 75;
static const float kParamPeriodMinValue = 1.0f;
static const float kParamPeriodMaxValue = 10.0f;
static const float kParamPeriodDefaultValue = 2.0f;

static const int kBpmHistorySize = 200;
#endif

// When ironing the grid for long sequences of const tempo we use
// a 25 ms tolerance because this small of a difference is inaudible
// This is > 2 * 12 ms, the step width of the QM beat detector.
// We are actually using a smaller hop-size of 256 frames for the libaubio
// beat detector. However, the parameters seem good enough.
static const double kMaxSecsPhaseError = 0.025;
// This is set to avoid to use a constant region during an offset shift.
// That happens for instance when the beat instrument changes.
static const double kMaxSecsPhaseErrorSum = 0.1;
static const int kMaxOutliersCount = 1;
static const int kMinRegionBeatCount = 10;

// Lowpass cutoff frequency.
//static const float kParamFilterMinValue = 50.0f;
//static const float kParamFilterMaxValue = 500.0f;
static const float kParamFilterDefaultValue = 120.0f;

@interface BeatTrackedSample()
{
}

@property (assign, nonatomic) size_t windowWidth;
//@property (strong, nonatomic) NSMutableDictionary* operations;
@property (strong, nonatomic) NSMutableArray<NSMutableData*>* sampleBuffers;
@property (strong, nonatomic) NSMutableDictionary* beatEventPages;
@property (strong, nonatomic) NSMutableData* coarseBeats;
@property (strong, nonatomic) dispatch_block_t queueOperation;

@end

@implementation BeatTrackedSample
{
    atomic_int _beatTrackDone;
    
    size_t _pages;
    
    size_t _hopSize;
    size_t _tileWidth;
    
    float _lastTempo;
    
    size_t _iteratePageIndex;
    size_t _iterateEventIndex;
    
    // Variables used by the lopass filter
    BOOL _filterEnabled;
    float _filterFrequency;
    
    double _filterOutput;
    double _filterConstant;

#ifdef BEATS_BY_AUBIO
    fvec_t* _aubio_input_buffer;
    fvec_t* _aubio_output_buffer;
    
    aubio_tempo_t* _aubio_tempo;
#else
    double currentBPM;
    double runningBPM;
    
    // Cached parameters
    int tolerance;
    float period;
    //BOOL useHostTempo;


    // Used to calculate the running BPM
    double bpmHistory[kBpmHistorySize];
    // Running BPM shown in GUI
    //double runningBpm;
    // State of the processing algorithm, will be true if the current sample is part of the beat
    bool currentlyInsideBeat;
    // Highest known amplitude found since initialization (or reset)
    double highestAmplitude;
    // Highest known amplitude found within a period
    double highestAmplitudeInPeriod;
    // Running average of the number of samples found between beats. Used to calculate the actual BPM.
    double beatLengthRunningAverage;
    // Used to calculate the BPM in combination with beatLengthRunningAverage
    unsigned long numSamplesSinceLastBeat;
    // Smallest possible BPM allowed, can improve accuracy if input source known to be within a given BPM range
    double minimumAllowedBpm;
    // Largest possible BPM allowed, can improve accuracy if input source known to be within a given BPM range
    double maximumAllowedBpm;
    // Poor man's downsampling
    unsigned long samplesToSkip;
    // Used to calculate the period, which in turn effects the total accuracy of the algorithm
    unsigned long numSamplesProcessed;
    // Wait at least this many samples before another beat can be detected. Used to reduce the possibility
    // of crazy fast tempos triggered by static wooshing and other such things which may fool the trigger
    // detection algorithm.
    unsigned long cooldownPeriodInSamples;
#endif
}

- (void)clearBpmHistory
{
#ifndef BEATS_BY_AUBIO
    memset(bpmHistory, kBpmHistorySize, sizeof(double));
    filterOutput = 0.0f;
    numSamplesProcessed = 0;
    highestAmplitude = 0.0;
    highestAmplitudeInPeriod = 0.0;
    currentlyInsideBeat = false;
    beatLengthRunningAverage = 0;
    numSamplesSinceLastBeat = 0;
    currentBPM = 0.0;
    runningBPM = 0.0;
#endif
}

- (id)initWithSample:(LazySample*)sample framesPerPixel:(double)framesPerPixel
{
    self = [super init];
    if (self) {
        _sample = sample;
        assert(framesPerPixel);
        _framesPerPixel = framesPerPixel;
        _tileWidth = 256;
        _windowWidth = 1024;
        _hopSize = _windowWidth / 4;
        _sampleBuffers = [NSMutableArray array];
        _lastTempo = 0.0f;
#ifdef BEATS_BY_AUBIO
        _aubio_input_buffer = NULL;
        _aubio_output_buffer = NULL;
        _aubio_tempo = NULL;
#else
#endif
        _beats = [NSMutableDictionary dictionary];

        unsigned long long framesNeeded = _hopSize * 1024;
        for (int channel = 0; channel < sample.channels; channel++) {
            NSMutableData* buffer = [NSMutableData dataWithCapacity:framesNeeded * _sample.frameSize];
            [_sampleBuffers addObject:buffer];
        }
    }
    return self;
}

- (void)setupTracking
{
    [self cleanupTracking];
#ifdef BEATS_BY_AUBIO
    _aubio_input_buffer = new_fvec((unsigned int)_hopSize);
    assert(_aubio_input_buffer);
    _aubio_output_buffer = new_fvec((unsigned int)1);
    assert(_aubio_output_buffer);
    _aubio_tempo = new_aubio_tempo("default",
                                   (unsigned int)_windowWidth,
                                   (unsigned int)_hopSize,
                                   (unsigned int)_sample.rate);
    aubio_tempo_set_threshold(_aubio_tempo, 0.75f);
    assert(_aubio_tempo);
#else
    tolerance = kParamToleranceDefaultValue;
    period = kParamPeriodDefaultValue;
#endif
    _filterEnabled = YES;
    _filterFrequency = kParamFilterDefaultValue;
    _filterConstant = _sample.rate / (2.0f * M_PI * _filterFrequency);
}

- (void)cleanupTracking
{
#ifdef BEATS_BY_AUBIO
    if (_aubio_input_buffer != NULL) {
        del_fvec(_aubio_input_buffer);
    }
    _aubio_input_buffer = NULL;

    if (_aubio_output_buffer != NULL) {
        del_fvec(_aubio_output_buffer);
    }
    _aubio_output_buffer = NULL;
    
    if (_aubio_tempo != NULL) {
        del_aubio_tempo(_aubio_tempo);
    }
    _aubio_tempo = NULL;
#else
    minimumAllowedBpm = kMinimumTempo;
    maximumAllowedBpm = kMaximumTempo;
    cooldownPeriodInSamples = (unsigned long)(_sample.rate * (60.0f / (float)maximumAllowedBpm));
    samplesToSkip = kDownsampleFactor;
    filterOutput = 0.0;
    filterConstant = 0.0;
    [self clearBpmHistory];
#endif
}

- (void)dealloc
{
}

struct _BeatsParserContext {
    unsigned long int eventIndex;
};

void beatsContextReset(BeatsParserContext* context)
{
    context->eventIndex = 0;
}

- (NSData* _Nullable)beatsFromOrigin:(size_t)origin
{
    unsigned long pageIndex = origin / _tileWidth;
    return [_beats objectForKey:[NSNumber numberWithLong:pageIndex]];
}


- (unsigned long long)framesPerBeat:(float)tempo
{
    return _sample.rate * (tempo / (60.0f * 4.0f) );
}

- (void)trackBeatsAsyncWithCallback:(void (^)(BOOL))callback;
{
    __block BOOL done = NO;
    _queueOperation = dispatch_block_create(DISPATCH_BLOCK_NO_QOS_CLASS, ^{
        done = [self trackBeats];
    });
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), _queueOperation);
    dispatch_block_notify(_queueOperation, dispatch_get_main_queue(), ^{
        self->_ready = done;
        callback(done);
    });
}

/*
 Locate and retrieve regions with a constant beat detection. Such region
 has a phase error that remains below a threshold. With the given detection method,
 we hardly ever get to 16 beats of stable detection - even with enabled lowpass filter.

 This is mostly a copy of code from MixxxDJ.
 from https://github.com/mixxxdj/mixxx/blob/8354c8e0f57a635acb7f4b3cc16b9745dc83312c/src/track/beatutils.cpp#L51
 */
- (NSData*)retrieveConstantRegions
{
    NSLog(@"pass two: locate constant regions");

    // Original comment doesnt apply exactly -- we are not using the QM detector but the
    // libaubio one. Anyway, tje rest applies equally.
    // The aubio detector has a step size of 256 frames @ 44100 Hz. This means that
    // Single beats have has a jitter of +- 6 ms around the actual position.
    // Expressed in BPM it means we have for instance steps of these BPM value around 120 BPM
    // 117.454 - 120.185 - 123.046 - 126.048
    // A pure electronic 120.000 BPM track will have many 120,185 BPM beats and a few
    // 117,454 BPM beats to adjust the collected offset.
    // This function irons these adjustment beats by adjusting every beat to the average of
    // a likely constant region.

    // Therefore we loop through the coarse beats and calculate the average beat
    // length from the first beat.
    // A inner loop checks for outliers using the momentary average as beat length.
    // once we have found an average with only single outliers, we store the beats using the
    // current average to adjust them by up to +-6 ms.
    // Than we start with the region from the found beat to the end.

    const size_t maxPhaseError = kMaxSecsPhaseError * _sample.rate;
    const size_t maxPhaseErrorSum = kMaxSecsPhaseErrorSum * _sample.rate;
    size_t leftIndex = 0;
    const unsigned long long *coarseBeats = _coarseBeats.bytes;
    const size_t coarseBeatCount = _coarseBeats.length / sizeof(unsigned long long);
    size_t rightIndex = coarseBeatCount - 1;

    NSMutableData* constantRegions = [NSMutableData data];
    // Go through all the beats there are...
    while (leftIndex < coarseBeatCount - 1) {
        NSAssert(rightIndex > leftIndex, @"somehow we ended up with an invalid right index");
        
        // Calculate the frame count between the first and the last detected beat.
        double meanBeatLength = (coarseBeats[rightIndex] - coarseBeats[leftIndex]) / (rightIndex - leftIndex);

        int outliersCount = 0;
        unsigned long long ironedBeat = coarseBeats[leftIndex];
        double phaseErrorSum = 0;
        size_t i = leftIndex + 1;

        for (; i <= rightIndex; ++i) {
            ironedBeat += meanBeatLength;
            const double phaseError = ironedBeat - coarseBeats[i];
            phaseErrorSum += phaseError;

            if (fabs(phaseError) > maxPhaseError) {
                outliersCount++;
                // the first beat must not be an outlier.
                if (outliersCount > kMaxOutliersCount || i == leftIndex + 1) {
                    break;
                }
            }
            if (fabs(phaseErrorSum) > maxPhaseErrorSum) {
                // we drift away in one direction, the meanBeatLength is not optimal.
                break;
            }
        }
        if (i > rightIndex) {
            // Verify that the first and the last beat are not correction beats in the same direction
            // as this would bend meanBeatLength unfavorably away from the optimum.
            double regionBorderError = 0;
            if (rightIndex > leftIndex + 2) {
                const double firstBeatLength = coarseBeats[leftIndex + 1] - coarseBeats[leftIndex];
                const double lastBeatLength = coarseBeats[rightIndex] - coarseBeats[rightIndex - 1];
                regionBorderError = fabs(firstBeatLength + lastBeatLength - (2 * meanBeatLength));
            }
            if (regionBorderError < maxPhaseError / 2) {
                // We have found a constant enough region.
                const unsigned long long firstBeat = coarseBeats[leftIndex];
                // store the regions for the later stages
                BeatConstRegion region = { firstBeat, meanBeatLength };
                [constantRegions appendBytes:&region length:sizeof(BeatConstRegion)];
                // continue with the next region.
                leftIndex = rightIndex;
                rightIndex = coarseBeatCount - 1;
                continue;
            }
        }
        // Try a by one beat smaller region
        rightIndex--;
    }

    // Add a final region with zero length to mark the end.
    BeatConstRegion region = { coarseBeats[coarseBeatCount - 1], 0 };
    [constantRegions appendBytes:&region length:sizeof(BeatConstRegion)];

    return constantRegions;
}

/*
 This is mostly a copy of code from MixxxDJ.
 from https://github.com/mixxxdj/mixxx/blob/8354c8e0f57a635acb7f4b3cc16b9745dc83312c/src/track/beatutils.cpp#L140
 */
- (double)makeConstBpm:(NSData*)constantRegions firstBeat:(unsigned long long*)pFirstBeat
{
    NSAssert(constantRegions.length > 0, @"no constant regions found");

    // We assume here the track was recorded with an unhear-able static metronome.
    // This metronome is likely at a full BPM.
    // The track may has intros, outros and bridges without detectable beats.
    // In these regions the detected beat might is floating around and is just wrong.
    // The track may also has regions with different rhythm giving instruments. They
    // have a different shape of onsets and introduce a static beat offset.
    // The track may also have break beats or other issues that makes the detector
    // hook onto a beat that is by an integer fraction off the original metronome.

    // This code aims to find the static metronome and a phase offset.

    // Find the longest region somewhere in the middle of the track to start with.
    // At least this region will be have finally correct annotated beats.

    int midRegionIndex = 0;
    double longestRegionLength = 0;
    double longestRegionBeatLength = 0;
    int longestRegionNumberOfBeats = 0;
    size_t regionsCount = constantRegions.length / sizeof(BeatConstRegion);
    
    const BeatConstRegion* regions = constantRegions.bytes;
    
    NSLog(@"pass three: identify longest constant region from out of %ld", regionsCount);

    for (int i = 0; i < regionsCount - 1; ++i) {
        double length = regions[i + 1].firstBeatFrame - regions[i].firstBeatFrame;
        int beatCount = (int)((length / regions[i].beatLength) + 0.5);
        if (beatCount > longestRegionNumberOfBeats) {
            longestRegionLength = length;
            longestRegionBeatLength = regions[i].beatLength;
            longestRegionNumberOfBeats = beatCount;
            midRegionIndex = i;
            NSLog(@"%d: %.0f %.0f", i, length, regions[i].beatLength);
        }
    }

    if (longestRegionLength == 0) {
        // Could not infer a tempo
        return 0.0;
    }
    
    NSLog(@"longest constant region: %.2f frames, %d beats", longestRegionLength, longestRegionNumberOfBeats);

    double longestRegionBeatLengthMin = longestRegionBeatLength - ((kMaxSecsPhaseError * _sample.rate) / longestRegionNumberOfBeats);
    double longestRegionBeatLengthMax = longestRegionBeatLength + ((kMaxSecsPhaseError * _sample.rate) / longestRegionNumberOfBeats);

    int startRegionIndex = midRegionIndex;

    NSLog(@"pass four: find a region at the beginning of the track with a similar tempo and phase");

    // Find a region at the beginning of the track with a similar tempo and phase
    for (int i = 0; i < midRegionIndex; ++i) {
        const double length = regions[i + 1].firstBeatFrame - regions[i].firstBeatFrame;
        const int numberOfBeats = (int)((length / regions[i].beatLength) + 0.5);
        if (numberOfBeats < kMinRegionBeatCount) {
            // Request short regions, too unstable.
            continue;
        }
        const double thisRegionBeatLengthMin = regions[i].beatLength - ((kMaxSecsPhaseError * _sample.rate) / numberOfBeats);
        const double thisRegionBeatLengthMax = regions[i].beatLength + ((kMaxSecsPhaseError * _sample.rate) / numberOfBeats);
        // check if the tempo of the longest region is part of the rounding range of this region
        if (longestRegionBeatLength > thisRegionBeatLengthMin && longestRegionBeatLength < thisRegionBeatLengthMax) {
            // Now check if both regions are at the same phase.
            const double newLongestRegionLength = regions[midRegionIndex + 1].firstBeatFrame - regions[i].firstBeatFrame;

            double beatLengthMin = MAX(longestRegionBeatLengthMin, thisRegionBeatLengthMin);
            double beatLengthMax = MIN(longestRegionBeatLengthMax, thisRegionBeatLengthMax);

            const int maxNumberOfBeats = (int)(round(newLongestRegionLength / beatLengthMin));
            const int minNumberOfBeats = (int)(round(newLongestRegionLength / beatLengthMax));

            if (minNumberOfBeats != maxNumberOfBeats) {
                // Ambiguous number of beats, find a closer region.
                NSLog(@"ambiguous number of beats - %d != %d - find a closer region ...", minNumberOfBeats, maxNumberOfBeats);
                continue;
            }
            const int numberOfBeats = minNumberOfBeats;
            const double newBeatLength = newLongestRegionLength / numberOfBeats;
            if (newBeatLength > longestRegionBeatLengthMin && newBeatLength < longestRegionBeatLengthMax) {
                longestRegionLength = newLongestRegionLength;
                longestRegionBeatLength = newBeatLength;
                longestRegionNumberOfBeats = numberOfBeats;
                longestRegionBeatLengthMin = longestRegionBeatLength - ((kMaxSecsPhaseError * _sample.rate) / longestRegionNumberOfBeats);
                longestRegionBeatLengthMax = longestRegionBeatLength + ((kMaxSecsPhaseError * _sample.rate) / longestRegionNumberOfBeats);
                startRegionIndex = i;
                break;
            }
        }
    }

    NSLog(@"startRegionIndex: %d", startRegionIndex);
    
    NSLog(@"pass five: find a region at the end of the track with a similar tempo and phase");
    
    // Find a region at the end of the track with similar tempo and phase
    for (size_t i = regionsCount - 2; i > midRegionIndex; --i) {
        const double length = regions[i + 1].firstBeatFrame - regions[i].firstBeatFrame;
        const int numberOfBeats = (int)((length / regions[i].beatLength) + 0.5);
        if (numberOfBeats < kMinRegionBeatCount) {
            continue;
        }
        const double thisRegionBeatLengthMin = regions[i].beatLength - ((kMaxSecsPhaseError * _sample.rate) / numberOfBeats);
        const double thisRegionBeatLengthMax = regions[i].beatLength + ((kMaxSecsPhaseError * _sample.rate) / numberOfBeats);
        if (longestRegionBeatLength > thisRegionBeatLengthMin && longestRegionBeatLength < thisRegionBeatLengthMax) {
            // Now check if both regions are at the same phase.
            const double newLongestRegionLength = regions[i + 1].firstBeatFrame - regions[startRegionIndex].firstBeatFrame;

            double minBeatLength = MAX(longestRegionBeatLengthMin, thisRegionBeatLengthMin);
            double maxBeatLength = MIN(longestRegionBeatLengthMax, thisRegionBeatLengthMax);

            const int maxNumberOfBeats = (int)(round(newLongestRegionLength / minBeatLength));
            const int minNumberOfBeats = (int)(round(newLongestRegionLength / maxBeatLength));

            if (minNumberOfBeats != maxNumberOfBeats) {
                // Ambiguous number of beats, find a closer region.
                NSLog(@"ambiguous number of beats - %d != %d - find a closer region ...", minNumberOfBeats, maxNumberOfBeats);
                continue;
            }
            const int numberOfBeats = minNumberOfBeats;
            double newBeatLength = newLongestRegionLength / numberOfBeats;
            if (newBeatLength > longestRegionBeatLengthMin && newBeatLength < longestRegionBeatLengthMax) {
                longestRegionLength = newLongestRegionLength;
                longestRegionBeatLength = newBeatLength;
                longestRegionNumberOfBeats = numberOfBeats;
                break;
            }
        }
    }

    NSLog(@"longestRegionNumberOfBeats: %d", longestRegionNumberOfBeats);

    longestRegionBeatLengthMin = longestRegionBeatLength -
            ((kMaxSecsPhaseError * _sample.rate) / longestRegionNumberOfBeats);
    longestRegionBeatLengthMax = longestRegionBeatLength +
            ((kMaxSecsPhaseError * _sample.rate) / longestRegionNumberOfBeats);

    NSLog(@"start: %d, mid: %d, count: %ld, longest: %.2f", startRegionIndex, midRegionIndex, regionsCount, longestRegionLength);
    NSLog(@"first beat: %lld, longest region length: %.2f, number of beats: %d", regions[startRegionIndex].firstBeatFrame, longestRegionLength, longestRegionNumberOfBeats);

    NSLog(@"pass six: create a const region from the first beat of the first region to the last beat of the last region");

    // Create a const region from the first beat of the first region to the last beat of the last region.

    const double minRoundBpm = (double)(60.0 * _sample.rate / longestRegionBeatLengthMax);
    const double maxRoundBpm = (double)(60.0 * _sample.rate / longestRegionBeatLengthMin);
    const double centerBpm = (double)(60.0 * _sample.rate / longestRegionBeatLength);

    const double roundBpm = roundBpmWithinRange(minRoundBpm, centerBpm, maxRoundBpm);
    if (pFirstBeat) {
        // Move the first beat as close to the start of the track as we can. This is
        // a constant beatgrid so "first beat" only affects the anchor point where
        // bpm adjustments are made.
        // This is a temporary fix, ideally the anchor point for the BPM grid should
        // be the first proper downbeat, or perhaps the CUE point.
        const double roundedBeatLength = 60.0 * _sample.rate / roundBpm;
        *pFirstBeat = (unsigned long long)(fmod(regions[startRegionIndex].firstBeatFrame, roundedBeatLength));
    }
    return roundBpm;
}

/*
 This is mostly a copy of code from MixxxDJ.
 from https://github.com/mixxxdj/mixxx/blob/8354c8e0f57a635acb7f4b3cc16b9745dc83312c/src/track/beatutils.cpp#L386
 */
- (unsigned long long)adjustPhase:(unsigned long long)firstBeat bpm:(double)bpm
{
    const double beatLength = 60 * _sample.rate / bpm;
    const unsigned long long startOffset = (unsigned long long)(fmod(firstBeat, beatLength));
    double offsetAdjust = 0;
    double offsetAdjustCount = 0;
    
    const unsigned long long *coarseBeats = _coarseBeats.bytes;
    const size_t coarseBeatCount = _coarseBeats.length / sizeof(unsigned long long);
    
    for (int i = 0;i < coarseBeatCount; i++) {\
        double offset = fmod(coarseBeats[i] - startOffset, beatLength);
        if (offset > beatLength / 2) {
            offset -= beatLength;
        }
        if (fabs(offset) < (kMaxSecsPhaseError * _sample.rate)) {
            offsetAdjust += offset;
            offsetAdjustCount++;
        }
    }
    offsetAdjust /= offsetAdjustCount;
    NSLog(@"adjusting phase by: %.2f", offsetAdjust);
    NSAssert(fabs(offsetAdjust) < (kMaxSecsPhaseError * _sample.rate), @"unexpexted phase adjustment");

    return firstBeat + offsetAdjust;
}

/*
 This is mostly a copy of code from MixxxDJ.
 from https://github.com/mixxxdj/mixxx/blob/8354c8e0f57a635acb7f4b3cc16b9745dc83312c/src/track/beatfactory.cpp#L51
 */
- (void)makePreferredBeats
{
    NSData* constantRegions = [self retrieveConstantRegions];

    if (!constantRegions.length) {
        return;
    }

    unsigned long long firstBeatFrame = 0;
    const double constBPM = [self makeConstBpm:constantRegions firstBeat:&firstBeatFrame];
    const double beatLength = 60 * _sample.rate / constBPM;
    firstBeatFrame = [self adjustPhase:firstBeatFrame bpm:constBPM];

    NSLog(@"first beat frame = %lld with %.2f", firstBeatFrame, constBPM);

    BeatEvent event;
    unsigned long long nextBeatFrame = firstBeatFrame;
    
    int beatIndex = 0;
    while (nextBeatFrame < _sample.frames) {
        event.frame = nextBeatFrame;
        event.bpm = constBPM;
        event.style = BeatEventStyleBeat;
        if (beatIndex == 0) {
            event.style |= BeatEventStyleBar;
        }

        size_t origin = event.frame / self->_framesPerPixel;
        NSNumber* pageKey = [NSNumber numberWithLong:origin / self->_tileWidth];

        NSMutableData* data = [self->_beats objectForKey:pageKey];
        if (data == nil) {
            data = [NSMutableData data];
        }
        
        [data appendBytes:&event length:sizeof(BeatEvent)];
        
        [self->_beats setObject:data forKey:pageKey];
        
        nextBeatFrame += beatLength;
        beatIndex = (beatIndex + 1) % 4;
    };
}

//- (double)calculateBpm
//{
//    NSData* constantRegions = [self retrieveConstantRegions];
//    return [self makeConstBpm:constantRegions firstBeat:nil];
//}

double roundBpmWithinRange(double minBpm, double centerBpm, double maxBpm)
{
    NSLog(@"rounding BPM - min: %.0f, center: %.0f, max: %.0f", minBpm, centerBpm, maxBpm);

    // First try to snap to a full integer BPM
    double snapBpm = (double)round(centerBpm);
    if (snapBpm > minBpm && snapBpm < maxBpm) {
        // Success
        return snapBpm;
    }

    // Probe the reasonable multipliers for 0.5
    const double roundBpmWidth = maxBpm - minBpm;
    if (roundBpmWidth > 0.5) {
        // 0.5 BPM are only reasonable if the double value is not insane
        // or the 2/3 value is not too small.
        if (centerBpm < (double)(85.0)) {
            // this cane be actually up to 175 BPM
            // allow halve BPM values
            return (double)(round(centerBpm * 2) / 2);
        } else if (centerBpm > (double)(127.0)) {
            // optimize for 2/3 going down to 85
            return (double)(round(centerBpm/ 3 * 2) * 3 / 2);
        }
    }

    if (roundBpmWidth > 1.0 / 12) {
        // this covers all sorts of 1/2 2/3 and 3/4 multiplier
        return (double)(round(centerBpm * 12) / 12);
    } else {
        // We are here if we have more that ~75 beats and ~30 s
        // try to snap to a 1/12 Bpm
        snapBpm = (double)(round(centerBpm * 12) / 12);
        if (snapBpm > minBpm && snapBpm < maxBpm) {
            // Success
            return snapBpm;
        }
        // else give up and use the original BPM value.
    }

    return centerBpm;
}

- (BOOL)trackBeats
{
    NSLog(@"beats tracking...");
    [self setupTracking];
    
    float* data[self->_sample.channels];
    const int channels = self->_sample.channels;
    for (int channel = 0; channel < channels; channel++) {
        data[channel] = (float*)((NSMutableData*)self->_sampleBuffers[channel]).bytes;
    }
    unsigned long long sourceWindowFrameOffset = 0LL;
    
    _coarseBeats = [NSMutableData data];
    
    NSLog(@"pass one");
    
    while (sourceWindowFrameOffset < self->_sample.frames) {
        if (dispatch_block_testcancel(self.queueOperation) != 0) {
            NSLog(@"aborted beat detection");
            return NO;
        }
        unsigned long long sourceWindowFrameCount = MIN(self->_hopSize * 1024,
                                                        self->_sample.frames - sourceWindowFrameOffset);
        // This may block for a loooooong time!
        unsigned long long received = [self->_sample rawSampleFromFrameOffset:sourceWindowFrameOffset
                                                                       frames:sourceWindowFrameCount
                                                                      outputs:data];
        
        unsigned long int sourceFrameIndex = 0;
        BeatEvent event;
        while(sourceFrameIndex < received) {
            if (dispatch_block_testcancel(self.queueOperation) != 0) {
                NSLog(@"aborted beat detection");
                return NO;
            }
            
#ifndef BEATS_BY_AUBIO
            double s = 0.0;
            for (int channel = 0; channel < channels; channel++) {
                s += data[channel][sourceFrameIndex];
            }
            s /= (float)channels;
            
            sourceFrameIndex++;
            
            double currentSampleAmplitude;
            
            if(filterEnabled) {
                // Basic lowpass filter (feedback)
                filterOutput += (s - filterOutput) / filterConstant;
                currentSampleAmplitude = fabs(filterOutput);
            }
            else {
                currentSampleAmplitude = fabs(s);
            }
            
            // Find highest peak in the current period
            if(currentSampleAmplitude > highestAmplitudeInPeriod) {
                highestAmplitudeInPeriod = currentSampleAmplitude;
                
                // Is it also the highest value since we started?
                if(currentSampleAmplitude > highestAmplitude) {
                    highestAmplitude = currentSampleAmplitude;
                }
            }
            
            // Downsample by skipping samples
            if(--samplesToSkip <= 0) {
                
                // Beat amplitude trigger has been detected
                if(highestAmplitudeInPeriod >= (highestAmplitude * tolerance / 100.0) &&
                   highestAmplitudeInPeriod > kSilenceThreshold) {
                    
                    // First sample inside of a beat?
                    if(!currentlyInsideBeat && numSamplesSinceLastBeat > cooldownPeriodInSamples) {
                        currentlyInsideBeat = true;
                        double bpm = (_sample.rate * 60.0f) / ((beatLengthRunningAverage + numSamplesSinceLastBeat) / 2);
                        
                        // Check for half-beat patterns. For instance, a song which has a kick drum
                        // at around 70 BPM but an actual tempo of x.
                        double doubledBpm = bpm * 2.0;
                        if(doubledBpm > minimumAllowedBpm && doubledBpm < maximumAllowedBpm) {
                            bpm = doubledBpm;
                        }
                        
                        beatLengthRunningAverage += numSamplesSinceLastBeat;
                        beatLengthRunningAverage /= 2;
                        numSamplesSinceLastBeat = 0;
                        
                        // Check to see that this tempo is within the limits allowed
                        if(bpm > minimumAllowedBpm && bpm < maximumAllowedBpm) {
                            bpmHistory[beatHistoryIndex] = bpm;
                            beatHistoryIndex++;
                            assert(beatHistoryIndex < kBpmHistorySize);
                            NSLog(@"Beat Triggered");
                            NSLog(@"Current BPM %f", bpm);
                            
                            event.frame = sourceWindowFrameOffset + sourceFrameIndex;
                            
                            if (llabs(expectedNextBeatFrame - event.frame) > (_sample.rate / 10)) {
                                NSLog(@"looks like a bad prediction at %lld - %@", event.frame, [_sample beautifulTimeWithFrame:event.frame]);
                            }
                            
                            event.bpm = bpm;
                            event.confidence = 1.0f;
                            event.index = barBeatIndex;
                            
                            barBeatIndex = (barBeatIndex + 1) % 4;
                            
                            expectedNextBeatFrame = event.frame + [self framesPerBeat:event.bpm];
                            NSLog(@"beat at %lld - %.2f bpm, confidence %.4f -- next beat expected at %lld",
                                  event.frame, event.bpm, event.confidence, expectedNextBeatFrame);
                            
                            if (_averageTempo == 0) {
                                _averageTempo = event.bpm;
                            } else {
                                _averageTempo = ((_averageTempo * 9.0f) + event.bpm) / 10.0f;
                            }
                            
                            size_t origin = event.frame / _framesPerPixel;
                            
                            NSNumber* pageKey = [NSNumber numberWithLong:origin / _tileWidth];
                            
                            NSMutableData* data = [_beats objectForKey:pageKey];
                            if (data == nil) {
                                data = [NSMutableData data];
                            }
                            
                            [data appendBytes:&event length:sizeof(BeatEvent)];
                            
                            [_beats setObject:data forKey:pageKey];
                            
                            // Do total BPM and Reset?
                            if(numSamplesProcessed > period * _sample.rate) {
                                runningBPM = 0.0;
                                for(unsigned int historyIndex = 0; historyIndex < beatHistoryIndex; ++historyIndex) {
                                    runningBPM += bpmHistory[historyIndex];
                                }
                                runningBPM /= (double)beatHistoryIndex;
                                beatHistoryIndex = 0;
                                numSamplesProcessed = 0;
                                NSLog(@"Running BPM %f", runningBPM);
                            }
                        } else {
                            // Outside of bpm threshold, ignore
                        }
                    } else {
                        // Not the first beat mark
                        currentlyInsideBeat = false;
                    }
                } else {
                    // Were we just in a beat?
                    if(currentlyInsideBeat) {
                        currentlyInsideBeat = false;
                    }
                }
                
                samplesToSkip = kDownsampleFactor;
                highestAmplitudeInPeriod = 0.0;
            }
            
            ++numSamplesProcessed;
            ++numSamplesSinceLastBeat;
#else
            assert(((struct debug_aubio_tempo_t*)self->_aubio_tempo)->total_frames ==
                   sourceWindowFrameOffset + sourceFrameIndex);
            for (unsigned long int inputFrameIndex = 0;
                 inputFrameIndex < self->_hopSize;
                 inputFrameIndex++) {
                double s = 0.0;
                for (int channel = 0; channel < channels; channel++) {
                    s += data[channel][sourceFrameIndex];
                }
                s /= (float)channels;

                if(self->_filterEnabled) {
                    // Basic lowpass filter (feedback)
                    self->_filterOutput += (s - self->_filterOutput) / self->_filterConstant;
                    s = self->_filterOutput;
                }
                
                self->_aubio_input_buffer->data[inputFrameIndex] = s;
                sourceFrameIndex++;
            }
            
            aubio_tempo_do(self->_aubio_tempo, self->_aubio_input_buffer, self->_aubio_output_buffer);
            const bool beat = fvec_get_sample(self->_aubio_output_buffer, 0) != 0.f;
            if (beat) {
                event.frame = aubio_tempo_get_last(self->_aubio_tempo);
                [self->_coarseBeats appendBytes:&event.frame length:sizeof(unsigned long long)];
            }
#endif
        };
        
        sourceWindowFrameOffset += received;
    };

    [self cleanupTracking];

    // Generate a constant grid pattern out of the detected beats.
    [self makePreferredBeats];

    NSLog(@"...beats tracking done");

    return YES;
}

- (NSString *)description
{
    return [NSString stringWithFormat:@"Average tempo: %.0f BPM", _lastTempo];
}

- (void)abortWithCallback:(void (^)(void))callback;
{
    if (_queueOperation != NULL) {
        dispatch_block_cancel(_queueOperation);
        dispatch_block_notify(_queueOperation, dispatch_get_main_queue(), ^{
            callback();
        });
    } else {
        callback();
    }
}

- (BOOL)isReady
{
    return _beatTrackDone;
}

- (float)currentTempo:(BeatEventIterator*)iterator
{
    if (iterator == nil || iterator->currentEvent == nil) {
        return 0.0;
    }
    return iterator->currentEvent->bpm;
}

- (unsigned long long)frameForFirstBar:(nonnull BeatEventIterator*)iterator
{
    iterator->pageIndex = 0;
    iterator->eventIndex = 0;
    iterator->currentEvent = nil;
    _pages = [_beats count];
    return [self frameForNextBar:iterator];
}

- (unsigned long long)frameForNextBar:(nonnull BeatEventIterator*)iterator
{
    NSData* data = nil;

    // Skip pages as long as we dont get any beat data.
    while (iterator->pageIndex < _pages) {
        data = [_beats objectForKey:[NSNumber numberWithLong:iterator->pageIndex]];
        if (data != nil) {
            break;
        }
        iterator->pageIndex++;
    };

    // Still no beat data -> bail out!
    if (data == nil) {
        return ULONG_LONG_MAX;
    }

    const BeatEvent* events = data.bytes;
    const size_t eventCount = data.length / sizeof(BeatEvent);

    NSAssert(eventCount, @"this beats page does not have a single event");
    NSAssert(iterator->eventIndex < eventCount, @"the event index somehow is beyond this page");

    iterator->currentEvent = &events[iterator->eventIndex];
    unsigned long long frame = events[iterator->eventIndex].frame;
    
    iterator->eventIndex++;
    
    // When the page event count is exhausted, go to the next page.
    if (iterator->eventIndex >= eventCount) {
        iterator->eventIndex = 0;
        iterator->pageIndex++;
    }

    return frame;
}

@end
