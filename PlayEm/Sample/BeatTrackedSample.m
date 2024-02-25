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

// Lowpass cutoff frequency.
//static const float kParamFilterMinValue = 50.0f;
//static const float kParamFilterMaxValue = 500.0f;
static const float kParamFilterDefaultValue = 240.0f;

@interface BeatTrackedSample()
{
}

@property (assign, nonatomic) size_t windowWidth;
//@property (strong, nonatomic) NSMutableDictionary* operations;
@property (strong, nonatomic) NSMutableArray<NSMutableData*>* sampleBuffers;
@property (strong, nonatomic) NSMutableDictionary* beatEventPages;

@end

@implementation BeatTrackedSample
{
    atomic_int _abortBeatTracking;
    atomic_int _beatTrackDone;
    
    size_t _hopSize;
    size_t _tileWidth;
    
    float _averageTempo;
    
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
        _averageTempo = 0.0f;
#ifdef BEATS_BY_AUBIO
        _aubio_input_buffer = NULL;
        _aubio_output_buffer = NULL;
        _aubio_tempo = NULL;
#else
#endif
        atomic_fetch_and(&_beatTrackDone, 0);

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
    _filterEnabled = YES;
    _filterFrequency = kParamFilterDefaultValue;
    _filterConstant = _sample.rate / (2.0f * M_PI * _filterFrequency);
#else
    tolerance = kParamToleranceDefaultValue;
    period = kParamPeriodDefaultValue;
    filterEnabled = YES;
    filterFrequency = kParamFilterDefaultValue;
    filterConstant = _sample.rate / (2.0f * M_PI * filterFrequency);
#endif
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

- (void)abortBeatTracking
{
    atomic_fetch_or(&_abortBeatTracking, 1);
}

- (float)tempo
{
    return _averageTempo;
}

- (unsigned long long)framesPerBeat:(float)tempo
{
    return _sample.rate * (tempo / (60.0f * 4.0f) );
}

- (void)trackBeatsAsyncWithCallback:(nonnull void (^)(void))callback
{
    atomic_fetch_and(&_abortBeatTracking, 0);
    atomic_fetch_and(&_beatTrackDone, 0);
    
    // Totally do this on a different thread!
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSLog(@"async beats tracking...");
        [self setupTracking];
        
        float* data[self->_sample.channels];
        const int channels = self->_sample.channels;
        for (int channel = 0; channel < channels; channel++) {
            data[channel] = (float*)((NSMutableData*)self->_sampleBuffers[channel]).bytes;
        }
        unsigned long long sourceWindowFrameOffset = 0LL;
        unsigned long long expectedNextBeatFrame = 0LL;
        
        //unsigned char barBeatIndex = 0;
        //unsigned int beatHistoryIndex = 0;

        NSLog(@"pass one");

        while (sourceWindowFrameOffset < self->_sample.frames) {
            unsigned long long sourceWindowFrameCount = MIN(self->_hopSize * 1024,
                                                            self->_sample.frames - sourceWindowFrameOffset);
            // This may block for a loooooong time!
            unsigned long long received = [self->_sample rawSampleFromFrameOffset:sourceWindowFrameOffset
                                                                         frames:sourceWindowFrameCount
                                                                        outputs:data];
                
            // FIXME: Consider introducing low pass filtering to get aubio to detect beats more reliably for electronic dance music which is all i am interested in.
            
            unsigned long int sourceFrameIndex = 0;
            BeatEvent event;
            while(sourceFrameIndex < received) {
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

                    // FIXME: This just crashed and I have no idea why, so far.
                    self->_aubio_input_buffer->data[inputFrameIndex] = s;
                    sourceFrameIndex++;
                }

                aubio_tempo_do(self->_aubio_tempo, self->_aubio_input_buffer, self->_aubio_output_buffer);
                const bool beat = fvec_get_sample(self->_aubio_output_buffer, 0) != 0.f;
                if (beat) {
                    event.frame = aubio_tempo_get_last(self->_aubio_tempo);

//                    if (llabs((signed long long)expectedNextBeatFrame - (signed long long)event.frame) > (self->_sample.rate / 5)) {
//                        NSLog(@"looks like a bad prediction at %lld - %@", event.frame, [self->_sample beautifulTimeWithFrame:event.frame]);
//                    }
                    
                    event.bpm = aubio_tempo_get_bpm(self->_aubio_tempo);
                    event.confidence = aubio_tempo_get_confidence(self->_aubio_tempo);

                    expectedNextBeatFrame = event.frame + [self framesPerBeat:event.bpm];
//                    NSLog(@"beat at %lld - %.2f bpm, confidence %.4f -- next beat expected at %lld",
//                          event.frame, event.bpm, event.confidence, expectedNextBeatFrame);

                    if (self->_averageTempo == 0) {
                        self->_averageTempo = event.bpm;
                    } else {
                        self->_averageTempo = ((self->_averageTempo * 9.0f) + event.bpm) / 10.0f;
                    }
                    
                    size_t origin = event.frame / self->_framesPerPixel;

                    NSNumber* pageKey = [NSNumber numberWithLong:origin / self->_tileWidth];

                    NSMutableData* data = [self->_beats objectForKey:pageKey];
                    if (data == nil) {
                        data = [NSMutableData data];
                    }

                    [data appendBytes:&event length:sizeof(BeatEvent)];

                    [self->_beats setObject:data forKey:pageKey];
                }
#endif
            };

            sourceWindowFrameOffset += received;
        };
        [self cleanupTracking];

        NSLog(@"pass two");
        
//        NSArray* keys = [[self->_beats allKeys] sortedArrayUsingSelector:@selector(compare:)];
//        for (NSNumber* key in keys) {
//            NSLog(@"beats page");
//            const NSData* data = self->_beats[key];
//            const BeatEvent* event = data.bytes;
//            for (int i=0; i < data.length / sizeof(BeatEvent); i++) {
//                NSLog(@"%lld %.0f %.4f", event->frame, event->bpm, event->confidence);
//                ++event;
//            }
//        }

        NSLog(@"pass three");
        
//        NSArray* keys = [_beats allKeys];
//        for (NSNumber* key in keys) {
//            NSLog(@"beats page");
//            const NSData* data = _beats[key];
//            const BeatEvent* event = data.bytes;
//            for (int i=0; i < data.length / sizeof(BeatEvent); i++) {
//                NSLog(@"%lld %f %.2f", event->frame, event->bpm, event->confidence);
//                ++event;
//            }
//        }

        atomic_fetch_or(&self->_beatTrackDone, 1);

        NSLog(@"...beats tracking done");
        
        NSLog(@"%@", self);

        if (callback){
            dispatch_async(dispatch_get_main_queue(), ^{
                callback();
            });
        }
    });
}

- (NSString *)description
{
    return [NSString stringWithFormat:@"Average tempo: %.0f BPM", _averageTempo];
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
    
    return [self frameForNextBar:iterator];
}

- (unsigned long long)frameForNextBar:(nonnull BeatEventIterator*)iterator
{
    NSData* data = [_beats objectForKey:[NSNumber numberWithLong:iterator->pageIndex]];
    if (data == nil) {
        return 0;
    }
    const BeatEvent* events = data.bytes;
    const size_t eventCount = data.length / sizeof(BeatEvent);
    assert(eventCount);
    assert(iterator->eventIndex < eventCount);

    iterator->currentEvent = &events[iterator->eventIndex];
    unsigned long long frame = events[iterator->eventIndex].frame;
    
    iterator->eventIndex++;
    
    if (iterator->eventIndex >= eventCount) {
        iterator->eventIndex = 0;
        iterator->pageIndex++;
    }

    return frame;
}

@end
