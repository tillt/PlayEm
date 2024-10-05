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
#import <CoreWLAN/CoreWLAN.h>
#import <AVKit/AVKit.h>

#import "AudioController.h"
#import "LazySample.h"
#import "ProfilingPointsOfInterest.h"

//#define support_rubberband YES
#define support_multi_output    YES
//#define support_avaudioengine   YES
//#define support_avplayer        YES
#define support_audioqueueplayback  YES


#include "rubberband/RubberBandStretcher.h"

const unsigned int kPlaybackBufferFrames = 4096;
const unsigned int kPlaybackBufferCount = 2;
static const float kDecodingPollInterval = 0.3f;
static const float kEnoughSecondsDecoded = 5.0f;
static const size_t kDecoderBufferFrames = 16384;

NSString * const kAudioControllerChangedPlaybackStateNotification = @"AudioControllerChangedPlaybackStateNotification";
NSString * const kPlaybackStateStarted = @"started";
NSString * const kPlaybackStatePaused = @"paused";
NSString * const kPlaybackStatePlaying = @"playing";
NSString * const kPlaybackStateEnded = @"ended";

#ifdef support_multi_output

typedef struct {
#ifdef support_audioqueueplayback
    AudioQueueRef               queue;
    AudioQueueBufferRef         buffers[kPlaybackBufferCount];
#endif
    int                         bufferIndex;
    unsigned long long          nextFrame;
    signed long long            latencyFrames;
} AudioOutputStream;
#endif

typedef struct {
    LazySample*                 sample;
    AudioOutputStream           stream;
    unsigned long long          nextFrame;
    //id<AudioControllerDelegate> delegate;
    signed long long            seekFrame;
    BOOL                        endOfStream;
    TapBlock                    tapBlock;
    dispatch_semaphore_t        semaphore;
#ifdef support_rubberband
    RubberBand::RubberBandStretcher* stretcher;
#endif
} AudioContext;

@interface AudioController ()
{
    AudioContext            _context;
    BOOL                    _isPaused;
    double                  _outputVolume;
}
@property (strong, nonatomic) NSTimer* timer;
#ifdef support_avaudioengine
@property (strong, nonatomic) AVAudioEngine*              engine;
@property (strong, nonatomic) AVAudioPlayerNode*          player;

@property (strong, nonatomic) NSArray<AVAudioPCMBuffer*>* buffers;
#endif
#ifdef support_avplayer
#endif
@property (strong, nonatomic) dispatch_block_t            decodeOperation;

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

AudioObjectID defaultOutputDevice(void)
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

#ifdef support_audioqueueplayback
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
        return context->nextFrame - context->stream.latencyFrames;
    }
    os_signpost_interval_end(pointsOfInterest, POIGetCurrentFrame, "GetCurrentFrame", "done");

    return MIN(context->seekFrame + timeStamp.mSampleTime, context->sample.frames - 1);
}

NSTimeInterval currentTime(AudioQueueRef queue, AudioContext* context)
{
    return ((NSTimeInterval)currentFrame(queue, context) / context->sample.rate);
}
#endif

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

    UInt32 deviceId = defaultOutputDevice();
    if (deviceId == 0) {
        return 0;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        NSString* name = deviceName(deviceId);
        NSLog(@"audio output now using device %@", name);
        context->stream.latencyFrames = totalLatency(deviceId, kAudioDevicePropertyScopeOutput);
        NSLog(@"audio output latency %lld frames", context->stream.latencyFrames);
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
            [[NSNotificationCenter defaultCenter] postNotificationName:kAudioControllerChangedPlaybackStateNotification
                                                                object:kPlaybackStatePlaying];
        } else {
            if (context->endOfStream) {
                context->endOfStream = NO;
                [[NSNotificationCenter defaultCenter] postNotificationName:kAudioControllerChangedPlaybackStateNotification
                                                                    object:kPlaybackStateEnded];
            } else {
                [[NSNotificationCenter defaultCenter] postNotificationName:kAudioControllerChangedPlaybackStateNotification
                                                                    object:kPlaybackStatePaused];
            }
        }
    });
}

