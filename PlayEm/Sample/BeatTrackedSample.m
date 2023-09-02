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
//    dispatch_queue_t _queue;
    atomic_int _abortBeatTracking;
    atomic_int _beatTrackDone;

//    unsigned long _resetAubioDistance;
//    atomic_ulong _resetAubioCoordinate;

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
        _averageTempo = 0.0;
        _aubio_input_buffer = NULL;
        _aubio_output_buffer = NULL;
        _aubio_tempo = NULL;
        atomic_fetch_and(&_beatTrackDone, 0);

        //        _resetAubioDistance = (60.0f * _sample.rate) / _framesPerPixel;
//        _resetAubioCoordinate = _resetAubioDistance;

        _beats = [NSMutableDictionary dictionary];

        unsigned long long framesNeeded = _hopSize * 1024;
        for (int channel = 0; channel < sample.channels; channel++) {
            NSMutableData* buffer = [NSMutableData dataWithCapacity:framesNeeded * _sample.frameSize];
            [_sampleBuffers addObject:buffer];
        }

//        dispatch_queue_attr_t attr = dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL, QOS_CLASS_USER_INITIATED, 0);
//        const char* queue_name = [@"BeatTrackedSample" cStringUsingEncoding:NSStringEncodingConversionAllowLossy];
//        _queue = dispatch_queue_create(queue_name, attr);
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

//    const BeatEvent* events = _beats.bytes;
//    const unsigned int eventCount = _beats.length / sizeof(BeatEvent);
//    NSMutableData* output = [NSMutableData data];
//    unsigned long long startFrame = origin * _framesPerPixel;
//    unsigned long long frameCount = width * _framesPerPixel;
//    unsigned long long endFrame = startFrame+frameCount;
//    
//    unsigned long long frame = startFrame;
//    
//    while (frame < endFrame) {
//        while (context->eventIndex < eventCount && events[context->eventIndex].frame < frame) {
//            context->eventIndex++;
//        };
//        if (events[context->eventIndex].frame >= endFrame) {
//            return output;
//        }
//        if (context->eventIndex >= eventCount) {
//            NSLog(@"no more events beyond event count %d", eventCount);
//            return output;
//        }
//        [output appendBytes:&events[context->eventIndex] length:sizeof(BeatEvent)];
//
//        frame = events[context->eventIndex].frame;
//        
//        context->eventIndex++;
//    }
//    return output;
}

//- (void)prepareBeatsFromOrigin:(size_t)origin callback:(void (^)(void))callback
//{
//    [self runOperationWithOrigin:origin callback:callback];
//}

- (void)abortBeatTracking
{
    atomic_fetch_or(&_abortBeatTracking, 1);
}

- (float)tempo
{
    return _averageTempo;
}

//- (void)trackBeatsAsync:(size_t)totalWidth callback:(nonnull void (^)(void))callback
//{
//    atomic_fetch_and(&_abortBeatTracking, 0);
//    
//    // Totally do this on a different thread!
//    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
//        NSLog(@"async beats tracking...");
//        [self startTracking];
//        unsigned long long resetCycle = (60 * _sample.rate) / _framesPerPixel;
//
//        NSTimeInterval t = 0;
//        CGFloat origin = 0.0f;
//        CGFloat resetTotal = resetCycle;
//
//        while (origin < totalWidth) {
//            [self prepareBeatsFromOrigin:origin callback:^{
//                if (origin + _tileWidth >= totalWidth) {
//                    callback();
//                }
//            }];
//            origin += _tileWidth;
//        }
//    });
//}

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
                    event.bpm = aubio_tempo_get_bpm(_aubio_tempo);
                    event.confidence = aubio_tempo_get_confidence(_aubio_tempo);
                    
                    if (_averageTempo == 0) {
                        _averageTempo = event.bpm;
                    } else {
                        _averageTempo = (_averageTempo + event.bpm) / 2.0f;
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

        if (callback){
            dispatch_async(dispatch_get_main_queue(), ^{
                callback();
            });
        }
    });
}

- (BOOL)isReady
{
    return _beatTrackDone;
}

