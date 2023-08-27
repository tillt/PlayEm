//
//  LazySample.m
//  PlayEm
//
//  Created by Till Toenshoff on 01.01.21.
//  Copyright © 2021 Till Toenshoff. All rights reserved.
//

#include <stdatomic.h>
#import "LazySample.h"

#import <AVFoundation/AVFoundation.h>
#import <CoreAudio/CoreAudio.h>             // AudioDeviceID
#import <CoreAudio/CoreAudioTypes.h>
#import <CoreServices/CoreServices.h>


const size_t kMaxFramesPerBuffer = 16384;

@interface LazySample ()

@property (strong, nonatomic) AVAudioFile* source;
@property (strong, nonatomic) NSCondition* tileProduced;
@property (strong, nonatomic) NSMutableDictionary* buffers;

@end


@implementation LazySample
{
    atomic_int _abortDecode;
}

- (id)initWithPath:(NSString*)path error:(NSError**)error
{
    self = [super init];
    if (self) {
        NSLog(@"init source file for reading");
        _source = [[AVAudioFile alloc] initForReading:[NSURL fileURLWithPath:path] error:error];
        _tileProduced = [[NSCondition alloc] init];
        
        if (*error || _source == nil) {
            NSLog(@"AVAudioFile initForReading:error: failed: %@\n", *error);
            return nil;
        }
    
        AVAudioFormat* format = _source.processingFormat;
        _channels = format.channelCount;
        _rate = format.sampleRate;
        _frameSize = format.channelCount * sizeof(float);
        _buffers = [NSMutableDictionary dictionary];
        NSLog(@"...lazy sample initialized");
    }
    return self;
}

- (unsigned long long)frames
{
    // NOTE: Careful, this one can be really expensive for variable bitrate files when invoked
    // the first time -- avoid calling on mainthread!
    return _source.length;
}

- (unsigned long long)decodedFrames
{
    NSUInteger buffers = 0;
    [_tileProduced lock];
    buffers = _buffers.count;
    [_tileProduced unlock];
    return buffers * kMaxFramesPerBuffer;
}

- (void)dealloc
{
    atomic_fetch_or(&_abortDecode, 1);
}

- (void)abortDecode
{
    atomic_fetch_or(&_abortDecode, 1);
    
}

- (void)decodeAsyncWithCallback:(void (^)(void))callback;
{
    atomic_fetch_and(&_abortDecode, 0);

    // Totally do this on a different thread!
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSLog(@"async sample decode...");
        [self decode];
        callback();
    });
}

- (void)decode
{
    NSLog(@"decoding sample...");

    NSError* error = nil;

    AVAudioEngine* engine;
    AVAudioPlayerNode* player;

    engine = [[AVAudioEngine alloc] init];
    player = [[AVAudioPlayerNode alloc] init];

    NSLog(@"attaching node...");
    [engine attachNode:player];
    NSLog(@"connecting player to engine...");
    [engine connect:player to:engine.mainMixerNode format:_source.processingFormat];
    NSLog(@"scheduling file...");
    [player scheduleFile:_source atTime:0 completionHandler:nil];
    NSLog(@"enabling manual render...");
    [engine enableManualRenderingMode:AVAudioEngineManualRenderingModeOffline
                               format:_source.processingFormat
                    maximumFrameCount:kMaxFramesPerBuffer
                                error:&error];
    NSLog(@"starting engine...");
    if (![engine startAndReturnError:&error]) {
        NSLog(@"startAndReturnError failed: %@\n", error);
        return;
    }
            
    AVAudioPCMBuffer* buffer =
        [[AVAudioPCMBuffer alloc] initWithPCMFormat:engine.manualRenderingFormat
                                      frameCapacity:kMaxFramesPerBuffer];
    
    NSLog(@"manual rendering maximum frame count: %d\n", engine.manualRenderingMaximumFrameCount);

    [player play];

    unsigned long long pageIndex = 0;

    while (engine.manualRenderingSampleTime < _source.length) {
        //NSLog(@"manual rendering sample time: %lld\n", _engine.manualRenderingSampleTime);
        // `_source.length` is the number of sample frames in the file.
        // `_engine.manualRenderingSampleTime`
        unsigned long long frameLeftCount = _source.length - engine.manualRenderingSampleTime;
        //_engine.manualRenderingMaximumFrameCount

        if ((unsigned long long)buffer.frameCapacity > frameLeftCount) {
            NSLog(@"last tile rendereing: %lld", pageIndex);
        }
        AVAudioFrameCount framesToRender = (AVAudioFrameCount)MIN(frameLeftCount, (long long)buffer.frameCapacity);
        AVAudioEngineManualRenderingStatus status = [engine renderOffline:framesToRender toBuffer:buffer error:&error];

        switch (status) {
            case AVAudioEngineManualRenderingStatusSuccess: {
                unsigned long long rawDataLengthPerChannel = buffer.frameLength * sizeof(float);
                
                NSMutableArray<NSData*>* channels = [NSMutableArray array];
                
                for (int channelIndex = 0; channelIndex < _channels; channelIndex++) {
                    NSData* channel = [NSData dataWithBytes:buffer.floatChannelData[channelIndex]
                                                     length:rawDataLengthPerChannel];
                    [channels addObject:channel];
                }
                [_tileProduced lock];
                [_buffers setObject:channels forKey:[NSNumber numberWithUnsignedLongLong:pageIndex]];
                [_tileProduced signal];
                [_tileProduced unlock];
                pageIndex++;
            }
            // Whenever the engine needs more data, this will get triggered - for our manual
            // rendering this comes directly before `AVAudioEngineManualRenderingStatusSuccess`.
            case AVAudioEngineManualRenderingStatusInsufficientDataFromInputNode:
                break;
            case AVAudioEngineManualRenderingStatusError:
                NSLog(@"renderOffline failed: %@\n", error);
                return;
            case AVAudioEngineManualRenderingStatusCannotDoInCurrentContext:
                NSLog(@"somehow one round failed, lets retry\n");
                break;
        }
        
        if (_abortDecode > 0) {
            NSLog(@"...decoding aborted!!!");
            return;
        }
    };
    NSLog(@"...decoding done");

    return;
}