#ifdef support_audioqueueplayback
void bufferCallback(void* user_data, AudioQueueRef queue, AudioQueueBufferRef buffer)
{
    os_signpost_interval_begin(pointsOfInterest, POIAudioBufferCallback, "AudioBufferCallback");
    
    assert(user_data);
    AudioContext* context = (AudioContext*)user_data;

    float* p = (float*)buffer->mAudioData;
    buffer->mUserData = user_data;
    unsigned int frames = buffer->mAudioDataByteSize / context->sample.frameSize;

//    // your time-processing object checks how many samples it can get from Rubber Band already (available),
//    // as there may be some in its internal buffers;
//    if (context->stretcher->available() > 0) {
//        context->stretcher->retrieve(p, frames);
//        /*
//        size_t RubberBand::RubberBandStretcher::retrieve    (    float *const *     output,
//        size_t     samples
//        )        const
//         */
//    }
//    // if that is not enough:
//    // it queries how many the Rubber Band stretcher needs at input before it can produce more at output (getSamplesRequired);
//    // it calls back into its audio source to obtain that number of samples;
//    unsigned long long fetched = [context->sample rawSampleFromFrameOffset:context->nextFrame
//                                                                   frames:frames
//                                                                     data:p];
//
//    // it runs the stretcher (process), receives the available output (retrieve), and repeats if necessary
//    unsigned long long fetched = ;
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
    os_signpost_interval_end(pointsOfInterest, POIAudioBufferCallback, "AudioBufferCallback");
}
#endif

