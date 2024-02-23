//
//  AudioController.m
//  PlayEm
//
//  Created by Till Toenshoff on 30.05.20.
//  Copyright © 2020 Till Toenshoff. All rights reserved.
//

#import <CoreAudio/CoreAudio.h>             // AudioDeviceID
#import <CoreAudio/CoreAudioTypes.h>
#import <CoreServices/CoreServices.h>
#import <AudioToolbox/AudioToolbox.h>

#import "AudioController.h"
#import "LazySample.h"
#import "ProfilingPointsOfInterest.h"

const unsigned int kPlaybackBufferFrames = 4096;
const unsigned int kPlaybackBufferCount = 2;
static const float kDecodingPollInterval = 0.3f;
static const float kEnoughSecondsDecoded = 5.0f;

typedef struct {
    int                         bufferIndex;
    AudioQueueBufferRef         buffers[kPlaybackBufferCount];
    LazySample*                 sample;
    unsigned long long          nextFrame;
    id<AudioControllerDelegate> delegate;
    signed long long            seekFrame;
    BOOL                        endOfStream;
    TapBlock                    tapBlock;
} AudioContext;

@interface AudioController ()
{
    AudioQueueRef           _queue;
    AudioContext            _context;
    BOOL                    _isPaused;
    double                  _outputVolume;
}

@property (strong, nonatomic) NSTimer* timer;

@end


@implementation AudioController

AVAudioFramePosition currentFrame(AudioQueueRef queue, AudioContext* context)
{
    // Now that we have a timeline included, are we going to see time adjusted
    // towards the playback delay introduced by the interface? That is something
    // we should be able to do. Needs a slow bluetooth device for testing.
    
    os_signpost_interval_begin(pointsOfInterest, POIGetCurrentFrame, "GetCurrentFrame");

    AudioQueueTimelineRef timeLine;
    OSStatus res = AudioQueueCreateTimeline(queue, &timeLine);
    
    if (res != noErr) {
        return 0;
    }
    
    AudioTimeStamp timeStamp;
    Boolean discontinued;
    
    res = AudioQueueGetCurrentTime(queue,
                                   timeLine,
                                   &timeStamp,
                                   &discontinued);

    AudioQueueDisposeTimeline(queue, timeLine);

    if (res) {
        os_signpost_interval_end(pointsOfInterest, POIGetCurrentFrame, "GetCurrentFrame", "failed");
        return 0;
    }
    if (timeStamp.mSampleTime < 0) {
        os_signpost_interval_end(pointsOfInterest, POIGetCurrentFrame, "GetCurrentFrame", "negative");
        return 0;
    }
    if (discontinued) {
        NSLog(@"discontinued queue -- needs reinitializing");
        os_signpost_interval_end(pointsOfInterest, POIGetCurrentFrame, "GetCurrentFrame", "discontinued");
        return 0;
    }
    os_signpost_interval_end(pointsOfInterest, POIGetCurrentFrame, "GetCurrentFrame", "done");

    return MIN(context->seekFrame + timeStamp.mSampleTime, context->sample.frames - 1);
}

NSTimeInterval currentTime(AudioQueueRef queue, AudioContext* context)
{
    return ((NSTimeInterval)currentFrame(queue, context) / context->sample.rate);
}

void propertyCallback (void* user_data, AudioQueueRef queue, AudioQueuePropertyID property_id)
{
    // We are only interested in the property kAudioQueueProperty_IsRunning
    if (property_id != kAudioQueueProperty_IsRunning) {
        NSLog(@"property_id %d not of interest", property_id);
        return;
    }
    assert(user_data);
    AudioContext* context = user_data;

    // Get the status of the property.
    UInt32 isRunning = FALSE;
    UInt32 size = sizeof(isRunning);
    AudioQueueGetProperty(queue, kAudioQueueProperty_IsRunning, &isRunning, &size);

    dispatch_async(dispatch_get_main_queue(), ^{
        NSLog(@"audio now running = %d", isRunning);
        if (isRunning) {
            [context->delegate audioControllerPlaybackStarted];
        } else {
            [context->delegate audioControllerPlaybackEnded];
        }
    });
}

