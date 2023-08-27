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


@interface BeatTrackedSample()
{
}

@property (assign, nonatomic) size_t tileWidth;
@property (assign, nonatomic) size_t windowWidth;
@property (strong, nonatomic) NSMutableDictionary* operations;
@property (strong, nonatomic) NSMutableArray<NSMutableData*>* sampleBuffers;

@end

@implementation BeatTrackedSample
{
    dispatch_queue_t _queue;
    atomic_int _abortBeatTracking;

    unsigned long _resetAubioDistance;
    atomic_ulong _resetAubioCoordinate;

    size_t _hopSize;

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
        _operations = [NSMutableDictionary dictionary];
        _tileWidth = 256;
        _windowWidth = 1024;
        _hopSize = _windowWidth / 4;
        _sampleBuffers = [NSMutableArray array];
        _aubio_input_buffer = NULL;
        _aubio_output_buffer = NULL;
        _aubio_tempo = NULL;
        _resetAubioDistance = (60.0f * _sample.rate) / _framesPerPixel;
        _resetAubioCoordinate = _resetAubioDistance;

        unsigned long long framesNeeded = _tileWidth * _framesPerPixel;

        _beats = [NSMutableData data];

        for (int channel = 0; channel < sample.channels; channel++) {
            NSMutableData* buffer = [NSMutableData dataWithCapacity:framesNeeded * _sample.frameSize];
            [_sampleBuffers addObject:buffer];
        }

        dispatch_queue_attr_t attr = dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL, QOS_CLASS_USER_INITIATED, 0);
        const char* queue_name = [@"BeatTrackedSample" cStringUsingEncoding:NSStringEncodingConversionAllowLossy];
        _queue = dispatch_queue_create(queue_name, attr);
    }
    return self;
}

- (void)startTracking
{
    [self stopTracking];
    _aubio_input_buffer = new_fvec((unsigned int)_hopSize);
    _aubio_output_buffer = new_fvec((unsigned int)1);
    _aubio_tempo = new_aubio_tempo("default",
                                   (unsigned int)_windowWidth,
                                   (unsigned int)_hopSize,
                                   (unsigned int)_sample.rate);
    assert(_aubio_tempo);
}

- (void)stopTracking
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
    for (id key in _operations) {
        [_operations[key] cancel];
    }
    for (id key in _operations) {
        [_operations[key] wait];
    }
}

- (NSData* _Nullable)beatsFromOrigin:(size_t)origin
{
    size_t pageIndex = origin / _tileWidth;
    IndexedBlockOperation* operation = nil;
    operation = [_operations objectForKey:[NSNumber numberWithLong:pageIndex]];
    if (operation == nil) {
        return nil;
    }
    if (!operation.isFinished) {
        return nil;
    }
    return operation.data;
}

- (void)prepareBeatsFromOrigin:(size_t)origin callback:(void (^)(void))callback
{
    [self runOperationWithOrigin:origin callback:callback];
}

- (void)abortBeatTracking
{
    atomic_fetch_or(&_abortBeatTracking, 1);
}

- (void)trackBeatsAsync:(size_t)totalWidth callback:(nonnull void (^)(void))callback
{
    atomic_fetch_and(&_abortBeatTracking, 0);
    
    // Totally do this on a different thread!
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSLog(@"async beats tracking...");
        [self startTracking];
        unsigned long long resetCycle = (60 * _sample.rate) / _framesPerPixel;

        NSTimeInterval t = 0;
        CGFloat origin = 0.0f;
        CGFloat resetTotal = resetCycle;

        while (origin < totalWidth) {
            [self prepareBeatsFromOrigin:origin callback:^{
                if (origin + _tileWidth >= totalWidth) {
                    callback();
                }
            }];
            origin += _tileWidth;
        }
    });
}

