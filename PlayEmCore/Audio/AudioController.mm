//
//  AudioController.m
//  PlayEm
//
//  Created by Till Toenshoff on 30.05.20.
//  Copyright © 2020 Till Toenshoff. All rights reserved.
//

#import "AudioController.h"

#import <AVFoundation/AVFoundation.h>
#import <AudioToolbox/AudioToolbox.h>

#import "AUPlaybackBackend.h"
#import "ActivityManager.h"
#import "AudioDevice.h"
#import "AQPlaybackBackend.h"
#import "LazySample.h"

static const BOOL kUseAUBackend = YES;

const unsigned int kPlaybackBufferFrames = 4096;
const unsigned int kPlaybackBufferCount = 2;
static const float kDecodingPollInterval = 0.3f;
static const float kEnoughSecondsDecoded = 5.0f;
static const size_t kDecoderBufferFrames = 16384;

NSString* const kAudioControllerChangedPlaybackStateNotification = @"AudioControllerChangedPlaybackStateNotification";
NSString* const kPlaybackStateStarted = @"started";
NSString* const kPlaybackStatePaused = @"paused";
NSString* const kPlaybackStatePlaying = @"playing";
NSString* const kPlaybackStateEnded = @"ended";
NSString* const kPlaybackFXStateChanged = @"fxStateChanged";

static OSStatus DefaultOutputDeviceChanged(AudioObjectID objectId, UInt32 numberAddresses, const AudioObjectPropertyAddress addresses[], void* clientData);

@interface AudioController () <AudioPlaybackBackendDelegate>

@property (nonatomic, strong) id<AudioPlaybackBackend> backend;
@property (nonatomic, strong, nullable) LazySample* sampleRef;
@property (nonatomic, strong, nullable) NSTimer* timer;
@property (nonatomic, strong, nullable) dispatch_block_t decodeOperation;
@property (nonatomic, copy, nullable) TapBlock tapBlock;
@property (nonatomic, assign) AVAudioFramePosition cachedLatency;
@property (nonatomic, assign) AudioObjectID cachedDeviceId;
@property (nonatomic, strong) NSArray<NSDictionary*>* availableEffects;
@property (nonatomic, assign) NSInteger currentEffectIndex;
@property (nonatomic, assign) AudioComponentDescription currentEffectDescription;

- (void)handleDefaultDeviceChange;

@end

static OSStatus DefaultOutputDeviceChanged(AudioObjectID objectId, UInt32 numberAddresses, const AudioObjectPropertyAddress addresses[], void* clientData)
{
    if (clientData == NULL) {
        return noErr;
    }
    AudioController* controller = (__bridge AudioController*) clientData;
    dispatch_async(dispatch_get_main_queue(), ^{
        [controller handleDefaultDeviceChange];
    });
    return noErr;
}

@implementation AudioController

- (instancetype)init
{
    self = [super init];
    if (self) {
        if (kUseAUBackend) {
            _backend = [[AUPlaybackBackend alloc] init];
        } else {
            _backend = [[AQPlaybackBackend alloc] init];
        }
        _backend.delegate = self;
        _outputVolume = 1.0;
        _tempoShift = 1.0f;
        _cachedLatency = -1;
        _cachedDeviceId = [AudioDevice defaultOutputDevice];
        _availableEffects = @[];
        _currentEffectIndex = -1;
        _currentEffectDescription = (AudioComponentDescription){0};
        AudioObjectPropertyAddress addr = {kAudioHardwarePropertyDefaultOutputDevice, kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain};
        AudioObjectAddPropertyListener(kAudioObjectSystemObject, &addr, DefaultOutputDeviceChanged, (__bridge void*) self);
    }
    return self;
}

- (void)dealloc
{
    AudioObjectPropertyAddress addr = {kAudioHardwarePropertyDefaultOutputDevice, kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain};
    AudioObjectRemovePropertyListener(kAudioObjectSystemObject, &addr, DefaultOutputDeviceChanged, (__bridge void*) self);
}

#pragma mark - Playback controls

- (void)togglePause
{
    if (self.playing) {
        [self pause];
    } else {
        [self play];
    }
}

- (void)play
{
    [self.backend play];
}

- (void)pause
{
    [self.backend pause];
}

- (void)playSample:(LazySample*)sample frame:(unsigned long long)frame paused:(BOOL)paused
{
    self.sampleRef = sample;
    [self.backend prepareWithSample:sample];
    [self.backend seekToFrame:frame];
    self.backend.volume = self.outputVolume;
    self.backend.tempo = self.tempoShift;
    if (self.tapBlock && [self.backend respondsToSelector:@selector(setTapBlock:)]) {
        [(id) self.backend setTapBlock:self.tapBlock];
    }
    if (!paused) {
        [self play];
    }
}

