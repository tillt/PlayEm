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
#import <CoreFoundation/CoreFoundation.h>
#import <AudioToolbox/AudioToolbox.h>

#import "AudioController.h"
#import "LazySample.h"
#import "ProfilingPointsOfInterest.h"

//#define support_rubberband YES

#include "rubberband/RubberBandStretcher.h"

const unsigned int kPlaybackBufferFrames = 4096;
const unsigned int kPlaybackBufferCount = 2;
static const float kDecodingPollInterval = 0.3f;
static const float kEnoughSecondsDecoded = 5.0f;

NSString * const kAudioControllerChangedPlaybackStateNotification = @"AudioControllerChangedPlaybackStateNotification";

typedef struct {
    int                         bufferIndex;
    AudioQueueBufferRef         buffers[kPlaybackBufferCount];
    LazySample*                 sample;
    unsigned long long          nextFrame;
    id<AudioControllerDelegate> delegate;
    signed long long            seekFrame;
    signed long long            latencyFrames;
    BOOL                        endOfStream;
    TapBlock                    tapBlock;
    RubberBand::RubberBandStretcher* stretcher;
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

NSString* deviceName(UInt32 deviceId)
{
    AudioObjectPropertyAddress namePropertyAddress = { kAudioDevicePropertyDeviceNameCFString, kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain };

    CFStringRef nameRef;
    UInt32 propertySize = sizeof(nameRef);
    OSStatus result = AudioObjectGetPropertyData(deviceId,
                                                 &namePropertyAddress,
                                                 0,
                                                 NULL,
                                                 &propertySize,
                                                 &nameRef);
    if (result != noErr) {
        NSLog(@"Failed to get device's name, err: %d", result);
        return nil;
    }
    NSString* name = (__bridge NSString*)nameRef;
    CFRelease(nameRef);
    return name;
}

AudioObjectID outputDevice(void)
{
    UInt32 deviceId;
    UInt32 propertySize = sizeof(deviceId);
    AudioObjectPropertyAddress theAddress = { kAudioHardwarePropertyDefaultOutputDevice, kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain };

    OSStatus result = AudioObjectGetPropertyData(kAudioObjectSystemObject,
                                                 &theAddress,
                                                 0,
                                                 NULL,
                                                 &propertySize,
                                                 &deviceId);
    if (result != noErr) {
        NSLog(@"Failed to get device's name, err: %d", result);
        return 0;
    }
    
    return deviceId;
}

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
        return context->nextFrame - context->latencyFrames;
    }
    os_signpost_interval_end(pointsOfInterest, POIGetCurrentFrame, "GetCurrentFrame", "done");

    return MIN(context->seekFrame + timeStamp.mSampleTime, context->sample.frames - 1);
}

NSTimeInterval currentTime(AudioQueueRef queue, AudioContext* context)
{
    return ((NSTimeInterval)currentFrame(queue, context) / context->sample.rate);
}

OSStatus propertyCallbackDefaultDevice (AudioObjectID inObjectID, UInt32 inNumberAddresses, const AudioObjectPropertyAddress inAddresses[], void *inClientData)
{
    // We are only interested in the property kAudioQueueProperty_IsRunning
    if (inAddresses->mSelector != kAudioHardwarePropertyDefaultOutputDevice) {
        NSLog(@"Selector %d not of interest", inAddresses->mSelector);
        return 0;
    }
    assert(inClientData);
    AudioContext* context = (AudioContext*)inClientData;

    NSLog(@"new default output");

    UInt32 deviceId = outputDevice();
    if (deviceId == 0) {
        return 0;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        NSString* name = deviceName(deviceId);
        NSLog(@"audio now using device %@", name);
        context->latencyFrames = latency(deviceId, kAudioDevicePropertyScopeOutput);
    });
    return 0;
}

void propertyCallbackIsRunning (void* user_data, AudioQueueRef queue, AudioQueuePropertyID property_id)
{
    // We are only interested in the property kAudioQueueProperty_IsRunning
    if (property_id != kAudioQueueProperty_IsRunning) {
        NSLog(@"property_id %d not of interest", property_id);
        return;
    }
    assert(user_data);
    AudioContext* context = (AudioContext*)user_data;

    // Get the status of the property.
    UInt32 isRunning = FALSE;
    UInt32 size = sizeof(isRunning);
    AudioQueueGetProperty(queue, kAudioQueueProperty_IsRunning, &isRunning, &size);

    dispatch_async(dispatch_get_main_queue(), ^{
        NSLog(@"audio now running = %d", isRunning);
        if (isRunning) {
            [context->delegate audioControllerPlaybackStarted];
            [[NSNotificationCenter defaultCenter] postNotificationName:kAudioControllerChangedPlaybackStateNotification
                                                                object:nil];
        } else {
            [context->delegate audioControllerPlaybackEnded];
            [[NSNotificationCenter defaultCenter] postNotificationName:kAudioControllerChangedPlaybackStateNotification
                                                                object:nil];
        }
    });
}