- (unsigned long long)rawSampleFromFrameOffset:(unsigned long long)offset
                                        frames:(unsigned long long)frames
                                          copy:(nonnull void (^)(unsigned long long, size_t, size_t, NSArray*))copy
{
    unsigned long long orderedFrames = frames;
    unsigned long long oldOffset = offset;

    // Cap frames requested, preventing overrun.
    frames = MIN(_source.length - offset, frames);
    
    while (frames) {
        unsigned long long pageIndex = offset / kMaxFramesPerBuffer;
        size_t pageOffset = offset - (pageIndex * kMaxFramesPerBuffer);

        NSArray* channels = nil;
        
        [_tileProduced lock];
        while ((channels = [_buffers objectForKey:[NSNumber numberWithUnsignedLongLong:pageIndex]]) == nil) {
            //NSLog(@"awaiting tile %lld\n", pageIndex);
            [_tileProduced wait];
        };
        [_tileProduced unlock];

        if (channels == nil) {
            return orderedFrames - frames;
        }

        BOOL lastRound = NO;
        unsigned long long count = MIN(kMaxFramesPerBuffer - pageOffset, frames);
        
        if (_source.length - offset < count) {
            count = _source.length - offset;
            lastRound = YES;
        }
        
        copy(count, pageOffset, _channels, channels);
        
        offset += count;
        frames -= count;

        if (lastRound) {
            break;
        }
    };
    return offset - oldOffset;
}

- (unsigned long long)rawSampleFromFrameOffset:(unsigned long long)offset frames:(unsigned long long)frames outputs:(float * const _Nonnull * _Nullable)outputs
{
    float* data[_channels];
    memcpy(data, outputs, _channels * sizeof(float*));

    __block float** output = data;
    return [self rawSampleFromFrameOffset:offset frames:frames copy:^(unsigned long long count, size_t pageOffset, size_t channels, NSArray* buffers){
        for (int channel = 0; channel < channels; channel++) {
            NSData* buffer = buffers[channel];
            float* source = (float*)buffer.bytes;
            memcpy(output[channel], source + pageOffset, count * sizeof(float));
            output[channel] += count;
        }
    }];
}

- (unsigned long long)rawSampleFromFrameOffset:(unsigned long long)offset frames:(unsigned long long)frames data:(float*)data
{
    __block float* output = data;
    return [self rawSampleFromFrameOffset:offset frames:frames copy:^(unsigned long long count, size_t pageOffset, size_t channels, NSArray* buffers){
        for (int i = 0; i < count; i++) {
            for (NSData* buffer in buffers) {
                *output = *((const float*)buffer.bytes + pageOffset + i);
                output++;
            }
        }
    }];
}

- (void)dumpToFile
{
    FILE* fp;
    
    fp = fopen("/tmp/dumpedLazySample.raw", "wb");

    float* windows[_channels];
    float* data[_channels];
    const size_t channelWindowFrames = 180000;

    for (int channelIndex=0; channelIndex < _channels; channelIndex++) {
        windows[channelIndex] = malloc(channelWindowFrames * sizeof(float));
    }
    
    float* output = malloc(self.frameSize * self.frames);
    float* outp = output;
    size_t left = self.frames;
    size_t offset = 0;
    while(left) {
        size_t fetchSize = MIN(channelWindowFrames, left);
        
        [self rawSampleFromFrameOffset:offset frames:fetchSize outputs:windows];

        for (int channelIndex=0; channelIndex < _channels; channelIndex++) {
            data[channelIndex] = windows[channelIndex];
        }
        for (size_t i=0; i < fetchSize;i++){
            for (int channelIndex=0; channelIndex < _channels; channelIndex++) {
                *output = *data[channelIndex];
                output++;
                data[channelIndex]++;
            }
        }
        offset += fetchSize;
        left -= fetchSize;
    };

    fwrite(outp, self.frames, self.frameSize, fp);
    fclose(fp);
    
    free(outp);
    for (int channelIndex=0; channelIndex < _channels; channelIndex++) {
        free(windows[channelIndex]);
    }
}

- (NSTimeInterval)duration
{
    assert(_rate != 0.0);
    assert(_source.length != 0);
    return _source.length / _rate;
}

- (NSTimeInterval)timeForFrame:(unsigned long long)frame
{
    assert(_rate != 0.0);
    return frame / _rate;
}

- (NSString *)description
{
    NSLog(@"rendering description...");
    return [NSString stringWithFormat:@"Channels: %d, Rate: %ld, Encoding: %d, Duration: %.02f seconds", _channels, _rate, _encoding, self.duration];
    //return [NSString stringWithFormat:@"Channels: %d, Rate: %ld, Encoding: %d", _channels, _rate, _encoding];
}

@end
