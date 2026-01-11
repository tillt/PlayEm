//
//  BeatTrackedSample.m
//  PlayEm
//
//  Created by Till Toenshoff on 06.08.23.
//  Copyright © 2023 Till Toenshoff. All rights reserved.
//
#import "BeatTrackedSample.h"

#import <Foundation/Foundation.h>

#import "../Audio/AudioProcessing.h"
#import "ActivityManager.h"
#import "CancelableBlockOperation.h"
#import "ConstantBeatRefiner.h"
#import "EnergyDetector.h"
#import "LazySample.h"

#define BEATS_BY_AUBIO

#define AUBIO_UNSTABLE 1
#include "aubio/aubio.h"

/* structure to store object state */
struct debug_aubio_tempo_t {
    aubio_specdesc_t* od;     /** onset detection */
    aubio_pvoc_t* pv;         /** phase vocoder */
    aubio_peakpicker_t* pp;   /** peak picker */
    aubio_beattracking_t* bt; /** beat tracking */
    cvec_t* fftgrain;         /** spectral frame */
    fvec_t* of;               /** onset detection function value */
    fvec_t* dfframe;          /** peak picked detection function buffer */
    fvec_t* out;              /** beat tactus candidates */
    fvec_t* onset;            /** onset results */
    smpl_t silence;           /** silence parameter */
    smpl_t threshold;         /** peak picking threshold */
    sint_t blockpos;          /** current position in dfframe */
    uint_t winlen;            /** dfframe bufsize */
    uint_t step;              /** dfframe hopsize */
    uint_t samplerate;        /** sampling rate of the signal */
    uint_t hop_size;          /** get hop_size */
    uint_t total_frames;      /** total frames since beginning */
    uint_t last_beat;         /** time of latest detected beat, in samples */
    sint_t delay;             /** delay to remove to last beat, in samples */
    uint_t last_tatum;        /** time of latest detected tatum, in samples */
    uint_t tatum_signature;   /** number of tatum between each beats */
};

static const float kBeatsShardSecondCount = 4.0f;

// Lowpass cutoff frequency.
// static const float kParamFilterMinValue = 50.0f;
// static const float kParamFilterMaxValue = 500.0f;
static const float kParamFilterDefaultValue = 270.0f;

static const float kSilenceThreshold = 0.1;

NSString* const kBeatTrackedSampleTempoChangeNotification = @"BeatTrackedSampleTempoChange";
NSString* const kBeatTrackedSampleBeatNotification = @"BeatTrackedSampleBeat";

NSString* const kBeatNotificationKeyBar = @"bar";
NSString* const kBeatNotificationKeyBeat = @"beat";
NSString* const kBeatNotificationKeyFrame = @"frame";
NSString* const kBeatNotificationKeyStyle = @"style";
NSString* const kBeatNotificationKeyTempo = @"tempo";
NSString* const kBeatNotificationKeyEnergy = @"energy";
NSString* const kBeatNotificationKeyLocalEnergy = @"localEnergy";
NSString* const kBeatNotificationKeyTotalEnergy = @"totalEnergy";
NSString* const kBeatNotificationKeyLocalPeak = @"localPeak";
NSString* const kBeatNotificationKeyTotalPeak = @"totalPeak";
NSString* const kBeatNotificationKeyTotalBeats = @"totalBeats";

const NSUInteger BeatEventMaskMarkers = BeatEventStyleMarkIntro | BeatEventStyleMarkBuildup | BeatEventStyleMarkTeardown | BeatEventStyleMarkOutro |
                                        BeatEventStyleMarkEnd | BeatEventStyleMarkChapter | BeatEventStyleMarkStart;

@interface BeatTrackedSample () {
}

@property (assign, nonatomic) size_t windowWidth;
@property (strong, nonatomic) NSMutableArray<NSMutableData*>* sampleBuffers;
@property (strong, nonatomic) NSMutableDictionary* beatEventPages;
@property (strong, nonatomic) dispatch_block_t queueOperation;