void bufferCallback(void* user_data, AudioQueueRef queue, AudioQueueBufferRef buffer)
{
    os_signpost_interval_begin(pointsOfInterest, POIAudioBufferCallback, "AudioBufferCallback");

    assert(user_data);
    AudioContext* context = (AudioContext*)user_data;
    
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

#ifdef support_rubberband
    // your time-processing object checks how many samples it can get from Rubber Band already (available), 
    // as there may be some in its internal buffers;
    if (context->stretcher->available() > 0) {
        context->stretcher->retrieve(p, frames);
        /*
        size_t RubberBand::RubberBandStretcher::retrieve    (    float *const *     output,
        size_t     samples
        )        const
         */
    }
    
    
    // if that is not enough:
    // it queries how many the Rubber Band stretcher needs at input before it can produce more at output (getSamplesRequired);

    // it calls back into its audio source to obtain that number of samples;
    unsigned long long fetched = [context->sample rawSampleFromFrameOffset:context->nextFrame
                                                                   frames:frames
                                                                     data:p];

    // it runs the stretcher (process), receives the available output (retrieve), and repeats if necessary

    unsigned long long fetched = ;
    

#else
    unsigned long long fetched = [context->sample rawSampleFromFrameOffset:context->nextFrame
                                                                   frames:frames
                                                                     data:p];
#endif
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

AVAudioFramePosition latency(UInt32 deviceId, AudioObjectPropertyScope scope)
{
    //NSLog(@"device %@, latency %d", nameRef);
    AudioObjectPropertyAddress deviceLatencyPropertyAddress = { kAudioDevicePropertyLatency, scope, kAudioObjectPropertyElementMain };
    UInt32 deviceLatency;
    UInt32 propertySize = sizeof(deviceLatency);
    OSStatus result = result = AudioObjectGetPropertyData(deviceId, &deviceLatencyPropertyAddress, 0, NULL, &propertySize, &deviceLatency);
    if (result != noErr) {
        NSLog(@"Failed to get latency, err: %d", result);
        return -1;
    }

    AudioObjectPropertyAddress safetyOffsetPropertyAddress = { kAudioDevicePropertySafetyOffset, scope, kAudioObjectPropertyElementMain };
    UInt32 safetyOffset;
    propertySize = sizeof(safetyOffset);
    result = AudioObjectGetPropertyData(deviceId, &safetyOffsetPropertyAddress, 0, NULL, &propertySize, &safetyOffset);
    if (result != noErr) {
        NSLog(@"Failed to get safety offset, err: %d", result);
        return -1;
    }

    AudioObjectPropertyAddress bufferSizePropertyAddress = { kAudioDevicePropertyBufferFrameSize, scope, kAudioObjectPropertyElementMain };
    UInt32 bufferSize;
    propertySize = sizeof(bufferSize);
    result = AudioObjectGetPropertyData(deviceId, &bufferSizePropertyAddress, 0, NULL, &propertySize, &bufferSize);
    if (result != noErr) {
        NSLog(@"Failed to get latency, err: %d", result);
        return -1;
    }

    AudioObjectPropertyAddress streamsPropertyAddress = { kAudioDevicePropertyStreams, scope, kAudioObjectPropertyElementMain };

    UInt32 streamLatency = 0;
    UInt32 streamsSize = 0;
    AudioObjectGetPropertyDataSize (deviceId, &streamsPropertyAddress, 0, NULL, &streamsSize);
    if (streamsSize >= sizeof(AudioStreamID)) {
        NSMutableData* streamIDs = [NSMutableData dataWithCapacity:streamsSize];
        AudioStreamID* ids = (AudioStreamID*)streamIDs.mutableBytes;
        result = AudioObjectGetPropertyData(deviceId, &streamsPropertyAddress, 0, nullptr, &streamsSize, ids);
        if (result != noErr) {
            NSLog(@"Failed to get streams, err: %d", result);
            return -1;
        }

        // get the latency of the first stream
        AudioObjectPropertyAddress streamLatencyPropertyAddress = { kAudioStreamPropertyLatency, scope, kAudioObjectPropertyElementMain };
        propertySize = sizeof(streamLatency);
        result = AudioObjectGetPropertyData (ids[0], &streamLatencyPropertyAddress, 0, NULL, &propertySize, &streamLatency);
        if (result != noErr) {
            NSLog(@"Failed to get stream latency, err: %d", result);
            return -1;
        }
    }
    
    AVAudioFramePosition totalLatency = deviceLatency + streamLatency + safetyOffset + bufferSize;

    NSLog(@"%d frames device latency,  %d frames output stream latency, %d safety offset, %d buffer size resulting in an estimated total latency of %lld frames", deviceLatency, streamLatency, safetyOffset, bufferSize, totalLatency);

    return totalLatency;
}

- (id)init
{
    self = [super init];
    if (self) {
        _isPaused = NO;
        _queue = NULL;
        _outputVolume = 1.0;

        AudioObjectPropertyAddress defaultDevicePropertyAddress = { kAudioHardwarePropertyDefaultOutputDevice, kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain };
        OSStatus res = AudioObjectAddPropertyListener(kAudioObjectSystemObject, &defaultDevicePropertyAddress, propertyCallbackDefaultDevice, &_context);
        assert(res == 0);
    }
    return self;
}

- (void)dealloc
{
    [self reset];
    
    AudioObjectPropertyAddress defaultDevicePropertyAddress = { kAudioHardwarePropertyDefaultOutputDevice, kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain };
    AudioObjectRemovePropertyListener(kAudioObjectSystemObject,
                                      &defaultDevicePropertyAddress,
                                      propertyCallbackDefaultDevice,
                                      &_context);
}

- (void)setTempoShift:(double)tempoShift
{
    assert(_queue != nil);
}

- (double)tempoShift
{
    if (_queue ==  nil) {
        return 1.0;
    }
    return 1.0;
}

- (void)setOutputVolume:(double)volume
{
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

- (void)playWhenReady:(unsigned long long)nextFrame paused:(BOOL)paused
{
    if (self.playing) {
        NSLog(@"playing already");
        return;
    }
    
    const unsigned long long enoughFrames = _context.sample.rate * kEnoughSecondsDecoded;
    
    if (nextFrame + enoughFrames >= _context.sample.frames) {
        NSLog(@"too late for restarting from that position again");
        nextFrame = 0LL;
    }
    
    if (_context.sample.decodedFrames >= nextFrame + enoughFrames) {
        NSLog(@"got enough data already.");
        [self play];
        return;
    }

    NSLog(@"waiting for more decoded audio data...");

    // TODO: We should use something more appropriate here, preventing polling.
    _timer = [NSTimer scheduledTimerWithTimeInterval:kDecodingPollInterval
                                             repeats:YES block:^(NSTimer* timer){
        if (self->_context.sample.decodedFrames >= nextFrame + (self->_context.sample.rate * kEnoughSecondsDecoded)) {
            NSLog(@"waiting done, triggering...");
            [timer invalidate];
            self.timer = nil;
            [self setCurrentFrame:nextFrame];
            [self play];
            if (paused) {
                [self pause];
            }
        } else {
            NSLog(@"still waiting for more decoded audio data...");
        }
    }];
}

- (void)playPause
{
    if (!self.playing) {
        [self play];
    } else {
        [self pause];
    }
}

- (void)pause
{
    if (_queue == NULL) {
        NSLog(@"no queue");
        return;
    }

    NSLog(@"pausing audioqueue");
    OSStatus res = AudioQueuePause(_queue);
    assert(0 == res);

    _isPaused = YES;
    [self.delegate audioControllerPlaybackPaused];
    [[NSNotificationCenter defaultCenter] postNotificationName:kAudioControllerChangedPlaybackStateNotification
                                                        object:self];
}

- (void)play
{
    if (_queue == NULL) {
        NSLog(@"no queue");
        return;
    }
    if (self.playing) {
        NSLog(@"already playing");
        return;
    }
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
    [[NSNotificationCenter defaultCenter] postNotificationName:kAudioControllerChangedPlaybackStateNotification
                                                        object:self];
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

- (AVAudioFramePosition)frameCountDeltaWithTimeDelta:(NSTimeInterval)duration
{
    return ceil(_context.sample.rate * duration);
}

- (void)reset
{
    NSLog(@"reset audio");
    [self stopTapping];
    
    [_timer invalidate];
    _timer = nil;
    
    if (_queue != NULL) {
        AudioQueueStop(_queue, TRUE);
        
        for (int i = 0; i < kPlaybackBufferCount; i++) {
            if (_context.buffers[i] != NULL) {
                AudioQueueFreeBuffer(_queue, _context.buffers[i]);
                _context.buffers[i] = NULL;
            }
        }
        AudioQueueRemovePropertyListener(_queue, kAudioQueueProperty_IsRunning, propertyCallbackIsRunning, &_context);

        AudioQueueDispose(_queue, true);
        _queue = NULL;
    }
    
    UInt32 deviceId = outputDevice();
    if (deviceId == 0) {
        NSLog(@"couldnt get output device -- that is unexpected");
        return;
    }
    NSString* name = deviceName(deviceId);
    _context.latencyFrames = latency(deviceId, kAudioDevicePropertyScopeOutput);
    NSLog(@"playback will happen on device %@ with a latency of %lld frames", name, _context.latencyFrames);
}

- (AVAudioFramePosition)latency
{
    return _context.latencyFrames;
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
                                        propertyCallbackIsRunning,
                                        &_context);
    assert(res == 0);

    // Assert the new queue inherits our volume desires.
    AudioQueueSetParameter(_queue, kAudioQueueParam_Volume, _outputVolume);
   
    uint32_t primed = 0;
    res = AudioQueuePrime(_queue, 0, &primed);
    assert((res == 0) && primed > 0);
    
#ifdef support_rubberband
    _context.stretcher = new RubberBand::RubberBandStretcher(sample.rate, sample.channels);
    _context.stretcher->setTimeRatio(1.2);
    _context.stretcher->setPitchScale(1.02);
#endif
    return;
}
@end