- (void)startTapping:(TapBlock _Nullable)tap
{
    self.tapBlock = tap;
    if ([self.backend respondsToSelector:@selector(setTapBlock:)]) {
        [(id) self.backend setTapBlock:tap];
    }
}

- (void)stopTapping
{
    self.tapBlock = nil;
    if ([self.backend respondsToSelector:@selector(setTapBlock:)]) {
        [(id) self.backend setTapBlock:nil];
    }
}

#pragma mark - Positioning

- (NSTimeInterval)currentTime
{
    return [self.backend currentTime];
}

- (void)setCurrentTime:(NSTimeInterval)time
{
    unsigned long long frame = (unsigned long long) (time * self.sampleFormat.rate);
    [self.backend seekToFrame:frame];
}

- (AVAudioFramePosition)currentFrame
{
    return (AVAudioFramePosition)[self.backend currentFrame];
}

- (void)setCurrentFrame:(AVAudioFramePosition)newFrame
{
    [self.backend seekToFrame:(unsigned long long) newFrame];
}

- (AVAudioFramePosition)frameCountDeltaWithTimeDelta:(NSTimeInterval)timestamp
{
    return ceil(self.sampleFormat.rate * timestamp);
}

- (NSTimeInterval)timeDeltaWithFrameCountDelta:(AVAudioFramePosition)timestamp
{
    return ceil(timestamp / self.sampleFormat.rate);
}

#pragma mark - Properties

- (SampleFormat)sampleFormat
{
    if (self.sampleRef) {
        return self.sampleRef.sampleFormat;
    }
    SampleFormat empty = {0};
    return empty;
}

- (NSTimeInterval)expectedDuration
{
    return self.sampleRef ? self.sampleRef.duration : 0.0;
}

- (int64_t)currentOffset
{
    return 0;
}

- (BOOL)playing
{
    return self.backend.playing;
}

- (BOOL)paused
{
    return self.backend.paused;
}

- (void)handleDefaultDeviceChange
{
    AudioObjectID newDevice = [AudioDevice defaultOutputDevice];
    if (newDevice == 0 || newDevice == self.cachedDeviceId) {
        return;
    }
    self.cachedDeviceId = newDevice;
    BOOL wasPlaying = self.playing;
    AVAudioFramePosition currentFrame = [self.backend currentFrame];
    [self.backend stop];
    if (self.sampleRef) {
        [self.backend prepareWithSample:self.sampleRef];
        [self.backend seekToFrame:(unsigned long long) currentFrame];
        self.backend.volume = (float) self.outputVolume;
        self.backend.tempo = self.tempoShift;
        if (self.tapBlock && [self.backend respondsToSelector:@selector(setTapBlock:)]) {
            [(id) self.backend setTapBlock:self.tapBlock];
        }
        if (wasPlaying) {
            [self.backend play];
        }
    }
}

- (void)setOutputVolume:(double)outputVolume
{
    _outputVolume = outputVolume;
    self.backend.volume = (float) outputVolume;
}

- (void)setTempoShift:(float)tempoShift
{
    _tempoShift = tempoShift;
    self.backend.tempo = tempoShift;
}

- (BOOL)selectEffectAtIndex:(NSInteger)index
{
    AudioComponentDescription desc = {0};
    if (index >= 0 && index < (NSInteger) self.availableEffects.count) {
        NSDictionary* entry = self.availableEffects[(NSUInteger) index];
        NSValue* packed = entry[@"component"];
        if (packed != nil && strcmp([packed objCType], @encode(AudioComponentDescription)) == 0) {
            [packed getValue:&desc];
        }
    }
    return [self selectEffectWithDescription:desc indexHint:index];
}

- (void)refreshAvailableEffectsAsync:(void (^)(NSArray<NSDictionary*>* effects))completion
{
    __weak AudioController* weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSArray<NSDictionary*>* effects = @[];
        if ([weakSelf.backend respondsToSelector:@selector(availableEffects)]) {
            effects = [(_Nullable id) weakSelf.backend availableEffects] ?: @[];
        }
        weakSelf.availableEffects = effects;
        if (completion) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(effects);
            });
        }
    });
}

