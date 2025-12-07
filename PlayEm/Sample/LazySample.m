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
#import "ProfilingPointsOfInterest.h"

const size_t kMaxFramesPerBuffer = 16384;

@interface LazySample ()

@property (strong, nonatomic) NSCondition* tileProduced;
@property (strong, nonatomic) NSMutableDictionary* buffers;

@end

@implementation LazySample

- (id)initWithPath:(NSString*)path error:(NSError**)error
{
    self = [super init];
    if (self) {
        NSLog(@"init source file for reading");

        NSURL* url = [NSURL fileURLWithPath:path];
        NSAssert(url != nil, @"invalid file path: %@", path);
        _source = [[AVAudioFile alloc] initForReading:url error:error];
        _tileProduced = [[NSCondition alloc] init];
        
        if (_source == nil) {
            NSLog(@"AVAudioFile initForReading failed");
            if (error != nil) {
                NSLog(@"error: %@\n", *error);
            }
            return nil;
        }
    
        AVAudioFormat* format = _source.processingFormat;
        _sampleFormat.rate = format.sampleRate;
        _sampleFormat.channels = format.channelCount;
        _frameSize = format.channelCount * sizeof(float);
        _buffers = [NSMutableDictionary dictionary];
        NSLog(@"...lazy sample %p initialized", self);
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
    NSLog(@"removing LazySample %p from memory", self);
}

- (void)addLazyPageIndex:(unsigned long long)pageIndex channels:(NSArray<NSData*>*)channels
{
    [_tileProduced lock];
    [_buffers setObject:channels forKey:[NSNumber numberWithUnsignedLongLong:pageIndex]];
    [_tileProduced signal];
    [_tileProduced unlock];
}

- (unsigned long long)rawSampleFromFrameOffset:(unsigned long long)offset
                                        frames:(unsigned long long)frames
                                          copy:(nonnull void (^)(unsigned long long, size_t, size_t, NSArray*))copy
{
    unsigned long long orderedFrames = frames;
    unsigned long long oldOffset = offset;
    
    if (_source.length <= offset) {
        return 0;
    }

    NSAssert(_source.length > offset, @"sample aint long enough");
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

        unsigned long long count = MIN(kMaxFramesPerBuffer - pageOffset, frames);
        
        copy(count, pageOffset, _sampleFormat.channels, channels);
        
        offset += count;
        frames -= count;
    };
    return offset - oldOffset;
}

- (unsigned long long)rawSampleFromFrameOffset:(unsigned long long)offset 
                                        frames:(unsigned long long)frames
                                       outputs:(float * const _Nonnull * _Nullable)outputs
{
    // Prepare the data pointer array to point at our outputs pointers
    float* data[_sampleFormat.channels];
    memcpy(data, outputs, _sampleFormat.channels * sizeof(float*));

    __block float** output = data;
    return [self rawSampleFromFrameOffset:offset 
                                   frames:frames
                                     copy:^(unsigned long long count, size_t pageOffset, size_t channels, NSArray* buffers){
        assert(buffers.count == channels);
        for (int channel = 0; channel < channels; channel++) {
            NSData* buffer = buffers[channel];
            float* source = (float*)buffer.bytes;
            memcpy(output[channel], source + pageOffset, count * sizeof(float));
            output[channel] += count;
        }
    }];
}

- (unsigned long long)rawSampleFromFrameOffset:(unsigned long long)offset 
                                        frames:(unsigned long long)frames
                                          data:(float*)data
{
    __block float* output = data;
    return [self rawSampleFromFrameOffset:offset 
                                   frames:frames
                                     copy:^(unsigned long long count, size_t pageOffset, size_t channels, NSArray* buffers){
        for (int i = 0; i < count; i++) {
            for (NSData* buffer in buffers) {
                *output = *((const float*)buffer.bytes + pageOffset + i);
                output++;
            }
        }
    }];
}

