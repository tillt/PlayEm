//
//  BeatTrackedSample.m
//  PlayEm
//
//  Created by Till Toenshoff on 06.08.23.
//  Copyright © 2023 Till Toenshoff. All rights reserved.
//
#import <Foundation/Foundation.h>

#import "BeatTrackedSample.h"
#import "LazySample.h"
#import "IndexedBlockOperation.h"
#import "ConstantBeatRefiner.h"

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

// Lowpass cutoff frequency.
//static const float kParamFilterMinValue = 50.0f;
//static const float kParamFilterMaxValue = 500.0f;
static const float kParamFilterDefaultValue = 270.0f;

static const float kSilenceThreshold = 0.1;

NSString * const kBeatTrackedSampleTempoChangeNotification = @"BeatTrackedSampleTempoChange";
NSString * const kBeatTrackedSampleBeatNotification = @"BeatTrackedSampleBeat";

NSString * const kBeatNotificationKeyFrame = @"frame";
NSString * const kBeatNotificationKeyTempo = @"tempo";
NSString * const kBeatNotificationKeyStyle = @"style";


@interface BeatTrackedSample()
{
}

@property (assign, nonatomic) size_t windowWidth;
//@property (strong, nonatomic) NSMutableDictionary* operations;
@property (strong, nonatomic) NSMutableArray<NSMutableData*>* sampleBuffers;
@property (strong, nonatomic) NSMutableDictionary* beatEventPages;
@property (strong, nonatomic) dispatch_block_t queueOperation;

@end

@implementation BeatTrackedSample
{
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


- (BOOL)trackBeats
{
    NSLog(@"beats tracking...");
    [self setupTracking];
    
    float* data[self->_sample.channels];
    const int channels = self->_sample.channels;
    for (int channel = 0; channel < channels; channel++) {
        data[channel] = (float*)((NSMutableData*)self->_sampleBuffers[channel]).bytes;
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
            
            const unsigned long int inputWindowFrameCount = MIN(self->_hopSize, self->_sample.frames - (sourceWindowFrameOffset + sourceFrameIndex));
            for (unsigned long int inputFrameIndex = 0; inputFrameIndex < inputWindowFrameCount; inputFrameIndex++) {
                double s = 0.0;
                for (int channel = 0; channel < channels; channel++) {
                    s += data[channel][sourceFrameIndex];
                }
                s /= (float)channels;
                
                // We need to track heading and trailing silence to correct the beat-grid.
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

                if(self->_filterEnabled) {
                    // For improving results on beat-detection for modern electronic music,
                    // we apply a basic lowpass filter (feedback).
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

    NSLog(@"initial silence ends at %lld frames after start of sample", _initialSilenceEndsAtFrame);
    NSLog(@"trailing silence starts %lld frames before end of sample", _sample.frames - _trailingSilenceStartsAtFrame);

    // Generate a constant grid pattern out of the detected beats.
    [self makeConstantBeats];  

    NSLog(@"...beats tracking done");

    return YES;
}
    
- (void)trackBeatsAsyncWithCallback:(void (^)(BOOL))callback
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

- (NSString *)description
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

// FIXME: I am almost certain, this isnt the coolest most idiomatic way to solve this problem. I would try to get close to a struct copy constructor implementations as done in C++.
+ (void)copyIteratorFromSource:(nonnull BeatEventIterator*)source destination:(nonnull BeatEventIterator*)destination
{
    destination->pageIndex = source->pageIndex;
    destination->eventIndex = source->eventIndex;
    destination->currentEvent = source->currentEvent;
}

- (float)currentTempo:(BeatEventIterator*)iterator
{
    if (iterator == nil || iterator->currentEvent == nil) {
        return 0.0;
    }
    return iterator->currentEvent->bpm;
}

- (unsigned long long)currentEventFrame:(BeatEventIterator*)iterator
{
    if (iterator == nil || iterator->currentEvent == nil) {
        return 0.0;
    }
    return iterator->currentEvent->frame;
}

- (unsigned long long)seekToFirstBeat:(nonnull BeatEventIterator*)iterator
{
    iterator->pageIndex = 0;
    iterator->eventIndex = 0;
    iterator->currentEvent = nil;
    _pages = [_beats count];
    return [self seekToNextBeat:iterator];
}

- (unsigned long long)seekToNextBeat:(nonnull BeatEventIterator*)iterator
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

- (unsigned long long)seekToPreviousBeat:(nonnull BeatEventIterator*)iterator
{
    NSData* data = nil;
    // Skip pages as long as we dont get any beat data.
    while (iterator->pageIndex >= 0) {
        data = [_beats objectForKey:[NSNumber numberWithLong:iterator->pageIndex]];
        if (data != nil) {
            break;
        }
        iterator->pageIndex--;
    };

    const BeatEvent* events = data.bytes;
    size_t eventCount = data.length / sizeof(BeatEvent);

    if (iterator->eventIndex == 0) {
        iterator->pageIndex--;

        data = nil;
        // Skip pages as long as we dont get any beat data.
        while (iterator->pageIndex >= 0) {
            data = [_beats objectForKey:[NSNumber numberWithLong:iterator->pageIndex]];
            if (data != nil) {
                break;
            }
            iterator->pageIndex--;
        };

        // Still no beat data -> bail out!
        if (data == nil) {
            NSLog(@"we somehow went past the first beat");
            return ULONG_LONG_MAX;
        }

        events = data.bytes;
        eventCount = data.length / sizeof(BeatEvent);

        NSAssert(eventCount > 0, @"we should really have at least some data");
        iterator->eventIndex = eventCount - 1;
    } else {
        iterator->eventIndex--;
    }

    iterator->currentEvent = &events[iterator->eventIndex];
    unsigned long long frame = events[iterator->eventIndex].frame;

    return frame;
}

@end