@end

@implementation BeatTrackedSample {
    size_t _pages;

    size_t _hopSize;

    float _lastTempo;

    size_t _iteratePageIndex;
    size_t _iterateEventIndex;

    // Variables used by the lopass filter
    BOOL _filterEnabled;
    float _filterFrequency;

    double _filterOutput;
    double _filterConstant;

    fvec_t* _aubio_input_buffer;
    fvec_t* _aubio_output_buffer;

    aubio_tempo_t* _aubio_tempo;
}

- (void)clearBpmHistory
{}

- (id)initWithSample:(LazySample*)sample
{
    self = [super init];
    if (self) {
        _sample = sample;
        _energy = [EnergyDetector new];
        _windowWidth = 1024;
        _hopSize = _windowWidth / 4;
        _sampleBuffers = [NSMutableArray array];
        _lastTempo = 0.0f;

        _aubio_input_buffer = NULL;
        _aubio_output_buffer = NULL;
        _aubio_tempo = NULL;

        _beats = [NSMutableDictionary dictionary];
        _shardFrameCount = ceil(sample.renderedSampleRate * kBeatsShardSecondCount);
        _constantBeats = nil;

        unsigned long long framesNeeded = _hopSize * 1024;
        for (int channel = 0; channel < sample.sampleFormat.channels; channel++) {
            NSMutableData* buffer = [NSMutableData dataWithCapacity:framesNeeded * _sample.frameSize];
            [_sampleBuffers addObject:buffer];
        }
    }
    return self;
}

- (void)setupTracking
{
    [self cleanupTracking];

    _aubio_input_buffer = new_fvec((unsigned int) _hopSize);
    assert(_aubio_input_buffer);
    _aubio_output_buffer = new_fvec((unsigned int) 1);
    assert(_aubio_output_buffer);
    _aubio_tempo = new_aubio_tempo("default", (unsigned int) _windowWidth, (unsigned int) _hopSize, (unsigned int) _sample.renderedSampleRate);
    aubio_tempo_set_threshold(_aubio_tempo, 0.75f);
    assert(_aubio_tempo);
    _filterEnabled = YES;
    _filterFrequency = kParamFilterDefaultValue;
    _filterConstant = _sample.renderedSampleRate / (2.0f * M_PI * _filterFrequency);
}

- (void)cleanupTracking
{
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
}

- (void)dealloc
{
    if (_aubio_input_buffer != NULL) {
        del_fvec(_aubio_input_buffer);
    }
    if (_aubio_output_buffer != NULL) {
        del_fvec(_aubio_output_buffer);
    }
    if (_aubio_tempo != NULL) {
        del_aubio_tempo(_aubio_tempo);
    }
}

struct _BeatsParserContext {
    unsigned long int eventIndex;
};

void beatsContextReset(BeatsParserContext* context)
{
    context->eventIndex = 0;
}