//- (IndexedBlockOperation*)runOperationWithOrigin:(size_t)origin callback:(void (^)(void))callback
//{
//    size_t pageIndex = origin / _tileWidth;
//
//    IndexedBlockOperation* block = [_operations objectForKey:[NSNumber numberWithLong:pageIndex]];
//    if (block != nil) {
//        NSLog(@"asking for the same operation again on page %ld", pageIndex);
//        return block;
//    }
//
//    block = [[IndexedBlockOperation alloc] initWithIndex:pageIndex];
//    //NSLog(@"adding %ld", pageIndex);
//    IndexedBlockOperation* __weak weakOperation = block;
//    BeatTrackedSample* __weak weakSelf = self;
//
//    [_operations setObject:block forKey:[NSNumber numberWithLong:pageIndex]];
//    
//    [block run:^(void){
//        if (weakOperation.isCancelled) {
//            return;
//        }
//        assert(!weakOperation.isFinished);
//        
//        unsigned long int framesNeeded = _tileWidth * _framesPerPixel;
////        assert((framesNeeded % _hopSize) == 0);
//        float* data[weakSelf.sample.channels];
//
//        const int channels = weakSelf.sample.channels;
//
//        for (int channel = 0; channel < channels; channel++) {
//            data[channel] = (float*)((NSMutableData*)weakSelf.sampleBuffers[channel]).bytes;
//        }
//
//        unsigned long long displaySampleFrameIndexOffset = origin * _framesPerPixel;
//        unsigned long long displaySampleFrameIndexEnd = displaySampleFrameIndexOffset + (_tileWidth * _framesPerPixel);
//        assert(displaySampleFrameIndexOffset < weakSelf.sample.frames);
//        unsigned long long displayFrameCount = MIN(framesNeeded, weakSelf.sample.frames - displaySampleFrameIndexOffset);
//
//        // This may block for a loooooong time!
//        [weakSelf.sample rawSampleFromFrameOffset:displaySampleFrameIndexOffset
//                                           frames:displayFrameCount
//                                          outputs:data];
//
//        //NSLog(@"This block of %lld frames is used to create visuals for %ld pixels", displayFrameCount, width);
//        weakOperation.index = pageIndex;
//        NSMutableData* eventsOutput = [NSMutableData data];
//
//        unsigned long int frameIndex = 0;
//        unsigned long int inputFrameIndex = 0;
//        BeatEvent event;
//        assert(displayFrameCount % _hopSize == 0);
//        while(frameIndex < displayFrameCount) {
//            if (weakOperation.isCancelled) {
//                break;
//            }
//            if (frameIndex >= displayFrameCount) {
//               break;
//            }
//            assert(((struct debug_aubio_tempo_t*)_aubio_tempo)->total_frames == displaySampleFrameIndexOffset + frameIndex);
//
//            while(inputFrameIndex < _hopSize) {
//                if (frameIndex >= displayFrameCount) {
//                   break;
//                }
//                double s = 0.0;
//                for (int channel = 0; channel < channels; channel++) {
//                    s += data[channel][frameIndex];
//                }
//                s /= (float)channels;
//                frameIndex++;
//                _aubio_input_buffer->data[inputFrameIndex] = s;
//                inputFrameIndex++;
//            };
//            aubio_tempo_do(_aubio_tempo, _aubio_input_buffer, _aubio_output_buffer);
//            const bool beat = fvec_get_sample(_aubio_output_buffer, 0) != 0.f;
//            if (beat) {
//                event.frame = aubio_tempo_get_last(_aubio_tempo);
//                if (event.frame < displaySampleFrameIndexEnd) {
//                    event.bpm = aubio_tempo_get_bpm(_aubio_tempo);
//                    event.confidence = aubio_tempo_get_confidence(_aubio_tempo);
//                    [eventsOutput appendBytes:&event length:sizeof(BeatEvent)];
//                } else {
//                    NSLog(@"bizarre beat exceeding input window at %lld - last-beat-processed frame at %lld", event.frame, ((struct debug_aubio_tempo_t*)_aubio_tempo)->total_frames);
//                }
//            }
//            inputFrameIndex = 0;
//        };
//        weakOperation.data = eventsOutput;
//        weakOperation.isFinished = YES;
//
//        if (callback){
//            dispatch_async(dispatch_get_main_queue(), ^{
//                callback();
//            });
//        }
//    }];
//
//    dispatch_async(_queue, block.block);
//
//    return block;
//}

- (float)currentTempo:(BeatEventIterator*)iterator
{
    if (iterator == nil || iterator->currentEvent == nil) {
        return 0.0;
    }
    return iterator->currentEvent->bpm;
}

- (unsigned long long)firstBarAtFrame:(nonnull BeatEventIterator*)iterator
{
    iterator->pageIndex = 0;
    iterator->eventIndex = 0;
    iterator->currentEvent = nil;
    
    return [self nextBarAtFrame:iterator];
}

- (unsigned long long)nextBarAtFrame:(nonnull BeatEventIterator*)iterator
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
    
//    
//    
//    
//    float tempo = 0.0f;
//    size_t slidingOrigin = origin;
//
//    while(true) {
//        NSData* data = [self beatsFromOrigin:slidingOrigin];
//        if (data == nil) {
//            return tempo;
//        }
//        const BeatEvent* events = data.bytes;
//        const size_t count = data.length / sizeof(BeatEvent);
//        if (count > 0) {
//            if (events[0].frame >= slidingOrigin) {
//                return ;
//            }
//        }
//    };
//
//    
//    size_t sourceWindowOffset = (origin / _tileWidth) * _tileWidth;
//    unsigned long long deltaFrames = (origin - sourceWindowOffset) * _framesPerPixel;
//    unsigned long long originFrame = origin * _framesPerPixel;
//
//    const BeatEvent* events = data.bytes;
//    const size_t count = data.length / sizeof(BeatEvent);
//    if (count == 0) {
//        return tempo;
//    }
//    if (events[0].frame > originFrame) {
//        return ;
//    }
//
//    size_t index = 0;
//    while (index < count &&
//           events[index].frame <= originFrame) {
//        tempo = events[index].bpm;
//        ++index;
//    };
//
//    return tempo;
}

@end
