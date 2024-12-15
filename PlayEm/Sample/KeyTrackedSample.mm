//
//  BeatTrackedSample.m
//  PlayEm
//
//  Created by Till Toenshoff on 06.08.24.
//  Copyright © 2023 Till Toenshoff. All rights reserved.
//
//#include <stdatomic.h>
#import <Foundation/Foundation.h>

#import "KeyTrackedSample.h"
#import "LazySample.h"
#import "IndexedBlockOperation.h"

#include <keyfinder/keyfinder.h>
#include <keyfinder/audiodata.h>

@interface KeyTrackedSample()
{
}

@property (assign, nonatomic) size_t windowWidth;
//@property (strong, nonatomic) NSMutableDictionary* operations;
@property (strong, nonatomic) NSMutableArray<NSMutableData*>* sampleBuffers;
@property (strong, nonatomic) NSMutableDictionary* beatEventPages;
@property (strong, nonatomic) NSMutableData* coarseBeats;
@property (strong, nonatomic) dispatch_block_t queueOperation;

@end

@implementation KeyTrackedSample
{
    //atomic_int _keyTrackDone;
    float _key;
    size_t _hopSize;
}

- (void)clearBpmHistory
{
}

- (id)initWithSample:(LazySample*)sample
{
    self = [super init];
    if (self) {
        _sample = sample;
        _windowWidth = 1024;
        _hopSize = _windowWidth / 4;
        _sampleBuffers = [NSMutableArray array];

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
}

- (void)cleanupTracking
{
}

- (void)dealloc
{
}

- (void)trackKeyAsyncWithCallback:(void (^)(BOOL))callback;
{
    __block BOOL done = NO;
    _queueOperation = dispatch_block_create(DISPATCH_BLOCK_NO_QOS_CLASS, ^{
        done = [self trackKey];
    });
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), _queueOperation);
    dispatch_block_notify(_queueOperation, dispatch_get_main_queue(), ^{
        self->_ready = done;
        callback(done);
    });
}

- (BOOL)trackKey
{
    NSLog(@"key tracking...");
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
        while(sourceFrameIndex < received) {
            if (dispatch_block_testcancel(self.queueOperation) != 0) {
                NSLog(@"aborted beat detection");
                return NO;
            }
            
            for (unsigned long int inputFrameIndex = 0;
                 inputFrameIndex < self->_hopSize;
                 inputFrameIndex++) {
                double s = 0.0;
                for (int channel = 0; channel < channels; channel++) {
                    s += data[channel][sourceFrameIndex];
                }
                s /= (float)channels;

                
                //self->_aubio_input_buffer->data[inputFrameIndex] = s;
                sourceFrameIndex++;
            }
            
//            aubio_tempo_do(self->_aubio_tempo, self->_aubio_input_buffer, self->_aubio_output_buffer);
//            const bool beat = fvec_get_sample(self->_aubio_output_buffer, 0) != 0.f;
//            if (beat) {
//                event.frame = aubio_tempo_get_last(self->_aubio_tempo);
//                [self->_coarseBeats appendBytes:&event.frame length:sizeof(unsigned long long)];
//            }
        };
        
        sourceWindowFrameOffset += received;
    };

    [self cleanupTracking];

    NSLog(@"...key tracking done");

    return YES;
}

- (NSString *)description
{
    return [NSString stringWithFormat:@"key: %.0f BPM", _key];
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
//    return _keyTrackDone;
    return NO;
}

@end