- (BOOL)trackBeatsWithToken:(ActivityToken*)token
{
    NSLog(@"beats tracking...");

    [[ActivityManager shared] updateActivity:token progress:0.0 detail:@"initializing beat detection"];

    [self setupTracking];

    float* data[self->_sample.sampleFormat.channels];
    const int channels = self->_sample.sampleFormat.channels;
    for (int channel = 0; channel < channels; channel++) {
        data[channel] = (float*) ((NSMutableData*) self->_sampleBuffers[channel]).bytes;
    }

    _coarseBeats = [NSMutableData data];

    NSLog(@"beat detect pass one: libaubio");

    // We need to track heading amd trailing silence to correct the beat-grid.
    BOOL initialSilenceEnded = NO;
    _initialSilenceEndsAtFrame = 0LL;
    _trailingSilenceStartsAtFrame = self->_sample.frames;

    // Here we go, all the way through our entire sample.
    unsigned long long sourceWindowFrameOffset = 0LL;
    while (sourceWindowFrameOffset < self->_sample.frames) {
        double progress = (double) sourceWindowFrameOffset / (double) self->_sample.frames;
        [[ActivityManager shared] updateActivity:token progress:progress detail:@"detecting beats"];

        if (dispatch_block_testcancel(self.queueOperation) != 0) {
            NSLog(@"aborted beat detection");
            [self cleanupTracking];
            return NO;
        }
        unsigned long long sourceWindowFrameCount = MIN(self->_hopSize * 1024, self->_sample.frames - sourceWindowFrameOffset);
        // This may block for a loooooong time!
        unsigned long long received = [self->_sample rawSampleFromFrameOffset:sourceWindowFrameOffset frames:sourceWindowFrameCount outputs:data];

        unsigned long int sourceFrameIndex = 0;
        BeatEvent event;
        while (sourceFrameIndex < received) {
            if (dispatch_block_testcancel(self.queueOperation) != 0) {
                NSLog(@"aborted beat detection");
                [self cleanupTracking];
                return NO;
            }

            assert(((struct debug_aubio_tempo_t*) self->_aubio_tempo)->total_frames == sourceWindowFrameOffset + sourceFrameIndex);

            const unsigned long int inputWindowFrameCount = MIN(self->_hopSize, self->_sample.frames - (sourceWindowFrameOffset + sourceFrameIndex));
            for (unsigned long int inputFrameIndex = 0; inputFrameIndex < inputWindowFrameCount; inputFrameIndex++) {
                double s = 0.0;
                for (int channel = 0; channel < channels; channel++) {
                    s += data[channel][sourceFrameIndex];
                }
                s /= (float) channels;

                [_energy addFrame:s];

                // We need to track heading and trailing silence to correct the
                // beat-grid.
                if (!initialSilenceEnded) {
                    if (fabs(s) > kSilenceThreshold) {
                        initialSilenceEnded = YES;
                        _initialSilenceEndsAtFrame = sourceWindowFrameOffset + sourceFrameIndex;
                    }
                }

                if (fabs(s) < kSilenceThreshold) {
                    if (_trailingSilenceStartsAtFrame == self->_sample.frames) {
                        _trailingSilenceStartsAtFrame = sourceWindowFrameOffset + sourceFrameIndex;
                    }
                } else {
                    _trailingSilenceStartsAtFrame = self->_sample.frames;
                }

                if (self->_filterEnabled) {
                    // For improving results on beat-detection for modern electronic
                    // music, we apply a basic lowpass filter (feedback).
                    // FIXME(tillt): We should really use the HW accellerated lowpass we
                    // already have.
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
        };

        sourceWindowFrameOffset += received;
    };
    [self cleanupTracking];

    NSLog(@"initial silence ends at %lld frames after start of sample", _initialSilenceEndsAtFrame);
    NSLog(@"trailing silence starts %lld frames before end of sample", _sample.frames - _trailingSilenceStartsAtFrame);

    [[ActivityManager shared] updateActivity:token progress:1.0 detail:@"refining beats"];

    // Generate a constant grid pattern out of the detected beats.
    NSData* constantRegions = [self retrieveConstantRegions];
    _constantBeats = [self makeConstantBeats:constantRegions];

    [self measureEnergyAtBeats];

    NSLog(@"...beats tracking done - total beats: %lld", [self beatCount]);
    [[ActivityManager shared] updateActivity:token progress:1.0 detail:@"beats tracked"];

    return YES;
}

- (void)measureEnergyAtBeats
{
    const unsigned long long windowSize = 4096;

    unsigned long long framesNeeded = windowSize;
    float* data[self->_sample.sampleFormat.channels];
    for (int channel = 0; channel < self->_sample.sampleFormat.channels; channel++) {
        NSMutableData* buffer = [NSMutableData dataWithCapacity:framesNeeded * _sample.frameSize];
        data[channel] = (float*) buffer.bytes;
    }

    EnergyDetector* nrg = [EnergyDetector new];

    unsigned long long beatIndex = 0;
    const unsigned long long beatCount = [self beatCount];

    while (beatIndex < beatCount) {
        BeatEvent currentEvent;
        [self getBeat:&currentEvent at:beatIndex];

        unsigned long long sourceWindowFrameOffset = currentEvent.frame;
        if (dispatch_block_testcancel(self.queueOperation) != 0) {
            NSLog(@"aborted beat detection during peak calculations");
            return;
        }
        unsigned long long sourceWindowFrameCount = MIN(windowSize, self->_sample.frames - sourceWindowFrameOffset);
        // This may block for a loooooong time!
        unsigned long long received = [self->_sample rawSampleFromFrameOffset:sourceWindowFrameOffset frames:sourceWindowFrameCount outputs:data];

        unsigned long int sourceFrameIndex = 0;
        while (sourceFrameIndex < received) {
            if (dispatch_block_testcancel(self.queueOperation) != 0) {
                NSLog(@"aborted beat detection during peak calculations");
                return;
            }

            const unsigned long int inputWindowFrameCount = MIN(windowSize, self->_sample.frames - (sourceWindowFrameOffset + sourceFrameIndex));
            for (unsigned long int inputFrameIndex = 0; inputFrameIndex < inputWindowFrameCount; inputFrameIndex++) {
                double s = 0.0;
                for (int channel = 0; channel < self->_sample.sampleFormat.channels; channel++) {
                    s += data[channel][sourceFrameIndex];
                }
                s /= (float) self->_sample.sampleFormat.channels;

                [nrg addFrame:s];

                sourceFrameIndex++;
            }
        };
        currentEvent.energy = nrg.rms;
        currentEvent.peak = nrg.peak;

        // frame = [self seekToNextBeat:&iterator];

        [self updateBeat:&currentEvent at:beatIndex];

        beatIndex++;

        [nrg reset];
    };
}

- (void)trackBeatsAsyncWithCallback:(void (^)(BOOL))callback
{
    __block BOOL done = NO;

    BeatTrackedSample* __weak weakSelf = self;

    ActivityToken* beatsToken = [[ActivityManager shared] beginActivityWithTitle:@"Beat Detection"
                                                                          detail:@""
                                                                     cancellable:NO
                                                                   cancelHandler:nil];

    _queueOperation = dispatch_block_create(DISPATCH_BLOCK_NO_QOS_CLASS, ^{
        done = [weakSelf trackBeatsWithToken:beatsToken];
    });
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), _queueOperation);
    dispatch_block_notify(_queueOperation, dispatch_get_main_queue(), ^{
        [[ActivityManager shared] completeActivity:beatsToken];
        self->_ready = done;
        callback(done);
    });
}

