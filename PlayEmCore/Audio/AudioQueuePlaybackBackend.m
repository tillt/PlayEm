//
//  AudioQueuePlaybackBackend.m
//  PlayEm
//
//  Created by Till Toenshoff on 01/05/26.
//  Copyright © 2026 Till Toenshoff. All rights reserved.
//

#import "AudioQueuePlaybackBackend.h"

#import <AudioToolbox/AudioToolbox.h>

#import "AudioDevice.h"
#import "LazySample.h"

static const unsigned int kPlaybackBufferFrames = 4096;
static const unsigned int kPlaybackBufferCount = 2;

typedef struct {
    AudioQueueRef queue;
    AudioQueueBufferRef buffers[kPlaybackBufferCount];
    BOOL endOfStream;
    unsigned long long nextFrame;
    unsigned long long baseFrame;
    signed long long seekFrame;
    signed long long latencyFrames;
} AQStream;

@interface AudioQueuePlaybackBackend () {
    AQStream _stream;
    BOOL _paused;
    float _volume;
    float _tempo;
    dispatch_semaphore_t _bufferSemaphore;
}
@property (nonatomic, strong) LazySample* sample;
@property (nonatomic) AudioQueueProcessingTapRef tapRef;
@end

static void AQPropertyCallback(void* userData, AudioQueueRef queue, AudioQueuePropertyID propertyID);
static void AQBufferCallback(void* userData, AudioQueueRef queue, AudioQueueBufferRef buffer);
static void AQTapCallback(void* userData, AudioQueueProcessingTapRef tapRef, UInt32 inNumberFrames, AudioTimeStamp* ioTimeStamp,
                          AudioQueueProcessingTapFlags* outFlags, UInt32* outNumberFrames, AudioBufferList* ioData);

unsigned long long AQPlaybackAdjustedFrame(unsigned long long baseFrame, double sampleTime, signed long long latencyFrames, unsigned long long totalFrames)
{
    signed long long adjusted = (signed long long) baseFrame + (signed long long) sampleTime - latencyFrames;
    if (adjusted < 0) {
        adjusted = 0;
    }
    unsigned long long capped = MIN((unsigned long long) adjusted, totalFrames > 0 ? totalFrames - 1 : 0);
    return capped;
}

@implementation AudioQueuePlaybackBackend

@synthesize playing = _playing;
@synthesize paused = _paused;
@synthesize volume = _volume;
@synthesize tempo = _tempo;
@synthesize delegate = _delegate;

- (instancetype)init
{
    self = [super init];
    if (self) {
        memset(&_stream, 0, sizeof(_stream));
        _bufferSemaphore = dispatch_semaphore_create(kPlaybackBufferCount);
        _volume = 1.0f;
        _tempo = 1.0f;
    }
    return self;
}

- (void)dealloc
{
    [self stop];
    if (_stream.queue) {
        AudioQueueDispose(_stream.queue, true);
        _stream.queue = NULL;
    }
    if (_tapRef != NULL) {
        AudioQueueProcessingTapDispose(_tapRef);
        _tapRef = NULL;
    }
}

- (void)prepareWithSample:(LazySample*)sample
{
    [self stop];
    if (_stream.queue != NULL) {
        AudioQueueStop(_stream.queue, TRUE);
        for (int i = 0; i < kPlaybackBufferCount; i++) {
            if (_stream.buffers[i] != NULL) {
                AudioQueueFreeBuffer(_stream.queue, _stream.buffers[i]);
                _stream.buffers[i] = NULL;
            }
        }
        if (_tapRef != NULL) {
            AudioQueueProcessingTapDispose(_tapRef);
            _tapRef = NULL;
        }
        AudioQueueDispose(_stream.queue, true);
        _stream.queue = NULL;
    }
    self.sample = sample;
    _stream.nextFrame = 0;
    _stream.baseFrame = 0;
    _stream.seekFrame = 0;
    _stream.endOfStream = NO;
    // Ensure a tap placeholder is in place before playback; actual block may be
    // nil (no-op).
    if (_tapRef != NULL) {
        AudioQueueProcessingTapDispose(_tapRef);
        _tapRef = NULL;
    }
    [self setupQueueIfNeeded];
}