void bufferCallback(void* user_data, AudioQueueRef queue, AudioQueueBufferRef buffer)
{
    os_signpost_interval_begin(pointsOfInterest, POIAudioBufferCallback, "AudioBufferCallback");

    assert(user_data);
    AudioContext* context = user_data;
    
    int bufferIndex = -1;
    for (int i = 0; i < kPlaybackBufferCount; i++) {
        if (buffer == context->buffers[i]) {
            bufferIndex = i;
            break;
        }
    }
    buffer->mUserData = user_data;
    unsigned int frames = buffer->mAudioDataByteSize / context->sample.frameSize;
    
    float* p = (float*)buffer->mAudioData;
    unsigned long long fetched = [context->sample rawSampleFromFrameOffset:context->nextFrame
                                                                   frames:frames
                                                                     data:p];
    // Pad last frame with silence, if needed.
    if (fetched < frames) {
        memset(p + fetched * context->sample.channels, 0, (frames - fetched) * context->sample.frameSize);
    }
    if (fetched == 0) {
        NSLog(@"reached end of stream at %lld", context->nextFrame);
        context->endOfStream = TRUE;
        // Flush data, to make sure we play to the end.
        OSStatus res = AudioQueueFlush(queue);
        assert(res == 0);
        AudioQueueStop(queue, FALSE);
    } else {
        // Is someone listening in?
        if (context->tapBlock) {
            context->tapBlock(context->nextFrame, p, frames);
        }

        context->nextFrame += fetched;
        // Play this buffer again...
        AudioQueueEnqueueBuffer(queue, buffer, 0, NULL);
    }
    context->bufferIndex = bufferIndex;
    
    os_signpost_interval_end(pointsOfInterest, POIAudioBufferCallback, "AudioBufferCallback");
}

- (id)init
{
    self = [super init];
    if (self) {
        _isPaused = NO;
        _queue = NULL;
        _outputVolume = 1.0;
    }
    return self;
}

- (void)dealloc
{
    [self reset];
}

- (void)setOutputVolume:(double)volume
{
    if (_outputVolume == volume) {
        return;
    }
    assert(_queue != nil);
    AudioQueueSetParameter(_queue, kAudioQueueParam_Volume, volume);
    _outputVolume = volume;
}

- (double)outputVolume
{
    if (_queue ==  nil) {
        return 0.0;
    }
    AudioQueueParameterValue volume;
    OSStatus res = AudioQueueGetParameter(_queue, kAudioQueueParam_Volume, &volume);
    assert(0 == res);
    _outputVolume = volume;
    return volume;
}

- (BOOL)playing
{
    if (_queue ==  nil) {
        return NO;
    }
    UInt32 isRunning = false;
    UInt32 size = sizeof(isRunning);
    OSStatus res = AudioQueueGetProperty(_queue, kAudioQueueProperty_IsRunning, &isRunning, &size);
    assert(0 == res);
    return (isRunning > 0) & !_isPaused;
}

- (void)startTapping:(TapBlock)tap
{
    _context.tapBlock = tap;
}

- (void)stopTapping
{
    _context.tapBlock = NULL;
}

- (void)playWhenReady
{
    if (self.playing) {
        return;
    }
    
    if (_context.sample.decodedFrames > _context.sample.rate * kEnoughSecondsDecoded) {
        NSLog(@"got enough data already.");
        [self playPause];
        return;
    }

    NSLog(@"waiting for more decoded audio data...");

    // TODO: We should use something more appropriate here, preventing polling.
    _timer = [NSTimer scheduledTimerWithTimeInterval:kDecodingPollInterval
                                             repeats:YES block:^(NSTimer* timer){
        if (self->_context.sample.decodedFrames >= self->_context.sample.rate * kEnoughSecondsDecoded) {
            NSLog(@"waiting done, starting playback.");
            [timer invalidate];
            self.timer = nil;
            if (!self.playing) {
                [self playPause];
            }
        } else {
            NSLog(@"still waiting for more decoded audio data...");
        }
    }];
}