AVAudioFramePosition totalLatency(UInt32 deviceId, AudioObjectPropertyScope scope)
{
    // Get the device latency.
    AudioObjectPropertyAddress deviceLatencyPropertyAddress = { kAudioDevicePropertyLatency, scope, kAudioObjectPropertyElementMain };
    UInt32 deviceLatency;
    UInt32 propertySize = sizeof(deviceLatency);
    OSStatus result = result = AudioObjectGetPropertyData(deviceId, &deviceLatencyPropertyAddress, 0, NULL, &propertySize, &deviceLatency);
    if (result != noErr) {
        NSLog(@"Failed to get latency, err: %d", result);
        return 0;
    }

    // Get the safety offset.
    AudioObjectPropertyAddress safetyOffsetPropertyAddress = { kAudioDevicePropertySafetyOffset, scope, kAudioObjectPropertyElementMain };
    UInt32 safetyOffset;
    propertySize = sizeof(safetyOffset);
    result = AudioObjectGetPropertyData(deviceId, &safetyOffsetPropertyAddress, 0, NULL, &propertySize, &safetyOffset);
    if (result != noErr) {
        NSLog(@"Failed to get safety offset, err: %d", result);
        return 0;
    }

    // Get the buffer size.
    AudioObjectPropertyAddress bufferSizePropertyAddress = { kAudioDevicePropertyBufferFrameSize, scope, kAudioObjectPropertyElementMain };
    UInt32 bufferSize;
    propertySize = sizeof(bufferSize);
    result = AudioObjectGetPropertyData(deviceId, &bufferSizePropertyAddress, 0, NULL, &propertySize, &bufferSize);
    if (result != noErr) {
        NSLog(@"Failed to get latency, err: %d", result);
        return 0;
    }

    AudioObjectPropertyAddress streamsPropertyAddress = { kAudioDevicePropertyStreams, scope, kAudioObjectPropertyElementMain };

    UInt32 streamLatency = 0;
    UInt32 streamsSize = 0;
    AudioObjectGetPropertyDataSize (deviceId, &streamsPropertyAddress, 0, NULL, &streamsSize);
    if (streamsSize >= sizeof(AudioStreamID)) {
        // Get the latency of the first stream.
        NSMutableData* streamIDs = [NSMutableData dataWithCapacity:streamsSize];
        AudioStreamID* ids = (AudioStreamID*)streamIDs.mutableBytes;
        result = AudioObjectGetPropertyData(deviceId, &streamsPropertyAddress, 0, nullptr, &streamsSize, ids);
        if (result != noErr) {
            NSLog(@"Failed to get streams, err: %d", result);
            return 0;
        }

        AudioObjectPropertyAddress streamLatencyPropertyAddress = { kAudioStreamPropertyLatency, scope, kAudioObjectPropertyElementMain };
        propertySize = sizeof(streamLatency);
        result = AudioObjectGetPropertyData(ids[0], &streamLatencyPropertyAddress, 0, NULL, &propertySize, &streamLatency);
        if (result != noErr) {
            NSLog(@"Failed to get stream latency, err: %d", result);
            return 0;
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
#ifdef support_audioqueueplayback
        _context.stream.queue = NULL;
#endif
#ifdef support_avaudioengine
        _engine = nil;
        _player = nil;
#endif
        _outputVolume = 1.0;
     
        _context.semaphore = dispatch_semaphore_create(kPlaybackBufferCount);

        AudioObjectPropertyAddress defaultDevicePropertyAddress = { kAudioHardwarePropertyDefaultOutputDevice, kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain };
        OSStatus res = AudioObjectAddPropertyListener(kAudioObjectSystemObject, &defaultDevicePropertyAddress, propertyCallbackDefaultDevice, &_context);
        assert(res == 0);
        _decodeOperation = NULL;
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
#ifdef support_audioqueueplayback
    assert(_context.stream.queue != nil);
#endif
}

- (double)tempoShift
{
#ifdef support_audioqueueplayback
    if (_context.stream.queue ==  nil) {
        return 1.0;
    }
#endif
    return 1.0;
}

- (void)setOutputVolume:(double)volume
{
#ifdef support_audioqueueplayback
    assert(_context.stream.queue != nil);
    AudioQueueSetParameter(_context.stream.queue, kAudioQueueParam_Volume, volume);
#endif
    _outputVolume = volume;
}

- (double)outputVolume
{
#ifdef support_audioqueueplayback
    if (_context.stream.queue ==  nil) {
        return 0.0;
    }
    AudioQueueParameterValue volume;
    OSStatus res = AudioQueueGetParameter(_context.stream.queue, kAudioQueueParam_Volume, &volume);
    assert(0 == res);
    _outputVolume = volume;
    return volume;
#endif
    return _outputVolume;
}

- (BOOL)playing
{
#ifdef support_audioqueueplayback
    if (_context.stream.queue ==  nil) {
        return NO;
    }
    UInt32 isRunning = false;
    UInt32 size = sizeof(isRunning);
    OSStatus res = AudioQueueGetProperty(_context.stream.queue, kAudioQueueProperty_IsRunning, &isRunning, &size);
    assert(0 == res);
    return (isRunning > 0) & !_isPaused;
#endif
    
#ifdef support_avaudioengine
    return _player.isPlaying & !_isPaused;
#endif
    
#ifdef support_avplayer
    return _player.timeControlStatus == AVPlayerTimeControlStatusPlaying;
#endif
}

- (void)startTapping:(TapBlock)tap
{
    _context.tapBlock = tap;
}

- (void)stopTapping
{
    _context.tapBlock = NULL;
}

- (void)playSample:(LazySample*)sample frame:(unsigned long long)nextFrame paused:(BOOL)paused
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
        self.timer = nil;
        [self setCurrentFrame:nextFrame];
        [self play];
        if (paused) {
            [self pause];
        }
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

- (void)togglePause
{
    if (!self.playing) {
        [self play];
    } else {
        [self pause];
    }
}

- (void)pause
{
#ifdef support_audioqueueplayback
    if (_context.stream.queue == NULL) {
        NSLog(@"no queue");
        return;
    }

    NSLog(@"pausing audioqueue");
    OSStatus res = AudioQueuePause(_context.stream.queue);
    assert(0 == res);
#endif

#ifdef support_avaudioengine
    [_player pause];
#endif

    _isPaused = YES;
    [[NSNotificationCenter defaultCenter] postNotificationName:kAudioControllerChangedPlaybackStateNotification
                                                        object:kPlaybackStatePaused];
}

#ifdef support_avplayer
- (void)play
{
    if (self.playing) {
        NSLog(@"already playing");
        return;
    }
    NSLog(@"starting playback...");
    [_player play];

    _isPaused = NO;
    [[NSNotificationCenter defaultCenter] postNotificationName:kAudioControllerChangedPlaybackStateNotification
                                                        object:self];
}
#endif

#ifdef support_audioqueueplayback
- (void)play
{
    if (self.playing) {
        NSLog(@"already playing");
        return;
    }
    if (_context.stream.queue == NULL) {
        NSLog(@"no queue");
        return;
    }
    if (_context.endOfStream) {
        _context.endOfStream = NO;
        self.currentFrame = 0;
        _context.seekFrame = 0;
        NSLog(@"resetting playback position to start of sample");
        for (int i = 0; i < kPlaybackBufferCount; i++) {
            bufferCallback(&_context,
                           _context.stream.queue,
                           _context.stream.buffers[i]);
        }
    }
    
    NSLog(@"starting audioqueue to play %@", _context.sample.source.url);
    OSStatus res = AudioQueueStart(_context.stream.queue, NULL);
    assert(0 == res);
    _isPaused = NO;

    [[NSNotificationCenter defaultCenter] postNotificationName:kAudioControllerChangedPlaybackStateNotification
                                                        object:kPlaybackStateStarted];
    [[NSNotificationCenter defaultCenter] postNotificationName:kAudioControllerChangedPlaybackStateNotification
                                                        object:kPlaybackStatePlaying];
}
#endif

#ifdef support_avaudioengine
- (void)play
{
    if (self.playing) {
        NSLog(@"already playing");
        return;
    }
    
    NSLog(@"starting playback...");
    [_player play];

    [self.delegate audioControllerPlaybackStarted];
    [self.delegate audioControllerPlaybackPlaying];

    NSLog(@"engine state: %@", [_engine description]);
    assert(_engine.isRunning);
    _isPaused = NO;
    [[NSNotificationCenter defaultCenter] postNotificationName:kAudioControllerChangedPlaybackStateNotification
                                                        object:self];
}
#endif

- (NSTimeInterval)currentTime
{
#ifdef support_audioqueueplayback
    return currentTime(_context.stream.queue, &_context);
#endif
#ifdef support_avaudioengine
    return [self currentFrame] / _context.sample.rate;
#endif
#ifdef support_avplayer
    return CMTimeGetSeconds(_player.currentTime);
#endif
}

- (void)setCurrentTime:(NSTimeInterval)time
{
    [self setCurrentFrame:time * _context.sample.rate];
}

- (AVAudioFramePosition)currentFrame
{
#ifdef support_audioqueueplayback
    return currentFrame(_context.stream.queue, &_context);
#endif
    
#ifdef support_avaudioengine
    if (_player.isPlaying) {
        AVAudioTime* nodeTime = [_player lastRenderTime];
        if (nodeTime) {
            AVAudioTime* playerTime = [_player playerTimeForNodeTime:nodeTime];
            
            if (playerTime) {
                return playerTime.sampleTime;
                // Calculate playback position in seconds
                //NSTimeInterval playbackPosition = (NSTimeInterval)playerTime.sampleTime / playerTime.sampleRate;
                //NSLog(@"Playback Position: %f seconds", playbackPosition);
            } else {
                NSLog(@"Player time is not available.");
            }
        } else {
            NSLog(@"Node time is not available.");
        }
    } else {
        NSLog(@"Player not playing.");
        return _context.nextFrame;
    }
    return 0.0;
#endif
    
#ifdef support_avplayer
    return [self currentTime] * _context.sample.rate;
#endif
}

- (void)setCurrentFrame:(AVAudioFramePosition)newFrame
{
    assert(newFrame < _context.sample.frames);
    AVAudioFramePosition oldFrame = self.currentFrame;
    _context.seekFrame += newFrame - oldFrame;
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
    
#ifdef support_audioqueueplayback
    if (_context.stream.queue != NULL) {
        AudioQueueStop(_context.stream.queue, TRUE);
        
        for (int i = 0; i < kPlaybackBufferCount; i++) {
            if (_context.stream.buffers[i] != NULL) {
                AudioQueueFreeBuffer(_context.stream.queue, _context.stream.buffers[i]);
                _context.stream.buffers[i] = NULL;
            }
        }
        AudioQueueRemovePropertyListener(_context.stream.queue, kAudioQueueProperty_IsRunning, propertyCallbackIsRunning, &_context);

        AudioQueueDispose(_context.stream.queue, true);
        _context.stream.queue = NULL;
    }
#endif
    
#ifdef support_avaudioengine
//    [_player stop];
//    [_engine stop];
////
//    NSLog(@"releasing player...");
//    _player = nil;
//
//    NSLog(@"releasing engine...");
//    _engine = nil;
#endif

    UInt32 deviceId = defaultOutputDevice();
    if (deviceId == 0) {
        NSLog(@"couldnt get output device -- that is unexpected");
        return;
    }
    NSString* name = deviceName(deviceId);
    _context.stream.latencyFrames = totalLatency(deviceId, kAudioDevicePropertyScopeOutput);
    NSLog(@"playback will happen on device %@ with a latency of %lld frames", name, _context.stream.latencyFrames);
}

- (AVAudioFramePosition)totalLatency
{
    return _context.stream.latencyFrames;
}

- (LazySample*)sample
{
    return _context.sample;
}

- (NSArray*)createBuffersWithFormat:(AVAudioFormat*)format
{
    NSMutableArray* buffers = [NSMutableArray arrayWithCapacity:kPlaybackBufferCount];
    for (int i=0;i < kPlaybackBufferCount;i++) {
        AVAudioPCMBuffer* buffer = [[AVAudioPCMBuffer alloc] initWithPCMFormat:format
                                                                 frameCapacity:kPlaybackBufferFrames];
        [buffers addObject:buffer];
    }
    return buffers;
}

void LogBufferContents(const uint8_t *buffer, size_t length)
{
    NSMutableString *bufferString = [NSMutableString stringWithCapacity:length * 3];
    
    for (size_t i = 0; i < length; i++) {
        [bufferString appendFormat:@"%02x ", buffer[i]];
    }

    NSLog(@"buffer contents: %@", bufferString);
}

- (BOOL)fillBuffer:(AVAudioPCMBuffer*)buffer
{
    NSLog(@"filling buffer : %@", buffer);
    //dispatch_semaphore_wait(context->semaphore, DISPATCH_TIME_FOREVER);
    unsigned int frames = buffer.frameCapacity;
    
    float* output[2] = { buffer.floatChannelData[0], buffer.floatChannelData[1] };
    unsigned long long fetched = [_context.sample rawSampleFromFrameOffset:_context.nextFrame
                                                                    frames:frames
                                                                   outputs:output];
    
    _context.nextFrame += fetched;
    
//    LogBufferContents((const uint8_t *)buffer.floatChannelData[0], 32);
//    LogBufferContents((const uint8_t *)buffer.floatChannelData[1], 32);
//    LogBufferContents((const uint8_t *)buffer.floatChannelData[0]+32, 32);
//    LogBufferContents((const uint8_t *)buffer.floatChannelData[1]+32, 32);
//    LogBufferContents((const uint8_t *)buffer.floatChannelData[0]+64, 32);
//    LogBufferContents((const uint8_t *)buffer.floatChannelData[1]+64, 32);
//    LogBufferContents((const uint8_t *)buffer.floatChannelData[0]+96, 32);
//    LogBufferContents((const uint8_t *)buffer.floatChannelData[1]+96, 32);

    if (fetched == 0) {
        NSLog(@"reached end of stream at %lld", _context.nextFrame);
        return NO;
    }
    return YES;
}

#ifdef support_avplayer
- (BOOL)setupPlayerWithSample:(LazySample*)sample error:(NSError**)error
{
    NSLog(@"new engine...");
    self.player = [[AVPlayer alloc] initWithURL:sample.source.url];
    return YES;
}
#endif

#ifdef support_avaudioengine
- (void)scheduleNextBuffer
{
    int index = self->_context.stream[0].bufferIndex;
    AVAudioPCMBuffer* buffer = self->_buffers[index];
    
    NSLog(@"scheduling %@", buffer);
    [_player scheduleBuffer:buffer completionHandler:^{
        NSLog(@"done with %@", buffer);
        if ([self fillBuffer:buffer]) {
            [self scheduleNextBuffer];
        };
    }];

    _context.stream[0].bufferIndex = (index + 1) % 2;
}

- (BOOL)setupEngineWithSample:(LazySample*)sample error:(NSError**)error
{
    NSLog(@"new engine...");
    self.engine = [[AVAudioEngine alloc] init];

    self.player = [[AVAudioPlayerNode alloc] init];
    [_engine attachNode:_player];

    AVAudioFormat* format = sample.source.processingFormat;
    self.buffers = [self createBuffersWithFormat:format];
    [self fillBuffer:self->_buffers[0]];
    [self fillBuffer:self->_buffers[1]];

    NSLog(@"connecting player to engine...");
    [_engine connect:_player
                  to:_engine.mainMixerNode
              format:format];

    [_engine connect:_engine.mainMixerNode
                  to:_engine.outputNode
              format:nil];

    NSLog(@"starting engine...");
    if (![_engine startAndReturnError:error]) {
        NSLog(@"startAndReturnError failed: %@\n", *error);
        return NO;
    }
    assert(!_engine.isInManualRenderingMode);

    _context.stream[0].bufferIndex = 0;

    NSLog(@"preparing engine...");
    //[_engine prepare];

    NSLog(@"engine state: %@", [_engine debugDescription]);

//    [self scheduleNextBuffer];
//    [self scheduleNextBuffer];
    
    [_player scheduleFile:sample.source atTime:nil completionHandler:nil];

    return YES;
}
#endif

#ifdef support_audioqueueplayback
- (AudioQueueRef)createQueueWithSample:(LazySample*)sample
{
    AudioQueueRef queue = NULL;
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
    OSStatus res = AudioQueueNewOutput(&fmt, bufferCallback, &_context, NULL, NULL, 0, &queue);
    assert((res == 0) && queue);
    return queue;
}
#endif

- (void)setSample:(LazySample*)sample
{
    if (sample == nil) {
        NSLog(@"Update with empty sample");
        _context.sample = nil;
        return;
    }
    NSLog(@"audiocontroller update with new sample %@", sample.source.url);

    [self reset];

    _context.sample = sample;
    _context.nextFrame = 0;
    _context.seekFrame = 0;

#ifdef support_avaudioengine
    NSError* error = nil;
    if (![self setupEngineWithSample:_context.sample error:&error]) {
        NSLog(@"failed to setup engine: %@", error);
    }
#endif

#ifdef support_avplayer
    NSError* error = nil;
    if (![self setupPlayerWithSample:_context.sample error:&error]) {
        NSLog(@"failed to setup player: %@", error);
    }
#endif

#ifdef support_audioqueueplayback
    _context.stream.queue = [self createQueueWithSample:sample];

    OSStatus res;
    // Create N audio buffers.
    for (int i = 0; i < kPlaybackBufferCount; i++) {
        UInt32 size = (UInt32)_context.sample.frameSize * kPlaybackBufferFrames;
        res = AudioQueueAllocateBuffer(_context.stream.queue, size, &_context.stream.buffers[i]);
        assert((res == 0) && _context.stream.buffers[i]);
        _context.stream.buffers[i]->mAudioDataByteSize = size;
        _context.stream.buffers[i]->mUserData = &_context;
        _context.stream.bufferIndex = i;
        // Populate buffer with audio data.
        bufferCallback(&_context, _context.stream.queue, _context.stream.buffers[i]);
    }
    // Listen for kAudioQueueProperty_IsRunning.
    res = AudioQueueAddPropertyListener(_context.stream.queue,
                                        kAudioQueueProperty_IsRunning,
                                        propertyCallbackIsRunning,
                                        &_context);
    assert(res == 0);

    // Assert the new queue inherits our volume desires.
    AudioQueueSetParameter(_context.stream.queue, kAudioQueueParam_Volume, _outputVolume);

    uint32_t primed = 0;
    res = AudioQueuePrime(_context.stream.queue, 0, &primed);
    assert((res == 0) && primed > 0);
#endif

#ifdef support_rubberband
    _context.stretcher = new RubberBand::RubberBandStretcher(sample.rate, sample.channels);
    _context.stretcher->setTimeRatio(1.2);
    _context.stretcher->setPitchScale(1.02);
#endif
    return;
}

- (void)decodeAbortWithCallback:(void (^)(void))callback
{
    if (_decodeOperation != NULL) {
        dispatch_block_cancel(_decodeOperation);
        dispatch_block_notify(_decodeOperation, dispatch_get_main_queue(), ^{
            callback();
        });
    } else {
        callback();
    }
}

- (void)decodeAsyncWithSample:(LazySample*)sample callback:(void (^)(BOOL))callback
{
#ifdef DEBUGGING
    __block BOOL done = NO;
    _queueOperation = dispatch_block_create(DISPATCH_BLOCK_NO_QOS_CLASS, ^{
        done = [self decode];
    });
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), _queueOperation);
    dispatch_block_notify(_queueOperation, dispatch_get_main_queue(), ^{
        callback(done);
    });
#else
    __block BOOL done = NO;
    _decodeOperation = dispatch_block_create(DISPATCH_BLOCK_NO_QOS_CLASS, ^{
        done = [self decode:sample cancelTest:^{
            if (dispatch_block_testcancel(self->_decodeOperation) != 0) {
                return YES;
            }
            return NO;
        }];
    });
    
    // Run the decode operation!
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), _decodeOperation);
    // Dispatch a callback on the main thread once decoding is done.
    dispatch_block_notify(_decodeOperation, dispatch_get_main_queue(), ^{
        callback(done);
    });