- (void)setupQueueIfNeeded
{
    if (_stream.queue != NULL || self.sample == nil) {
        return;
    }
    AudioStreamBasicDescription fmt = {0};
    fmt.mSampleRate = (Float64) self.sample.sampleFormat.rate;
    fmt.mFormatID = kAudioFormatLinearPCM;
    fmt.mFormatFlags = kLinearPCMFormatFlagIsFloat | kAudioFormatFlagIsPacked;
    fmt.mFramesPerPacket = 1;
    fmt.mChannelsPerFrame = (uint32_t) self.sample.sampleFormat.channels;
    fmt.mBytesPerFrame = (unsigned int) self.sample.frameSize;
    fmt.mBytesPerPacket = (unsigned int) self.sample.frameSize;
    fmt.mBitsPerChannel = 32;

    OSStatus res = AudioQueueNewOutput(&fmt, AQBufferCallback, (__bridge void*) self, NULL, NULL, 0, &_stream.queue);
    assert((res == 0) && _stream.queue);

    // Cache latency for sync calculations.
    AudioObjectID deviceId = [AudioDevice defaultOutputDevice];
    _stream.latencyFrames = [AudioDevice latencyForDevice:deviceId scope:kAudioDevicePropertyScopeOutput];
    static dispatch_once_t logOnce;
    dispatch_once(&logOnce, ^{
        NSLog(@"Output latency frames: %lld", _stream.latencyFrames);
    });

    // Create a processing tap upfront (no-op until tapBlock is set).
    if (_tapRef == NULL) {
        UInt32 maxFrames = 0;
        AudioStreamBasicDescription procFormat = fmt;
        OSStatus tapRes = AudioQueueProcessingTapNew(_stream.queue, AQTapCallback, (__bridge void*) self, kAudioQueueProcessingTap_PostEffects, &maxFrames,
                                                     &procFormat, &_tapRef);
        if (tapRes != noErr) {
            NSLog(@"AudioQueueProcessingTapNew failed with status %d", (int) tapRes);
            _tapRef = NULL;
        }
    }

    // Listen for isRunning changes.
    res = AudioQueueAddPropertyListener(_stream.queue, kAudioQueueProperty_IsRunning, AQPropertyCallback, (__bridge void*) self);
    assert(res == 0);

    UInt32 value = 1;
    value = 1;
    AudioQueueSetProperty(_stream.queue, kAudioQueueProperty_EnableTimePitch, &value, sizeof(value));
    value = kAudioQueueTimePitchAlgorithm_Spectral;
    AudioQueueSetProperty(_stream.queue, kAudioQueueProperty_TimePitchAlgorithm, &value, sizeof(value));
    AudioQueueSetParameter(_stream.queue, kAudioQueueParam_Volume, _volume);
    AudioQueueSetParameter(_stream.queue, kAudioQueueParam_PlayRate, _tempo);

    // Prime buffers.
    for (int i = 0; i < kPlaybackBufferCount; i++) {
        UInt32 size = (UInt32) self.sample.frameSize * kPlaybackBufferFrames;
        res = AudioQueueAllocateBuffer(_stream.queue, size, &_stream.buffers[i]);
        assert((res == 0) && _stream.buffers[i]);
        _stream.buffers[i]->mAudioDataByteSize = size;
        AQBufferCallback((__bridge void*) self, _stream.queue, _stream.buffers[i]);
    }
    uint32_t primed = 0;
    res = AudioQueuePrime(_stream.queue, 0, &primed);
    if (res != 0 || primed == 0) {
        NSLog(@"AudioQueuePrime returned %d primed=%u", (int) res, primed);
    }
}

- (void)play
{
    if (_playing || _stream.queue == NULL) {
        return;
    }
    _stream.baseFrame = _stream.seekFrame;
    if (_stream.endOfStream) {
        _stream.endOfStream = NO;
        _stream.nextFrame = 0;
        _stream.seekFrame = 0;
        for (int i = 0; i < kPlaybackBufferCount; i++) {
            AQBufferCallback((__bridge void*) self, _stream.queue, _stream.buffers[i]);
        }
    }
    OSStatus res = AudioQueueStart(_stream.queue, NULL);
    if (res == 0) {
        _playing = YES;
        _paused = NO;
        [self.delegate playbackBackendDidStart:self];
    }
}

