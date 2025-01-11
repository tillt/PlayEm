//
//  KeyTrackedSample.mm
//  PlayEm
//
//  Created by Till Toenshoff on 18.12.24.
//  Copyright © 2024 Till Toenshoff. All rights reserved.
//
#import <Foundation/Foundation.h>

#import "KeyTrackedSample.h"
#import "LazySample.h"
#import "IndexedBlockOperation.h"

#include <keyfinder/keyfinder.h>
#include <keyfinder/audiodata.h>

// Anything beyond 30mins playtime is not of interest for chroma tracking, I declare hereby.
const double kSampleDurationThreshold = 30.0 * 60.0;

@interface KeyTrackedSample()
{
}

@property (assign, nonatomic) size_t windowWidth;
@property (strong, nonatomic) NSMutableArray<NSMutableData*>* sampleBuffers;
@property (strong, nonatomic) NSMutableDictionary* beatEventPages;
@property (strong, nonatomic) NSMutableData* coarseBeats;
@property (strong, nonatomic) dispatch_block_t queueOperation;

@end

@implementation KeyTrackedSample
{
    KeyFinder::KeyFinder _keyFinder;
    KeyFinder::Workspace _workspace;
    KeyFinder::AudioData _audioData;

    unsigned long long _currentFrame;
    unsigned long long _totalFrames;
    unsigned long long _maxFramesToProcess;
}

- (id)initWithSample:(LazySample*)sample
{
    self = [super init];
    if (self) {
        _sample = sample;
        _windowWidth = 1024;
        _sampleBuffers = [NSMutableArray array];
        
        unsigned long long framesNeeded = _windowWidth * 1024;
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
    
    if (_sample.duration > kSampleDurationThreshold) {
        NSLog(@"skipping key tracking - sample is too long to get any value out.");
        _key = @"";
        return YES;
    }

    const int channels = self->_sample.channels;

    float* data[channels];
    for (int channel = 0; channel < channels; channel++) {
        data[channel] = (float*)((NSMutableData*)self->_sampleBuffers[channel]).bytes;
    }

    _audioData.setChannels(channels);
    _audioData.setFrameRate((unsigned int)self->_sample.rate);
    _audioData.addToSampleCount((unsigned int)self->_windowWidth * channels);
    
    unsigned long long sourceWindowFrameOffset = 0LL;
    
    while (sourceWindowFrameOffset < self->_sample.frames) {
        if (dispatch_block_testcancel(self.queueOperation) != 0) {
            NSLog(@"aborted key detection");
            return NO;
        }
        unsigned long long sourceWindowFrameCount = MIN(self->_windowWidth * 1024,
                                                        self->_sample.frames - sourceWindowFrameOffset);
        // This may block for a loooooong time!
        unsigned long long received = [self->_sample rawSampleFromFrameOffset:sourceWindowFrameOffset
                                                                       frames:sourceWindowFrameCount
                                                                      outputs:data];
        unsigned long int sourceFrameIndex = 0;
        while(sourceFrameIndex < received) {
            if (dispatch_block_testcancel(self.queueOperation) != 0) {
                NSLog(@"aborted key detection");
                return NO;
            }
            
            const unsigned long int inputWindowFrameCount = MIN(self->_windowWidth, self->_sample.frames - (sourceWindowFrameOffset + sourceFrameIndex));

            for (unsigned long int inputFrameIndex = 0;
                 inputFrameIndex < inputWindowFrameCount;
                 inputFrameIndex++) {
                for (int channel = 0; channel < channels; channel++) {
                    _audioData.setSampleByFrame((unsigned int)inputFrameIndex,
                                                channel,
                                                data[channel][sourceFrameIndex]);
                }
                sourceFrameIndex++;
            }
            _keyFinder.progressiveChromagram(_audioData, _workspace);
        };
        
        sourceWindowFrameOffset += received;
    };

    _keyFinder.finalChromagram(_workspace);

    KeyFinder::key_t key = _keyFinder.keyOfChromagram(_workspace);
    
    switch(key) {
        case KeyFinder::D_FLAT_MINOR:  _key = @"12A";  break;
        case KeyFinder::E_MAJOR:       _key = @"12B";  break;
        case KeyFinder::G_FLAT_MINOR:  _key = @"11A";  break;
        case KeyFinder::A_MAJOR:       _key = @"11B";  break;
        case KeyFinder::B_MINOR:       _key = @"10A";  break;
        case KeyFinder::D_MAJOR:       _key = @"10B";  break;
        case KeyFinder::E_MINOR:       _key = @"9A";   break;
        case KeyFinder::G_MAJOR:       _key = @"9B";   break;
        case KeyFinder::A_MINOR:       _key = @"8A";   break;
        case KeyFinder::C_MAJOR:       _key = @"8B";   break;
        case KeyFinder::D_MINOR:       _key = @"7A";   break;
        case KeyFinder::F_MAJOR:       _key = @"7B";   break;
        case KeyFinder::G_MINOR:       _key = @"6A";   break;
        case KeyFinder::B_FLAT_MAJOR:  _key = @"6B";   break;
        case KeyFinder::C_MINOR:       _key = @"5A";   break;
        case KeyFinder::E_FLAT_MAJOR:  _key = @"5B";   break;
        case KeyFinder::F_MINOR:       _key = @"4A";   break;
        case KeyFinder::A_FLAT_MAJOR:  _key = @"4B";   break;
        case KeyFinder::B_FLAT_MINOR:  _key = @"3A";   break;
        case KeyFinder::D_FLAT_MAJOR:  _key = @"3B";   break;
        case KeyFinder::E_FLAT_MINOR:  _key = @"2A";   break;
        case KeyFinder::G_FLAT_MAJOR:  _key = @"2B";   break;
        case KeyFinder::A_FLAT_MINOR:  _key = @"1A";   break;
        case KeyFinder::B_MAJOR:       _key = @"1B";   break;
        case KeyFinder::SILENCE:
        default:
            _key = @"";
    }

    NSLog(@"key %d", key);
    [self cleanupTracking];

    NSLog(@"...key tracking done");

    return YES;
}

- (NSString *)description
{
    return [NSString stringWithFormat:@"key: %.0f BPM", 0.0];
}

- (void)abortWithCallback:(void (^)(void))callback
{
    NSLog(@"abort of key detection ongoing..");
    if (_queueOperation != NULL) {
        dispatch_block_cancel(_queueOperation);
        dispatch_block_notify(_queueOperation, dispatch_get_main_queue(), ^{
            callback();
        });
    } else {
        callback();
    }
}

@end