#endif
}

- (BOOL)decode:(LazySample*)sample cancelTest:(BOOL (^)(void))cancelTest
{
    NSLog(@"decoding sample %@...", sample);
    AVAudioEngine* engine = [[AVAudioEngine alloc] init];

    NSLog(@"enabling manual render...");
    NSError* error = nil;
    [engine enableManualRenderingMode:AVAudioEngineManualRenderingModeOffline
                               format:sample.source.processingFormat
                    maximumFrameCount:kDecoderBufferFrames
                                error:&error];

    AVAudioPlayerNode* player = [[AVAudioPlayerNode alloc] init];

    NSLog(@"attaching player node...");
    [engine attachNode:player];

    NSLog(@"connecting player to engine...");
    [engine connect:player
                 to:engine.outputNode
             format:sample.source.processingFormat];

    NSLog(@"starting engine...");
    if (![engine startAndReturnError:&error]) {
        NSLog(@"startAndReturnError failed: %@\n", error);
        return NO;
    }

    NSLog(@"scheduling file...");
    [player scheduleFile:sample.source atTime:0 completionHandler:nil];

    NSLog(@"engine state: %@", [engine description]);

    AVAudioPCMBuffer* buffer =
        [[AVAudioPCMBuffer alloc] initWithPCMFormat:engine.manualRenderingFormat
                                      frameCapacity:kDecoderBufferFrames];
    
    NSLog(@"manual rendering maximum frame count: %d\n", engine.manualRenderingMaximumFrameCount);

    [player play];

    unsigned long long pageIndex = 0;
    
    BOOL ret = YES;

    while (engine.manualRenderingSampleTime < sample.source.length) {
        if (cancelTest()) {
            ret = NO;
            NSLog(@"...decoding aborted!!!");
            break;
        }
        //NSLog(@"manual rendering sample time: %lld\n", _engine.manualRenderingSampleTime);
        // `_source.length` is the number of sample frames in the file.
        // `_engine.manualRenderingSampleTime`
        unsigned long long frameLeftCount = sample.source.length - engine.manualRenderingSampleTime;
        //_engine.manualRenderingMaximumFrameCount

        if ((unsigned long long)buffer.frameCapacity > frameLeftCount) {
            NSLog(@"last tile rendereing: %lld", pageIndex);
        }
        AVAudioFrameCount framesToRender = (AVAudioFrameCount)MIN(frameLeftCount, (long long)buffer.frameCapacity);
        AVAudioEngineManualRenderingStatus status = [engine renderOffline:framesToRender
                                                                 toBuffer:buffer
                                                                    error:&error];

        switch (status) {
            case AVAudioEngineManualRenderingStatusSuccess: {
                unsigned long long rawDataLengthPerChannel = buffer.frameLength * sizeof(float);
                
                NSMutableArray<NSData*>* channels = [NSMutableArray array];
                
                for (int channelIndex = 0; channelIndex < sample.channels; channelIndex++) {
                    NSData* channel = [NSData dataWithBytes:buffer.floatChannelData[channelIndex]
                                                     length:rawDataLengthPerChannel];
                    [channels addObject:channel];
                }
                [sample addLazyPageIndex:pageIndex channels:channels];
                pageIndex++;
            }
            // Whenever the engine needs more data, this will get triggered - for our manual
            // rendering this comes directly before `AVAudioEngineManualRenderingStatusSuccess`.
            case AVAudioEngineManualRenderingStatusInsufficientDataFromInputNode:
                break;
            case AVAudioEngineManualRenderingStatusError:
                NSLog(@"renderOffline failed: %@\n", error);
                return NO;
            case AVAudioEngineManualRenderingStatusCannotDoInCurrentContext:
                NSLog(@"somehow one round failed, lets retry\n");
                break;
        }
    };
    NSLog(@"...decoding done");
    [player stop];
    [engine stop];
    engine = nil;
    player = nil;
    NSLog(@"old engine freed");
    
    // Debug output to `/tmp/dumpedLazySample.raw`
    // [sample dumpToFile];

    return ret;
}

@end