- (void)pause
{
    if (!_playing || _stream.queue == NULL) {
        return;
    }
    AudioQueuePause(_stream.queue);
    _paused = YES;
    _playing = NO;
    [self.delegate playbackBackendDidPause:self];
}

- (void)stop
{
    if (_stream.queue) {
        AudioQueueStop(_stream.queue, TRUE);
    }
    _playing = NO;
    _paused = NO;
}

- (void)seekToFrame:(unsigned long long)frame
{
    BOOL wasPlaying = _playing;
    if (_stream.queue != NULL) {
        AudioQueueStop(_stream.queue, TRUE);
        _stream.endOfStream = NO;
    }
    _stream.seekFrame = frame;
    _stream.nextFrame = frame;
    _stream.baseFrame = frame;
    // Refill buffers from new position.
    for (int i = 0; i < kPlaybackBufferCount && _stream.queue != NULL; i++) {
        AQBufferCallback((__bridge void*) self, _stream.queue, _stream.buffers[i]);
    }
    if (wasPlaying && _stream.queue != NULL) {
        AudioQueueStart(_stream.queue, NULL);
        _playing = YES;
        _paused = NO;
    }
}

- (unsigned long long)currentFrame
{
    if (_stream.queue == NULL) {
        return 0;
    }
    AudioTimeStamp ts;
    OSStatus res = AudioQueueGetCurrentTime(_stream.queue, NULL, &ts, NULL);
    if (res != 0 || ts.mSampleTime < 0) {
        return _stream.nextFrame;
    }
    return AQPlaybackAdjustedFrame(_stream.baseFrame, ts.mSampleTime, _stream.latencyFrames, self.sample.frames);
}

- (NSTimeInterval)currentTime
{
    return ((NSTimeInterval)[self currentFrame] / self.sample.sampleFormat.rate);
}

- (void)setVolume:(float)volume
{
    _volume = volume;
    if (_stream.queue) {
        AudioQueueSetParameter(_stream.queue, kAudioQueueParam_Volume, volume);
    }
}

- (float)volume
{
    if (_stream.queue == nil) {
        return _volume;
    }
    AudioQueueParameterValue v = (AudioQueueParameterValue) _volume;
    AudioQueueGetParameter(_stream.queue, kAudioQueueParam_Volume, &v);
    _volume = v;
    return v;
}

- (void)setTempo:(float)tempo
{
    _tempo = tempo;
    if (_stream.queue != NULL) {
        UInt32 enable = 1;
        AudioQueueSetProperty(_stream.queue, kAudioQueueProperty_EnableTimePitch, &enable, sizeof(enable));
        UInt32 algo = kAudioQueueTimePitchAlgorithm_Spectral;
        AudioQueueSetProperty(_stream.queue, kAudioQueueProperty_TimePitchAlgorithm, &algo, sizeof(algo));
        AudioQueueSetParameter(_stream.queue, kAudioQueueParam_PlayRate, _tempo);
    }
}

- (float)tempo
{
    if (_stream.queue == nil) {
        return _tempo;
    }
    AudioQueueParameterValue t = _tempo;
    AudioQueueGetParameter(_stream.queue, kAudioQueueParam_PlayRate, &t);
    _tempo = t;
    return t;
}

- (void)setTapBlock:(void (^)(unsigned long long, float*, unsigned int))tapBlock
{
    _tapBlock = [tapBlock copy];
}

#pragma mark - Callbacks

