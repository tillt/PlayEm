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
    KeyFinder::KeyFinder _keyFinder;
    KeyFinder::Workspace _workspace;
    KeyFinder::AudioData _audioData;

    unsigned long long _currentFrame;
    unsigned long long _totalFrames;
    size_t _hopSize;
    unsigned long long _maxFramesToProcess;
    
    bool _keyDetectionEnabled;
    bool _fastAnalysisEnabled;
    bool _reanalyzeEnabled;
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
//        _hopSize = 256;
        _hopSize = _windowWidth / 4;
        _sampleBuffers = [NSMutableArray array];
        
        _keyDetectionEnabled = YES;
        _fastAnalysisEnabled = NO;
        _reanalyzeEnabled = NO;

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

//- (void)process(const CSAMPLE* pIn, SINT iLen)
//{
//    if (_audioData.getSampleCount() == 0) {
//        _audioData.addToSampleCount(iLen);
//    }
//
//    const SINT numInputFrames = iLen / kAnalysisChannels;
//    _currentFrame += numInputFrames;
//
//    for (SINT frame = 0; frame < numInputFrames; frame++) {
//        for (SINT channel = 0; channel < kAnalysisChannels; channel++) {
//            _audioData.setSampleByFrame(frame, channel, pIn[frame * kAnalysisChannels + channel]);
//        }
//    }
//    _keyFinder.progressiveChromagram(_audioData, _workspace);
//}

/*
 * KeyFinder::AudioData a;
  * a.setFrameRate(yourAudioStream.framerate);
  * a.setChannels(yourAudioStream.channels);
  * a.addToSampleCount(yourAudioStream.packetLength);
  *
  * static KeyFinder::KeyFinder k;
  *
  * // the workspace holds the memory allocations for analysis of a single track
  * KeyFinder::Workspace w;
  *
  * while (someType yourPacket = newAudioPacket()) {
  *
  *   for (int i = 0; i < yourPacket.length; i++) {
  *     a.setSample(i, yourPacket[i]);
  *   }
  *   k.progressiveChromagram(a, w);
  *
  *   // if you want to grab progressive key estimates...
  *   KeyFinder::key_t key = k.keyOfChromagram(w);
  *   doSomethingWithMostRecentKeyEstimate(key);
  * }
  *
  * // if you only want a single key estimate, or to squeeze
  * // every last bit of audio from the working buffer after
  * // progressive estimates...
  * k.finalChromagram(w);
  *
  * // and finally...
  * KeyFinder::key key = k.keyOfChromagram(w);
  *
  * doSomethingWithFinalKeyEstimate(key);
  * ```
 */

- (BOOL)trackKey
{
    NSLog(@"key tracking...");

    const int channels = self->_sample.channels;

    float* data[channels];
    for (int channel = 0; channel < channels; channel++) {
        data[channel] = (float*)((NSMutableData*)self->_sampleBuffers[channel]).bytes;
    }

    _audioData.setChannels(channels);
    _audioData.setFrameRate((unsigned int)self->_sample.rate);
    _audioData.addToSampleCount((unsigned int)self->_windowWidth * 2);
    
    unsigned long long sourceWindowFrameOffset = 0LL;
    
    while (sourceWindowFrameOffset < self->_sample.frames) {
        if (dispatch_block_testcancel(self.queueOperation) != 0) {
            NSLog(@"aborted key detection");
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
                 inputFrameIndex < self->_windowWidth;
                 inputFrameIndex++) {
                for (int channel = 0; channel < channels; channel++) {
                    _audioData.setSampleByFrame((unsigned int)inputFrameIndex,
                                                channel,
                                                data[channel][sourceFrameIndex]);
                }
                sourceFrameIndex++;
            }
            
            _keyFinder.progressiveChromagram(_audioData, _workspace);

//            aubio_tempo_do(self->_aubio_tempo, self->_aubio_input_buffer, self->_aubio_output_buffer);
//            const bool beat = fvec_get_sample(self->_aubio_output_buffer, 0) != 0.f;
//            if (beat) {
//                event.frame = aubio_tempo_get_last(self->_aubio_tempo);
//                [self->_coarseBeats appendBytes:&event.frame length:sizeof(unsigned long long)];
//            }
        };
        
        sourceWindowFrameOffset += received;
    };

    _keyFinder.finalChromagram(_workspace);

    KeyFinder::key_t key = _keyFinder.keyOfChromagram(_workspace);
    
    switch(key) {
        case KeyFinder::D_FLAT_MINOR:  _key = @"12A";  break;
        case KeyFinder::E_MAJOR:       _key = @"12B";  break;
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
        case KeyFinder::G_FLAT_MINOR:  _key = @"8A";   break;
        case KeyFinder::SILENCE:
        default:
            _key = @"";
    }

    
    /*
     enum key_t {
     };
     */

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