- (NSString*)description
{
    return [NSString stringWithFormat:@"Average tempo: %.0f BPM", _lastTempo];
}

- (void)abortWithCallback:(void (^)(void))callback
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

// FIXME: I am almost certain, this isnt the coolest most idiomatic way to solve
// this problem. I would try to get close to a struct copy constructor
// implementations as done in C++.
+ (void)copyIteratorFromSource:(nonnull BeatEventIterator*)source destination:(nonnull BeatEventIterator*)destination
{
    destination->eventIndex = source->eventIndex;
    destination->currentEvent = source->currentEvent;
}

- (float)currentTempo:(BeatEventIterator*)iterator
{
    if (iterator == nil) {
        return 0.0;
    }
    return iterator->currentEvent.bpm;
}

- (unsigned long long)currentEventFrame:(BeatEventIterator*)iterator
{
    if (iterator == nil) {
        return 0.0;
    }
    return iterator->currentEvent.frame;
}

- (unsigned long long)seekToBeatAfterFrameAt:(unsigned long long)frame iterator:(nonnull BeatEventIterator*)iterator
{
    [self seekToFirstBeat:iterator];

    while (frame > iterator->currentEvent.frame) {
        if ([self seekToNextBeat:iterator] == ULONG_LONG_MAX) {
            break;
        }
    };

    return iterator->currentEvent.frame;
}