- (void)fromFile
{
    FILE* fp;
    
    fp = fopen("/tmp/dumpedLazySample.raw", "rb");
    if (fp == NULL) {
        return;
    }

    float* windows[_sampleFormat.channels];
    float* data[_sampleFormat.channels];
    const size_t channelWindowFrames = 180000;

    for (int channelIndex=0; channelIndex < _sampleFormat.channels; channelIndex++) {
        windows[channelIndex] = malloc(channelWindowFrames * sizeof(float));
    }
    
    float* output = malloc(self.frameSize * self.frames);
    float* outp = output;
    size_t left = self.frames;
    size_t offset = 0;
    while(left) {
        size_t fetchSize = MIN(channelWindowFrames, left);
        
        [self rawSampleFromFrameOffset:offset frames:fetchSize outputs:windows];

        for (int channelIndex=0; channelIndex < _sampleFormat.channels; channelIndex++) {
            data[channelIndex] = windows[channelIndex];
        }
        for (size_t i=0; i < fetchSize;i++){
            for (int channelIndex=0; channelIndex < _sampleFormat.channels; channelIndex++) {
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
    for (int channelIndex=0; channelIndex < _sampleFormat.channels; channelIndex++) {
        free(windows[channelIndex]);
    }
}

- (void)dumpToFile
{
    FILE* fp;
    
    fp = fopen("/tmp/dumpedLazySample.raw", "wb");

    float* windows[_sampleFormat.channels];
    float* data[_sampleFormat.channels];
    const size_t channelWindowFrames = 180000;

    for (int channelIndex=0; channelIndex < _sampleFormat.channels; channelIndex++) {
        windows[channelIndex] = malloc(channelWindowFrames * sizeof(float));
    }
    
    float* output = malloc(self.frameSize * self.frames);
    float* outp = output;
    size_t left = self.frames;
    size_t offset = 0;
    while(left) {
        size_t fetchSize = MIN(channelWindowFrames, left);
        
        [self rawSampleFromFrameOffset:offset frames:fetchSize outputs:windows];

        for (int channelIndex=0; channelIndex < _sampleFormat.channels; channelIndex++) {
            data[channelIndex] = windows[channelIndex];
        }
        for (size_t i=0; i < fetchSize;i++){
            for (int channelIndex=0; channelIndex < _sampleFormat.channels; channelIndex++) {
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
    for (int channelIndex=0; channelIndex < _sampleFormat.channels; channelIndex++) {
        free(windows[channelIndex]);
    }
}

- (NSTimeInterval)duration
{
    assert(_sampleFormat.rate != 0.0);
    assert(_source.length != 0);
    return _source.length / _sampleFormat.rate;
}

- (NSTimeInterval)timeForFrame:(unsigned long long)frame
{
    assert(_sampleFormat.rate != 0.0);
    return frame / _sampleFormat.rate;
}

- (NSString*)beautifulTimeWithFrame:(unsigned long long)frame
{
    NSTimeInterval time = frame / _sampleFormat.rate;
    unsigned int hours = floor(time / 3600);
    unsigned int minutes = (unsigned int)floor(time) % 3600 / 60;
    unsigned int seconds = (unsigned int)floor(time) % 3600 % 60;
    if (hours > 0) {
        return [NSString stringWithFormat:@"%d:%02d:%02d", hours, minutes, seconds];
    }
    return [NSString stringWithFormat:@"%d:%02d", minutes, seconds];
}

- (NSString*)cueTimeWithFrame:(unsigned long long)frame
{
    NSTimeInterval time = frame / _sampleFormat.rate;
    unsigned int minutes = (unsigned int)floor(time) / 60;
    unsigned int seconds = (unsigned int)floor(time) % 60;
    return [NSString stringWithFormat:@"%02d:%02d:00", minutes, seconds];
}

- (NSString *)description
{
    return [NSString stringWithFormat:@"file: %@, channels: %d, rate: %ld, duration: %.02f seconds",
            _source.url, _sampleFormat.channels, _sampleFormat.rate, self.duration];
}

@end
