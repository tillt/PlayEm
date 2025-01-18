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
#import "AudioDevice.h"

//#define support_avaudioengine   YES
//#define support_avplayer        YES
#define support_audioqueueplayback  YES

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

typedef struct {
#ifdef support_audioqueueplayback
    AudioQueueRef               queue;
    AudioQueueBufferRef         buffers[kPlaybackBufferCount];
#endif
    int                         bufferIndex;
    unsigned long long          nextFrame;
    signed long long            latencyFrames;
} AudioOutputStream;

typedef struct {
    LazySample*                 sample;
    AudioOutputStream           stream;
    unsigned long long          nextFrame;
    signed long long            seekFrame;
    BOOL                        endOfStream;
    TapBlock                    tapBlock;
    dispatch_semaphore_t        semaphore;
} AudioContext;

@interface AudioController ()
{
    AudioContext            _context;
    BOOL                    _isPaused;
    float                   _tempoShift;
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

#ifdef support_audioqueueplayback
AVAudioFramePosition currentFrame(AudioQueueRef queue, AudioContext* context)
{
    if (queue == NULL) {
        return 0;
    }
    
    os_signpost_interval_begin(pointsOfInterest, POIGetCurrentFrame, "GetCurrentFrame");

 //   AudioQueueTimelineRef timeLine;
    //OSStatus res = AudioQueueCreateTimeline(queue, &timeLine);
    
//    if (res != noErr) {
//        return 0;
//    }
    
    AudioTimeStamp timeStamp;
    //Boolean discontinued;
    
    OSStatus res = AudioQueueGetCurrentTime(queue,
                                           NULL,
                                           &timeStamp,
                                           NULL);

    //AudioQueueDisposeTimeline(queue, timeLine);

    if (res) {
        os_signpost_interval_end(pointsOfInterest, POIGetCurrentFrame, "GetCurrentFrame", "failed");
        return 0;
    }
    if (timeStamp.mSampleTime < 0) {
        os_signpost_interval_end(pointsOfInterest, POIGetCurrentFrame, "GetCurrentFrame", "negative");
        return 0;
    }
//    assert(!discontinued);
//    if (discontinued) {
//        NSLog(@"discontinued queue -- needs reinitializing");
//        os_signpost_interval_end(pointsOfInterest, POIGetCurrentFrame, "GetCurrentFrame", "discontinued");
//        return context->nextFrame - context->stream.latencyFrames;
//    }
    os_signpost_interval_end(pointsOfInterest, POIGetCurrentFrame, "GetCurrentFrame", "done");

    return MIN(context->seekFrame + timeStamp.mSampleTime, context->sample.frames - 1);
}

NSTimeInterval currentTime(AudioQueueRef queue, AudioContext* context)
{
    return ((NSTimeInterval)currentFrame(queue, context) / context->sample.rate);
}
#endif

/// Callback for changes on the default output device setup.
OSStatus propertyCallbackDefaultDevice (AudioObjectID inObjectID,
                                        UInt32 inNumberAddresses,
                                        const AudioObjectPropertyAddress inAddresses[],
                                        void* inClientData)
{
    // We are only interested in the property kAudioQueueProperty_IsRunning
    if (inAddresses->mSelector != kAudioHardwarePropertyDefaultOutputDevice) {
        NSLog(@"Selector %d not of interest", inAddresses->mSelector);
        return 0;
    }
    assert(inClientData);
    AudioContext* context = (AudioContext*)inClientData;

    NSLog(@"new default output");

    UInt32 deviceId = [AudioDevice defaultOutputDevice];
    if (deviceId == 0) {
        return 0;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        NSString* name = [AudioDevice nameForDevice:deviceId];
        NSLog(@"audio output now using device %@", name);
        context->stream.latencyFrames = [AudioDevice latencyForDevice:deviceId
                                                                scope:kAudioDevicePropertyScopeOutput];
        NSLog(@"audio output latency %lld frames", context->stream.latencyFrames);
    });
    return 0;
}

/// Callback for changes on AudioQueue properties - used for monitoring the playback state.
void propertyCallbackIsRunning (void* user_data,
                                AudioQueueRef queue,
                                AudioQueuePropertyID property_id)
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
    unsigned long long fetched = [context->sample rawSampleFromFrameOffset:context->nextFrame
                                                                   frames:frames
                                                                     data:p];
    // Pad last frame with silence, if needed.
    if (fetched < frames) {
        memset(p + fetched * context->sample.channels, 0, (frames - fetched) * context->sample.frameSize);
    }
    if (fetched == 0) {
        NSLog(@"reached end of stream at %lld", context->nextFrame);
        context->endOfStream = YES;
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

- (void)setTempoShift:(float)tempoShift
{
#ifdef support_audioqueueplayback
    assert(_context.stream.queue != nil);
    AudioQueueSetParameter(_context.stream.queue, kAudioQueueParam_PlayRate, tempoShift);
#endif
}

- (float)tempoShift
{
    float tempoShift = 0.0;
#ifdef support_audioqueueplayback
    AudioQueueGetParameter(_context.stream.queue, kAudioQueueParam_PlayRate, &tempoShift);
#endif
    return tempoShift;
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

- (void)startTapping:(TapBlock _Nullable)tap
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

    // FIXME: This appears utterly magic - should happen explicitly somewhere else.
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
    NSAssert(_context.stream.queue != nil, @"queue shouldnt be empty");
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
    // Secure tapping state.
    TapBlock tap = _context.tapBlock;
    [self stopTapping];

    assert(newFrame < _context.sample.frames);
     AVAudioFramePosition oldFrame = self.currentFrame;
    _context.seekFrame += newFrame - oldFrame;
    _context.nextFrame = newFrame;
    
    // Restore tapping state.
    [self startTapping:tap];
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

    UInt32 deviceId = [AudioDevice defaultOutputDevice];
    if (deviceId == 0) {
        NSLog(@"couldnt get output device -- that is unexpected");
        return;
    }
    NSString* name = [AudioDevice nameForDevice:deviceId];
    _context.stream.latencyFrames = [AudioDevice latencyForDevice:deviceId scope:kAudioDevicePropertyScopeOutput];
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

#ifdef support_avaudioengine
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
    
    if (fetched == 0) {
        NSLog(@"reached end of stream at %lld", _context.nextFrame);
        return NO;
    }
    return YES;
}
#endif

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
    UInt32 value = 1;
    AudioQueueSetProperty(_context.stream.queue, kAudioQueueProperty_EnableTimePitch, &value, sizeof(value));
    value = kAudioQueueTimePitchAlgorithm_Spectral;
    AudioQueueSetProperty(_context.stream.queue, kAudioQueueProperty_TimePitchAlgorithm, &value, sizeof(value));
    AudioQueueSetParameter(_context.stream.queue, kAudioQueueParam_PlayRate, 1.0);

    uint32_t primed = 0;
    res = AudioQueuePrime(_context.stream.queue, 0, &primed);
//    assert((res == 0) && primed > 0);
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
        NSLog(@"decoder is done - we are back on the main thread - run the callback block with %d", done);
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
    NSLog(@"old engine freed - exiting decoder");
    // Debug output to `/tmp/dumpedLazySample.raw`
    // [sample dumpToFile];
    return ret;
}

@end