- (unsigned long long)seekToBeatBeforeFrameAt:(unsigned long long)frame iterator:(nonnull BeatEventIterator*)iterator
{
    [self seekToFirstBeat:iterator];

    while (frame > iterator->currentEvent.frame) {
        if ([self seekToNextBeat:iterator] == ULONG_LONG_MAX) {
            break;
        }
    };

    return iterator->currentEvent.frame;
}

- (unsigned long long)seekToFirstBeat:(nonnull BeatEventIterator*)iterator
{
    iterator->eventIndex = 0;
    return [self seekToNextBeat:iterator];
}

- (unsigned long long)seekToNextBeat:(nonnull BeatEventIterator*)iterator
{
    if (iterator->eventIndex + 1 >= [self beatCount]) {
        return ULONG_LONG_MAX;
    }
    iterator->eventIndex++;
    [self getBeat:&iterator->currentEvent at:iterator->eventIndex];

    // NSAssert(eventCount, @"this beats page does not have a single event");
    // NSAssert(iterator->eventIndex < eventCount, @"the event index somehow is
    // beyond this page");

    // iterator->currentEvent = &events[iterator->eventIndex];
    //    unsigned long long frame = events[iterator->eventIndex].frame;
    //
    //    iterator->eventIndex++;
    //
    //    // When the page event count is exhausted, go to the next page.
    //    if (iterator->eventIndex >= eventCount) {
    //        iterator->eventIndex = 0;
    //        iterator->pageIndex++;
    //    }

    return iterator->currentEvent.frame;
}

- (unsigned long long)seekToPreviousBeat:(nonnull BeatEventIterator*)iterator
{
    if (iterator->eventIndex == 0) {
        return ULONG_LONG_MAX;
    }
    iterator->eventIndex++;
    [self getBeat:&iterator->currentEvent at:iterator->eventIndex];
    return iterator->currentEvent.frame;
}

//- (BeatEvent*)beatsFromFrame:(unsigned long long)frame
//{
//    unsigned long pageIndex = frame / _shardSize;
//    unsigned long long eventIndex = [[_beats objectForKey:[NSNumber
//    numberWithLong:pageIndex]];
//}
//
- (unsigned long long)firstBeatIndexAfterFrame:(unsigned long long)frame
{
    size_t page = frame / self.shardFrameCount;
    NSNumber* pageKey = [NSNumber numberWithLong:page];

    NSNumber* shardBeatIndex = [_beats objectForKey:pageKey];
    if (shardBeatIndex == nil) {
        // NSLog(@"that beats shard doesnt exist");
        return ULONG_LONG_MAX;
    }

    unsigned long long beatIndex = [shardBeatIndex unsignedLongLongValue];
    const unsigned long long beatCount = [self beatCount];

    while (beatIndex < beatCount) {
        BeatEvent event;
        [self getBeat:&event at:beatIndex];
        if (event.frame >= frame) {
            break;
        }
        beatIndex++;
    };

    return beatIndex;
}

- (void)updateBeat:(BeatEvent*)event at:(unsigned long long)index
{
    [_constantBeats replaceBytesInRange:NSMakeRange(index * sizeof(BeatEvent), sizeof(BeatEvent)) withBytes:event];
}

- (void)getBeat:(BeatEvent*)event at:(unsigned long long)index
{
    assert(index < [self beatCount]);
    const unsigned long long firstByteIndex = index * sizeof(BeatEvent);
    [_constantBeats getBytes:event range:NSMakeRange(firstByteIndex, sizeof(BeatEvent))];
    assert(event->index == index);
}

- (unsigned long long)beatCount
{
    return self.constantBeats.length / sizeof(BeatEvent);
}

@end