- (BOOL)selectEffectWithDescription:(AudioComponentDescription)description indexHint:(NSInteger)indexHint
{
    if (![self.backend respondsToSelector:@selector(setEffectWithDescription:)]) {
        return NO;
    }
    // Avoid redundant reconfiguration if this effect is already active.
    AudioComponentDescription none = {0};
    if (indexHint == _currentEffectIndex) {
        if (memcmp(&description, &_currentEffectDescription, sizeof(AudioComponentDescription)) == 0) {
            _currentEffectDescription = description;
            _currentEffectIndex = indexHint;
            return YES;
        }
        if (memcmp(&description, &none, sizeof(AudioComponentDescription)) == 0 &&
            memcmp(&_currentEffectDescription, &none, sizeof(AudioComponentDescription)) == 0) {
            _currentEffectDescription = description;
            _currentEffectIndex = indexHint;
            return YES;
        }
    }

    BOOL wasPlaying = self.playing;
    NSLog(@"AudioController: selectEffect type=0x%08x subtype=0x%08x manuf=0x%08x hint=%ld", (unsigned int) description.componentType,
          (unsigned int) description.componentSubType, (unsigned int) description.componentManufacturer, (long) indexHint);
    BOOL ok = [(id) self.backend setEffectWithDescription:description];
    if (ok) {
        if (indexHint >= 0 && indexHint < (NSInteger) self.availableEffects.count) {
            _currentEffectIndex = indexHint;
        } else {
            _currentEffectIndex = -1;
        }
        _currentEffectDescription = description;
        self.backend.volume = (float) self.outputVolume;
        self.backend.tempo = self.tempoShift;
        if (self.tapBlock && [self.backend respondsToSelector:@selector(setTapBlock:)]) {
            [(id) self.backend setTapBlock:self.tapBlock];
        }
        if (wasPlaying) {
            [self.backend play];
        }
        BOOL enabled = (_currentEffectIndex >= 0);
        [[NSNotificationCenter defaultCenter] postNotificationName:kPlaybackFXStateChanged
                                                            object:self
                                                          userInfo:@{ @"enabled" : @(enabled), @"index" : @(_currentEffectIndex) }];
    } else {
        NSLog(@"AudioController: selectEffect failed");
    }
    return ok;
}

- (NSDictionary<NSNumber*, NSDictionary*>*)effectParameterInfo
{
    if (![self.backend respondsToSelector:@selector(effectParameterInfo)]) {
        return @{};
    }
    return [(_Nullable id) self.backend effectParameterInfo] ?: @{};
}

- (BOOL)setEffectParameter:(AudioUnitParameterID)parameter value:(AudioUnitParameterValue)value
{
    if (![self.backend respondsToSelector:@selector(setEffectParameter:value:)]) {
        return NO;
    }
    return [(_Nullable id) self.backend setEffectParameter:parameter value:value];
}

- (BOOL)setEffectEnabled:(BOOL)enabled
{
    BOOL ok = NO;
    if ([self.backend respondsToSelector:@selector(setEffectEnabled:)]) {
        ok = [(_Nullable id) self.backend setEffectEnabled:enabled];
    }
    if (!ok && self.currentEffectIndex >= 0 && self.currentEffectIndex < (NSInteger) self.availableEffects.count) {
        // Fall back to reselecting the current effect to force it audible.
        ok = [self selectEffectAtIndex:self.currentEffectIndex];
    }
    [[NSNotificationCenter defaultCenter] postNotificationName:kPlaybackFXStateChanged
                                                        object:self
                                                      userInfo:@{ @"enabled" : @(enabled), @"index" : @(self.currentEffectIndex) }];
    return ok;
}

- (LazySample*)sample
{
    return self.sampleRef;
}

- (AVAudioFramePosition)totalLatency
{
    UInt32 deviceId = [AudioDevice defaultOutputDevice];
    if (deviceId == 0) {
        return 0;
    }
    if (deviceId != self.cachedDeviceId || self.cachedLatency < 0) {
        self.cachedLatency = [AudioDevice latencyForDevice:deviceId scope:kAudioDevicePropertyScopeOutput];
        self.cachedDeviceId = deviceId;
    }
    return self.cachedLatency;
}

#pragma mark - Decoding

- (void)decodeAbortWithCallback:(void (^)(void))callback
{
    if (self.decodeOperation != nil) {
        dispatch_block_cancel(self.decodeOperation);
        if (callback != nil) {
            dispatch_block_notify(self.decodeOperation, dispatch_get_main_queue(), ^{
                callback();
            });
        }
    } else if (callback != nil) {
        callback();
    }
}