static void AQBufferCallback(void* userData, AudioQueueRef queue, AudioQueueBufferRef buffer)
{
    AudioQueuePlaybackBackend* backend = (__bridge AudioQueuePlaybackBackend*) userData;
    if (!backend.sample) {
        memset(buffer->mAudioData, 0, buffer->mAudioDataByteSize);
        buffer->mAudioDataByteSize = 0;
        return;
    }
    // Always fill buffers for playback; tap reads source audio independently.
    float* p = (float*) buffer->mAudioData;
    unsigned int frames = buffer->mAudioDataByteSize / backend.sample.frameSize;
    unsigned long long fetched = [backend.sample rawSampleFromFrameOffset:backend->_stream.nextFrame frames:frames data:p];
    if (fetched < frames) {
        memset(p + fetched * backend.sample.sampleFormat.channels, 0, (frames - fetched) * backend.sample.frameSize);
    }
    if (fetched == 0) {
        backend->_stream.endOfStream = YES;
        AudioQueueFlush(queue);
        AudioQueueStop(queue, FALSE);
    } else {
        static BOOL loggedOnce = NO;
        if (!loggedOnce && fetched > 0) {
            double acc = 0.0;
            UInt32 count = MIN(fetched, (UInt32) 32);
            for (UInt32 i = 0; i < count; i++) {
                float v = p[i];
                acc += (double) v * (double) v;
            }
            double rms = sqrt(acc / (double) count);
            NSLog(@"[AQBuf] frames=%u rms(first32)=%.6f", (unsigned int) fetched, rms);
            loggedOnce = YES;
        }
        backend->_stream.nextFrame += fetched;
        AudioQueueEnqueueBuffer(queue, buffer, 0, NULL);
    }
}

static void AQPropertyCallback(void* userData, AudioQueueRef queue, AudioQueuePropertyID propertyID)
{
    if (propertyID != kAudioQueueProperty_IsRunning) {
        return;
    }
    AudioQueuePlaybackBackend* backend = (__bridge AudioQueuePlaybackBackend*) userData;
    UInt32 isRunning = FALSE;
    UInt32 size = sizeof(isRunning);
    AudioQueueGetProperty(queue, kAudioQueueProperty_IsRunning, &isRunning, &size);
    if (!isRunning && backend->_stream.endOfStream) {
        [backend.delegate playbackBackendDidEnd:backend];
    }
}

static void AQTapCallback(void* userData, AudioQueueProcessingTapRef tapRef, UInt32 inNumberFrames, AudioTimeStamp* ioTimeStamp,
                          AudioQueueProcessingTapFlags* outFlags, UInt32* outNumberFrames, AudioBufferList* ioData)
{
    AudioQueuePlaybackBackend* backend = (__bridge AudioQueuePlaybackBackend*) userData;
    if (backend == nil || backend.sample == nil) {
        *outNumberFrames = 0;
        return;
    }
    OSStatus res = AudioQueueProcessingTapGetSourceAudio(tapRef, inNumberFrames, ioTimeStamp, outFlags, outNumberFrames, ioData);
    if (res != noErr || *outNumberFrames == 0) {
        if (res != noErr) {
            NSLog(@"AudioQueueProcessingTapGetSourceAudio failed with status %d", (int) res);
        }
        return;
    }

    if (backend.tapBlock == nil) {
        return;
    }
    float* data = NULL;
    static NSMutableData* interleaveBuf = nil;
    if (ioData->mNumberBuffers == backend.sample.sampleFormat.channels && backend.sample.sampleFormat.channels > 1) {
        // Deinterleaved input; interleave into a scratch buffer.
        UInt32 frames = *outNumberFrames;
        UInt32 channels = (UInt32) backend.sample.sampleFormat.channels;
        UInt32 total = frames * channels;
        if (interleaveBuf == nil || interleaveBuf.length < total * sizeof(float)) {
            interleaveBuf = [NSMutableData dataWithLength:total * sizeof(float)];
        }
        float* dst = (float*) interleaveBuf.mutableBytes;
        for (UInt32 ch = 0; ch < channels; ch++) {
            const float* src = (const float*) ioData->mBuffers[ch].mData;
            for (UInt32 f = 0; f < frames; f++) {
                dst[f * channels + ch] = src ? src[f] : 0.0f;
            }
        }
        data = dst;
    } else {
        data = (ioData->mNumberBuffers > 0) ? (float*) ioData->mBuffers[0].mData : NULL;
    }
    unsigned long long framePos = (ioTimeStamp && ioTimeStamp->mSampleTime >= 0) ? (unsigned long long) (ioTimeStamp->mSampleTime + backend->_stream.seekFrame)
                                                                                 : backend->_stream.nextFrame;
    backend.tapBlock(framePos, data, *outNumberFrames);
}

@end
