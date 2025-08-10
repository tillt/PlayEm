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
const double kBeatSampleDurationThreshold = 30.0 * 60.0;

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
        _key = nil;
        _hint = nil;
        
        unsigned long long framesNeeded = _windowWidth * 1024;
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
    
    if (_sample.duration > kBeatSampleDurationThreshold) {
        NSLog(@"skipping key tracking - sample is too long to get any value out.");
        _key = @"";
        _hint = @"";
        return YES;
    }

    const int channels = self->_sample.sampleFormat.channels;

    float* data[channels];
    for (int channel = 0; channel < channels; channel++) {
        data[channel] = (float*)((NSMutableData*)self->_sampleBuffers[channel]).bytes;
    }

    _audioData.setChannels(channels);
    _audioData.setFrameRate((unsigned int)self->_sample.sampleFormat.rate);
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
        case KeyFinder::D_FLAT_MINOR:  _key = @"12A";  _hint = @"D flat minor"; break;
        case KeyFinder::E_MAJOR:       _key = @"12B";  _hint = @"E major"; break;
        case KeyFinder::G_FLAT_MINOR:  _key = @"11A";  _hint = @"G flat minor"; break;
        case KeyFinder::A_MAJOR:       _key = @"11B";  _hint = @"A major"; break;
        case KeyFinder::B_MINOR:       _key = @"10A";  _hint = @"B minor"; break;
        case KeyFinder::D_MAJOR:       _key = @"10B";  _hint = @"D major"; break;
        case KeyFinder::E_MINOR:       _key = @"9A";   _hint = @"E minor"; break;
        case KeyFinder::G_MAJOR:       _key = @"9B";   _hint = @"G major"; break;
        case KeyFinder::A_MINOR:       _key = @"8A";   _hint = @"A minor"; break;
        case KeyFinder::C_MAJOR:       _key = @"8B";   _hint = @"C major"; break;
        case KeyFinder::D_MINOR:       _key = @"7A";   _hint = @"D minor"; break;
        case KeyFinder::F_MAJOR:       _key = @"7B";   _hint = @"F major"; break;
        case KeyFinder::G_MINOR:       _key = @"6A";   _hint = @"G minor"; break;
        case KeyFinder::B_FLAT_MAJOR:  _key = @"6B";   _hint = @"B flat major"; break;
        case KeyFinder::C_MINOR:       _key = @"5A";   _hint = @"C minor"; break;
        case KeyFinder::E_FLAT_MAJOR:  _key = @"5B";   _hint = @"E flat major"; break;
        case KeyFinder::F_MINOR:       _key = @"4A";   _hint = @"F minor"; break;
        case KeyFinder::A_FLAT_MAJOR:  _key = @"4B";   _hint = @"A flat major"; break;
        case KeyFinder::B_FLAT_MINOR:  _key = @"3A";   _hint = @"B flat minor"; break;
        case KeyFinder::D_FLAT_MAJOR:  _key = @"3B";   _hint = @"D flat major"; break;
        case KeyFinder::E_FLAT_MINOR:  _key = @"2A";   _hint = @"E flat minor"; break;
        case KeyFinder::G_FLAT_MAJOR:  _key = @"2B";   _hint = @"G flat major"; break;
        case KeyFinder::A_FLAT_MINOR:  _key = @"1A";   _hint = @"A flat minor"; break;
        case KeyFinder::B_MAJOR:       _key = @"1B";   _hint = @"B major"; break;
        case KeyFinder::SILENCE:
        default:
            _key = @""; _hint = @"";
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