- (void)playPause
{
    if (_queue == NULL) {
        NSLog(@"no queue");
        return;
    }
    if (!self.playing) {
        if (_context.endOfStream) {
            _context.endOfStream = NO;
            self.currentFrame = 0;
            _context.seekFrame = 0;
            NSLog(@"resetting playback position to start of sample");
            for (int i = 0; i < kPlaybackBufferCount; i++) {
                bufferCallback(&_context,
                               _queue,
                               _context.buffers[i]);
            }
        }

        NSLog(@"starting audioqueue");
        OSStatus res = AudioQueueStart(_queue, NULL);
        assert(0 == res);

        _isPaused = NO;
        [self.delegate audioControllerPlaybackPlaying];
    } else {
        NSLog(@"pausing audioqueue");
        OSStatus res = AudioQueuePause(_queue);
        assert(0 == res);

        _isPaused = YES;
        [self.delegate audioControllerPlaybackPaused];
    }
}

- (NSTimeInterval)currentTime
{
    return currentTime(_queue, &_context);
}

- (AVAudioFramePosition)currentFrame
{
    return currentFrame(_queue, &_context);
}

- (void)setCurrentFrame:(AVAudioFramePosition)newFrame
{
    AVAudioFramePosition oldFrame = currentFrame(_queue, &_context);

    _context.seekFrame += newFrame - oldFrame;

    assert(_context.sample.frames > 0);
    _context.nextFrame = newFrame;
}

- (void)reset
{
    NSLog(@"reset audio");
    [self stopTapping];

    [_timer invalidate];
    _timer = nil;
    
    if (_queue == NULL) {
        return;
    }

    AudioQueueStop(_queue, TRUE);

    for (int i = 0; i < kPlaybackBufferCount; i++) {
        if (_context.buffers[i] != NULL) {
            AudioQueueFreeBuffer(_queue, _context.buffers[i]);
            _context.buffers[i] = NULL;
        }
    }
    AudioQueueRemovePropertyListener(_queue, kAudioQueueProperty_IsRunning, propertyCallback, &_context);
    AudioQueueDispose(_queue, true);
    _queue = NULL;
}

- (LazySample*)sample
{
    return _context.sample;
}

- (void)setSample:(LazySample*)sample
{
    if (sample == nil) {
        NSLog(@"Update with empty sample");
        _context.sample = nil;
        return;
    }
    
    [self reset];

    _context.sample = sample;
    _context.delegate = _delegate;
    _context.nextFrame = 0;
    _context.seekFrame = 0;

    // Create an audio queue with 32bit floating point samples.
    AudioStreamBasicDescription fmt;
    memset(&fmt, 0, sizeof(fmt));
    fmt.mSampleRate = (Float64)sample.rate;
    fmt.mFormatID = kAudioFormatLinearPCM;
    fmt.mFormatFlags = kLinearPCMFormatFlagIsFloat | kAudioFormatFlagIsPacked;
    fmt.mFramesPerPacket = 1;
    fmt.mChannelsPerFrame = (uint32_t)sample.channels;
    fmt.mBytesPerFrame = (unsigned int)_context.sample.frameSize;
    fmt.mBytesPerPacket = (unsigned int)_context.sample.frameSize;
    fmt.mBitsPerChannel = 32;
    OSStatus res = AudioQueueNewOutput(&fmt, bufferCallback, &_context, NULL, NULL, 0, &_queue);
    assert((res == 0) && _queue);
   
    // Create N audio buffers.
    for (int i = 0; i < kPlaybackBufferCount; i++) {
        UInt32 size = (UInt32)_context.sample.frameSize * kPlaybackBufferFrames;
        res = AudioQueueAllocateBuffer(_queue, size, &_context.buffers[i]);
        assert((res == 0) && _context.buffers[i]);
        _context.buffers[i]->mAudioDataByteSize = size;
        _context.buffers[i]->mUserData = &_context;
        _context.bufferIndex = i;
        // Populate buffer with audio data.
        bufferCallback(&_context, _queue, _context.buffers[i]);
    }

    // Listen for kAudioQueueProperty_IsRunning.
    res = AudioQueueAddPropertyListener(_queue, 
                                        kAudioQueueProperty_IsRunning,
                                        propertyCallback,
                                        &_context);
    assert(res == 0);
    
    // Assert the new queue inherits our volume desires.
    AudioQueueSetParameter(_queue, 
                           kAudioQueueParam_Volume,
                           _outputVolume);
   
    uint32_t primed = 0;
    res = AudioQueuePrime(_queue, 0, &primed);
    assert((res == 0) && primed > 0);

    return;
}
@end