- (IndexedBlockOperation*)runOperationWithOrigin:(size_t)origin callback:(void (^)(void))callback
{
    size_t pageIndex = origin / _tileWidth;

    IndexedBlockOperation* block = [_operations objectForKey:[NSNumber numberWithLong:pageIndex]];
    if (block != nil) {
        NSLog(@"asking for the same operation again on page %ld", pageIndex);
        return block;
    }

    block = [[IndexedBlockOperation alloc] initWithIndex:pageIndex];
    //NSLog(@"adding %ld", pageIndex);
    IndexedBlockOperation* __weak weakOperation = block;
    BeatTrackedSample* __weak weakSelf = self;

    [_operations setObject:block forKey:[NSNumber numberWithLong:pageIndex]];
    
    [block run:^(void){
//        if (origin > _resetAubioCoordinate) {
//            NSLog(@"resetting libaubio's tempo tracking as advised");
//            [self startTracking];
//            _resetAubioCoordinate += _resetAubioDistance;
//        }

        if (weakOperation.isCancelled) {
            return;
        }
        assert(!weakOperation.isFinished);
        
        unsigned long int framesNeeded = _tileWidth * _framesPerPixel;
//        assert((framesNeeded % _hopSize) == 0);
        float* data[weakSelf.sample.channels];

        const int channels = weakSelf.sample.channels;

        for (int channel = 0; channel < channels; channel++) {
            data[channel] = (float*)((NSMutableData*)weakSelf.sampleBuffers[channel]).bytes;
        }

        unsigned long long displaySampleFrameIndexOffset = origin * _framesPerPixel;
        assert(displaySampleFrameIndexOffset < weakSelf.sample.frames);
        unsigned long long displayFrameCount = MIN(framesNeeded, weakSelf.sample.frames - displaySampleFrameIndexOffset);

        // This may block for a loooooong time!
        [weakSelf.sample rawSampleFromFrameOffset:displaySampleFrameIndexOffset
                                           frames:displayFrameCount
                                          outputs:data];

        //NSLog(@"This block of %lld frames is used to create visuals for %ld pixels", displayFrameCount, width);
        weakOperation.index = pageIndex;
        NSMutableData* eventsOutput = [NSMutableData data];

        unsigned long int frameIndex = 0;
        unsigned long int inputFrameIndex = 0;
        BeatEvent event;

        while(frameIndex < displayFrameCount) {
            if (weakOperation.isCancelled) {
                break;
            }
            if (frameIndex > displayFrameCount) {
               break;
            }
            while(inputFrameIndex < _hopSize) {
                if (frameIndex > displayFrameCount) {
                   break;
                }
                double s = 0.0;
                for (int channel = 0; channel < channels; channel++) {
                    s += data[channel][frameIndex];
                }
                s /= (float)channels;
                frameIndex++;
                _aubio_input_buffer->data[inputFrameIndex] = s;
                inputFrameIndex++;
            };
            aubio_tempo_do(_aubio_tempo, _aubio_input_buffer, _aubio_output_buffer);
            const bool beat = fvec_get_sample(_aubio_output_buffer, 0) != 0.f;
            if (beat) {
                event.bpm = aubio_tempo_get_bpm(_aubio_tempo);
                event.confidence = aubio_tempo_get_confidence(_aubio_tempo);
                event.frame = aubio_tempo_get_last(_aubio_tempo);
                [eventsOutput appendBytes:&event length:sizeof(BeatEvent)];
            }
            inputFrameIndex = 0;
        };
        weakOperation.data = eventsOutput;
        weakOperation.isFinished = YES;

        if (callback){
            dispatch_async(dispatch_get_main_queue(), ^{
                callback();
            });
        }
    }];

    dispatch_async(_queue, block.block);

    return block;
}

- (float)tempoForOrigin:(size_t)origin
{
    float tempo = 0.0f;
    
    NSData* beats = [self beatsFromOrigin:origin];
    const BeatEvent* events = beats.bytes;
    const size_t count = beats.length / sizeof(BeatEvent);
    if (count > 0) {
        tempo = events[0].bpm;
    }
    
    return tempo;
}

@end
