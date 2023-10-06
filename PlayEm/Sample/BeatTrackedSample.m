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

    fvec_t* _aubio_input_buffer;
    fvec_t* _aubio_output_buffer;

    aubio_tempo_t* _aubio_tempo;
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
        _aubio_input_buffer = NULL;
        _aubio_output_buffer = NULL;
        _aubio_tempo = NULL;
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
    _aubio_input_buffer = new_fvec((unsigned int)_hopSize);
    assert(_aubio_input_buffer);
    _aubio_output_buffer = new_fvec((unsigned int)1);
    assert(_aubio_output_buffer);
    _aubio_tempo = new_aubio_tempo("default",
                                   (unsigned int)_windowWidth,
                                   (unsigned int)_hopSize,
                                   (unsigned int)_sample.rate);
    aubio_tempo_set_threshold(_aubio_tempo, 0.5);
    assert(_aubio_tempo);
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
        
        float* data[_sample.channels];
        const int channels = _sample.channels;
        for (int channel = 0; channel < channels; channel++) {
            data[channel] = (float*)((NSMutableData*)_sampleBuffers[channel]).bytes;
        }
        unsigned long long sourceWindowFrameOffset = 0;
        
        unsigned long long expectedNextBeatFrame = 0;
        
        unsigned char beatIndex = 0;

        while (sourceWindowFrameOffset < _sample.frames) {
            unsigned long long sourceWindowFrameCount = MIN(_hopSize * 1024,
                                                            _sample.frames - sourceWindowFrameOffset);
            // This may block for a loooooong time!
            unsigned long long received = [_sample rawSampleFromFrameOffset:sourceWindowFrameOffset
                                                                     frames:sourceWindowFrameCount
                                                                    outputs:data];
            unsigned long int sourceFrameIndex = 0;
            BeatEvent event;
            while(sourceFrameIndex < received) {
                assert(((struct debug_aubio_tempo_t*)_aubio_tempo)->total_frames ==
                       sourceWindowFrameOffset + sourceFrameIndex);

                for (unsigned long int inputFrameIndex = 0;
                     inputFrameIndex < _hopSize;
                     inputFrameIndex++) {
                    double s = 0.0;
                    for (int channel = 0; channel < channels; channel++) {
                        s += data[channel][sourceFrameIndex];
                    }
                    s /= (float)channels;
                    _aubio_input_buffer->data[inputFrameIndex] = s;
                    sourceFrameIndex++;
                }

                aubio_tempo_do(_aubio_tempo, _aubio_input_buffer, _aubio_output_buffer);

                const bool beat = fvec_get_sample(_aubio_output_buffer, 0) != 0.f;
                if (beat) {
                    event.frame = aubio_tempo_get_last(_aubio_tempo);
                    
                    if (llabs(expectedNextBeatFrame - event.frame) > (_sample.rate / 10)) {
                        NSLog(@"looks like a bad prediction at %lld - %@", event.frame, [_sample beautifulTimeWithFrame:event.frame]);
                    }
                    
                    event.bpm = aubio_tempo_get_bpm(_aubio_tempo);
                    event.confidence = aubio_tempo_get_confidence(_aubio_tempo);
                    event.index = beatIndex;
                    
                    beatIndex = (beatIndex + 1) % 4;
                    
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
                }
            };
            sourceWindowFrameOffset += received;
        };
        
        

        [self cleanupTracking];
        atomic_fetch_or(&_beatTrackDone, 1);

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