- (void)decodeAsyncWithSample:(LazySample*)sample callback:(void (^)(BOOL))callback
{
    __weak AudioController* weakSelf = self;

    __block BOOL done = NO;
    __weak __block dispatch_block_t weakBlock;

    ActivityToken* decoderToken = [[ActivityManager shared] beginActivityWithTitle:@"Decoding Sample" detail:@"" cancellable:NO cancelHandler:nil];

    dispatch_block_t block = dispatch_block_create(DISPATCH_BLOCK_NO_QOS_CLASS, ^{
        done = [weakSelf decode:sample
                          token:decoderToken
                     cancelTest:^BOOL {
                         return dispatch_block_testcancel(weakBlock) != 0 ? YES : NO;
                     }];
    });

    weakBlock = block;
    self.decodeOperation = block;

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), self.decodeOperation);

    dispatch_block_notify(self.decodeOperation, dispatch_get_main_queue(), ^{
        [[ActivityManager shared] completeActivity:decoderToken];
        callback(done);
    });
}

- (BOOL)decode:(LazySample*)encodedSample token:(ActivityToken*)token cancelTest:(BOOL (^)(void))cancelTest
{
    [[ActivityManager shared] updateActivity:token progress:0.0 detail:@"initializing engine"];

    AVAudioEngine* engine = [[AVAudioEngine alloc] init];

    NSError* error = nil;
    [engine enableManualRenderingMode:AVAudioEngineManualRenderingModeOffline
                               format:encodedSample.source.processingFormat
                    maximumFrameCount:kDecoderBufferFrames
                                error:&error];

    AVAudioPlayerNode* player = [[AVAudioPlayerNode alloc] init];
    [engine attachNode:player];
    [engine connect:player to:engine.outputNode format:encodedSample.source.processingFormat];

    if (![engine startAndReturnError:&error]) {
        [encodedSample markDecodingComplete];
        return NO;
    }

    [player scheduleFile:encodedSample.source atTime:0 completionHandler:nil];

    AVAudioPCMBuffer* buffer = [[AVAudioPCMBuffer alloc] initWithPCMFormat:engine.manualRenderingFormat frameCapacity:kDecoderBufferFrames];

    [player play];

    unsigned long long pageIndex = 0;
    BOOL ret = YES;

    while (engine.manualRenderingSampleTime < encodedSample.source.length) {
        double progress = (double) engine.manualRenderingSampleTime / encodedSample.source.length;
        [[ActivityManager shared] updateActivity:token progress:progress detail:@"decoding compressed audio data"];

        if (cancelTest()) {
            ret = NO;
            break;
        }

        unsigned long long frameLeftCount = encodedSample.source.length - engine.manualRenderingSampleTime;
        AVAudioFrameCount framesToRender = (AVAudioFrameCount) MIN(frameLeftCount, (long long) buffer.frameCapacity);
        AVAudioEngineManualRenderingStatus status = [engine renderOffline:framesToRender toBuffer:buffer error:&error];

        switch (status) {
        case AVAudioEngineManualRenderingStatusSuccess: {
            unsigned long long rawDataLengthPerChannel = buffer.frameLength * sizeof(float);
            NSMutableArray<NSData*>* channels = [NSMutableArray array];

            for (int channelIndex = 0; channelIndex < encodedSample.sampleFormat.channels; channelIndex++) {
                NSData* channel = [NSData dataWithBytes:buffer.floatChannelData[channelIndex] length:rawDataLengthPerChannel];
                [channels addObject:channel];
            }
            [encodedSample addLazyPageIndex:pageIndex channels:channels];
            pageIndex++;
        }
        case AVAudioEngineManualRenderingStatusInsufficientDataFromInputNode:
            break;
        case AVAudioEngineManualRenderingStatusError:
            [encodedSample markDecodingComplete];
            return NO;
        case AVAudioEngineManualRenderingStatusCannotDoInCurrentContext:
            break;
        }
    }
    [[ActivityManager shared] updateActivity:token progress:1.0 detail:@"decoding audio done"];
    [player stop];
    [engine stop];
    engine = nil;
    player = nil;
    [encodedSample markDecodingComplete];
    return ret;
}

#pragma mark - Backend delegate

- (void)playbackBackendDidStart:(AudioPlaybackBackend*)backend
{
    [[NSNotificationCenter defaultCenter] postNotificationName:kAudioControllerChangedPlaybackStateNotification object:kPlaybackStateStarted];
    [[NSNotificationCenter defaultCenter] postNotificationName:kAudioControllerChangedPlaybackStateNotification object:kPlaybackStatePlaying];
}

- (void)playbackBackendDidPause:(AudioPlaybackBackend*)backend
{
    [[NSNotificationCenter defaultCenter] postNotificationName:kAudioControllerChangedPlaybackStateNotification object:kPlaybackStatePaused];
}

- (void)playbackBackendDidEnd:(AudioPlaybackBackend*)backend
{
    [[NSNotificationCenter defaultCenter] postNotificationName:kAudioControllerChangedPlaybackStateNotification object:kPlaybackStateEnded];
}

@end
