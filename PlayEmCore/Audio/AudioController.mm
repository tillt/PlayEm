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
#import <math.h>

#import "AUPlaybackBackend.h"
#import "ActivityManager.h"
#import "AudioDevice.h"
#import "AQPlaybackBackend.h"
#import "LazySample.h"

static const BOOL kUseAUBackend = YES;

const unsigned int kPlaybackBufferFrames = 4096;
const unsigned int kPlaybackBufferCount = 2;
static const size_t kDecoderBufferFrames = 16384;
static const float kTempoBypassEpsilon = 0.01f;

NSString* const kAudioControllerChangedPlaybackStateNotification = @"AudioControllerChangedPlaybackStateNotification";
NSString* const kPlaybackStateStarted = @"started";
NSString* const kPlaybackStatePaused = @"paused";
NSString* const kPlaybackStatePlaying = @"playing";
NSString* const kPlaybackStateEnded = @"ended";
NSString* const kPlaybackFXStateChanged = @"fxStateChanged";
NSString* const kPlaybackGraphChanged = @"graphChanged";
NSString* const kGraphChangeReasonKey = @"reason";
NSString* const kGraphChangeEffectEnabledKey = @"effectEnabled";
NSString* const kGraphChangeEffectIndexKey = @"effectIndex";
NSString* const kGraphChangeTempoKey = @"tempo";
NSString* const kGraphChangeDeviceRateKey = @"deviceRate";
NSString* const kGraphChangeDeviceIdKey = @"deviceId";

static OSStatus DefaultOutputDeviceChanged(AudioObjectID objectId, UInt32 numberAddresses, const AudioObjectPropertyAddress addresses[], void* clientData);

@interface AudioController () <AudioPlaybackBackendDelegate>

@property (nonatomic, strong) id<AudioPlaybackBackend> backend;
@property (nonatomic, strong, nullable) LazySample* sampleRef;
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
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:kPlaybackGraphChanged
                                                            object:self
                                                          userInfo:@{kGraphChangeReasonKey : @"sample",
                                                                     @"sample" : sample ?: [NSNull null]}];
    });
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
    unsigned long long frame = (unsigned long long) (time * self.sample.renderedSampleRate);
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
    return ceil(self.sample.renderedSampleRate * timestamp);
}

- (NSTimeInterval)timeDeltaWithFrameCountDelta:(AVAudioFramePosition)timestamp
{
    return ceil(timestamp / self.sample.renderedSampleRate);
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
    Float64 deviceRate = [AudioDevice sampleRateForDevice:newDevice];
    [[NSNotificationCenter defaultCenter] postNotificationName:kPlaybackGraphChanged
                                                        object:self
                                                      userInfo:@{kGraphChangeReasonKey : @"device",
                                                                 kGraphChangeDeviceIdKey : @(newDevice),
                                                                 kGraphChangeDeviceRateKey : @(deviceRate)}];

    BOOL wasPlaying = self.playing;
    AVAudioFramePosition currentFrame = [self.backend currentFrame];
    double currentRate = self.sampleRef ? self.sampleRef.sampleFormat.rate : 0.0;
    NSTimeInterval currentTime = (currentRate > 0 ? currentFrame / currentRate : 0.0);
    [self.backend stop];
    if (!self.sampleRef) {
        return;
    }

    // If the rendered sample rate no longer matches the device, re-decode at the new device rate.
    if (deviceRate > 0 && fabs(deviceRate - self.sampleRef.sampleFormat.rate) > 1.0) {
        NSURL* url = self.sampleRef.source.url;
        NSError* err = nil;
        LazySample* freshSample = [[LazySample alloc] initWithPath:url.path error:&err];
        if (freshSample == nil || err != nil) {
            NSLog(@"AudioController: failed to reload sample at %@ err=%@", url, err);
            return;
        }
        __weak typeof(self) weakSelf = self;
        [self decodeAsyncWithSample:freshSample notifyEarlyAtFrame:0 callback:^(BOOL success, BOOL reachedEarlyFrame) {
            typeof(self) strongSelf = weakSelf;
            if (!strongSelf || !success) {
                return;
            }
            strongSelf.sampleRef = freshSample;
            unsigned long long newFrame = (unsigned long long) llrint(currentTime * freshSample.sampleFormat.rate);
            [strongSelf.backend prepareWithSample:freshSample];
            [strongSelf.backend seekToFrame:newFrame];
            strongSelf.backend.volume = (float) strongSelf.outputVolume;
            strongSelf.backend.tempo = strongSelf.tempoShift;
            if (strongSelf.tapBlock && [strongSelf.backend respondsToSelector:@selector(setTapBlock:)]) {
                [(id) strongSelf.backend setTapBlock:strongSelf.tapBlock];
            }
            if (wasPlaying) {
                [strongSelf.backend play];
            }
        }];
    } else {
        // No rate change; just rebuild the graph on the new device.
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
    [[NSNotificationCenter defaultCenter] postNotificationName:kPlaybackGraphChanged
                                                        object:self
                                                      userInfo:@{kGraphChangeReasonKey : @"tempo",
                                                                 kGraphChangeTempoKey : @(tempoShift)}];
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
        [[NSNotificationCenter defaultCenter] postNotificationName:kPlaybackGraphChanged
                                                            object:self
                                                          userInfo:@{kGraphChangeReasonKey : @"effect",
                                                                     kGraphChangeEffectEnabledKey : @(enabled),
                                                                     kGraphChangeEffectIndexKey : @(_currentEffectIndex)}];
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

- (BOOL)applyEffectEnabled:(BOOL)enabled
{
    BOOL ok = NO;
    if ([self.backend respondsToSelector:@selector(applyEffectEnabled:)]) {
        ok = [(_Nullable id) self.backend applyEffectEnabled:enabled];
    }
    if (!ok && self.currentEffectIndex >= 0 && self.currentEffectIndex < (NSInteger) self.availableEffects.count) {
        // Fall back to reselecting the current effect to force it audible.
        ok = [self selectEffectAtIndex:self.currentEffectIndex];
    }
    [[NSNotificationCenter defaultCenter] postNotificationName:kPlaybackFXStateChanged
                                                        object:self
                                                      userInfo:@{ @"enabled" : @(enabled), @"index" : @(self.currentEffectIndex) }];
    [[NSNotificationCenter defaultCenter] postNotificationName:kPlaybackGraphChanged
                                                        object:self
                                                      userInfo:@{kGraphChangeReasonKey : @"effect",
                                                                 kGraphChangeEffectEnabledKey : @(enabled),
                                                                 kGraphChangeEffectIndexKey : @(self.currentEffectIndex)}];
    return ok;
}

- (BOOL)effectEnabled
{
    if ([self.backend respondsToSelector:@selector(effectEnabled)]) {
        return [(id) self.backend effectEnabled];
    }
    return (self.currentEffectIndex >= 0);
}

- (BOOL)tempoBypassed
{
    if ([self.backend respondsToSelector:@selector(tempoBypassed)]) {
        return [(id) self.backend tempoBypassed];
    }
    return (fabsf(self.tempoShift - 1.0f) <= kTempoBypassEpsilon);
}

- (LazySample*)sample
{
    return self.sampleRef;
}

//- (AVAudioFramePosition)totalLatency
//{
//    UInt32 deviceId = [AudioDevice defaultOutputDevice];
//    if (deviceId == 0) {
//        return 0;
//    }
//    if (deviceId != self.cachedDeviceId || self.cachedLatency < 0) {
//        self.cachedLatency = [AudioDevice latencyForDevice:deviceId scope:kAudioDevicePropertyScopeOutput];
//        self.cachedDeviceId = deviceId;
//    }
//    return self.cachedLatency;
//}

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

- (BOOL)defaultDeviceSupportsSampleRateForSample:(LazySample*)sample
{
    if (sample == nil) {
        return NO;
    }
    AudioObjectID deviceId = [AudioDevice defaultOutputDevice];
    Float64 deviceRate = [AudioDevice sampleRateForDevice:deviceId];
    Float64 sourceRate = sample.fileSampleRate;
    if (deviceRate <= 0 || sourceRate <= 0) {
        return NO;
    }
    return [AudioDevice device:deviceId supportsSampleRate:sourceRate];
}

- (BOOL)decode:(LazySample*)encodedSample frame:(unsigned long long)frame token:(ActivityToken*)token reachedFrame:(void (^)(void))reachedFrame cancelTest:(BOOL (^)(void))cancelTest
{
    [[ActivityManager shared] updateActivity:token progress:0.0 detail:@"initializing engine"];

    AudioObjectID deviceId = [AudioDevice defaultOutputDevice];
    Float64 deviceRate = [AudioDevice sampleRateForDevice:deviceId];
    Float64 sourceRate = encodedSample.fileSampleRate;
    // Render at the current device rate. We go this way as any switching happens before decode.
    // Rate switching could prove to be a brittle thing to do, it is discouraged everywhere.
    //
    // And indeed, you will always get a little popp on a Komplete Audio 2 -- not so great,
    // but also not a huge issue for me.
    //
    // It is said that a successfull rate switch may not even be possible with many devices.
    // We do at least try - and from there, we reconciliate from the device state.
    //
    // The decoder gets the rendering rate determined by the device rate at this point.
    // This introduced another caveat; the moment the user switches the output device, we
    // need to re-check if that device would even support the currently available decode/
    // resample variant. Worst case it does not and the entire jazz has to start from the
    // beginning.
    // It is, in my opinion totally worth it. We are using the decoder/resampler in mastering
    // mode, not meant for real-time use -- we just make things appear as if it was real-time.
    Float64 renderRate = (deviceRate > 0 ? deviceRate : sourceRate);
    double expectedRenderedFrames = (sourceRate > 0 ? (double) encodedSample.source.length * (renderRate / sourceRate) : (double) encodedSample.source.length);
    // Update rate immediately so early playback (before full decode) uses the device rate.
    encodedSample.sampleFormat = (SampleFormat){.channels = encodedSample.sampleFormat.channels, .rate = (long) renderRate};
    encodedSample.renderedSampleRate = renderRate;
    [encodedSample setRenderedLength:(unsigned long long) ceil(expectedRenderedFrames)];

    // We now know which rate that file will get decoded/resampled to, lets tell the world.
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:kPlaybackGraphChanged
                                                            object:self
                                                          userInfo:@{kGraphChangeReasonKey : @"sample",
                                                                     @"sample" : encodedSample ?: [NSNull null]}];
    });

    AVAudioFormat* renderFormat = [[AVAudioFormat alloc] initWithCommonFormat:AVAudioPCMFormatFloat32
                                                                   sampleRate:renderRate
                                                                     channels:encodedSample.sampleFormat.channels
                                                                  interleaved:NO];

    // High-quality offline resample via AVAudioConverter.
    AVAudioFormat* sourceFormat = encodedSample.source.processingFormat;
    AVAudioConverter* converter = [[AVAudioConverter alloc] initFromFormat:sourceFormat toFormat:renderFormat];
    converter.sampleRateConverterQuality = AVAudioQualityMax;
    converter.sampleRateConverterAlgorithm = AVSampleRateConverterAlgorithm_Mastering;

    AVAudioPCMBuffer* inputBuffer = [[AVAudioPCMBuffer alloc] initWithPCMFormat:sourceFormat frameCapacity:kDecoderBufferFrames];
    AVAudioPCMBuffer* outputBuffer = [[AVAudioPCMBuffer alloc] initWithPCMFormat:renderFormat frameCapacity:kDecoderBufferFrames];

    unsigned long long pageIndex = 0;
    BOOL ret = YES;
    BOOL reachFrameCalled = NO;

    unsigned long long totalRenderedFrames = 0;
    __block BOOL doneReading = NO;
    while (!doneReading) {
        if (cancelTest()) {
            ret = NO;
            break;
        }

        inputBuffer.frameLength = 0;
        outputBuffer.frameLength = 0;

        AVAudioConverterInputBlock inputBlock = ^AVAudioBuffer* _Nullable(AVAudioPacketCount inNumberOfPackets, AVAudioConverterInputStatus* outStatus) {
            NSError* readError = nil;
            if (![encodedSample.source readIntoBuffer:inputBuffer error:&readError] || inputBuffer.frameLength == 0) {
                *outStatus = AVAudioConverterInputStatus_EndOfStream;
                doneReading = YES;
                return nil;
            }
            *outStatus = AVAudioConverterInputStatus_HaveData;
            return inputBuffer;
        };

        NSError* convertError = nil;
        AVAudioConverterOutputStatus status = [converter convertToBuffer:outputBuffer error:&convertError withInputFromBlock:inputBlock];

        if (status == AVAudioConverterOutputStatus_HaveData && outputBuffer.frameLength > 0) {
            unsigned long long rawDataLengthPerChannel = outputBuffer.frameLength * sizeof(float);
            NSMutableArray<NSData*>* channels = [NSMutableArray array];
            for (int channelIndex = 0; channelIndex < encodedSample.sampleFormat.channels; channelIndex++) {
                NSData* channel = [NSData dataWithBytes:outputBuffer.floatChannelData[channelIndex] length:rawDataLengthPerChannel];
                [channels addObject:channel];
            }
            [encodedSample addLazyPageIndex:pageIndex channels:channels];
            pageIndex++;
            totalRenderedFrames += outputBuffer.frameLength;
        } else if (status == AVAudioConverterOutputStatus_EndOfStream) {
            doneReading = YES;
        } else if (status == AVAudioConverterOutputStatus_Error) {
            NSLog(@"AudioController: resample convert error %@", convertError);
            ret = NO;
            break;
        }

        if (!reachFrameCalled && totalRenderedFrames >= frame) {
            reachedFrame();
            reachFrameCalled = YES;
        }

        double progress = 0.0;
        if (sourceRate > 0 && renderRate > 0 && encodedSample.source.length > 0) {
            double estimatedTotalFrames = (double) encodedSample.source.length * (renderRate / sourceRate);
            progress = MIN(1.0, totalRenderedFrames / estimatedTotalFrames);
        }
        [[ActivityManager shared] updateActivity:token progress:progress detail:@"decoding compressed audio data"];
    }
    [[ActivityManager shared] updateActivity:token progress:1.0 detail:@"decoding audio done"];

    // Update sample metadata to reflect the rendered rate so playback/tap stay at the device rate.
    encodedSample.sampleFormat = (SampleFormat){.channels = encodedSample.sampleFormat.channels, .rate = (long) renderRate};
    [encodedSample setRenderedLength:totalRenderedFrames];
    [encodedSample markDecodingComplete];
    return ret;
}

- (void)decodeAsyncWithSample:(LazySample*)sample notifyEarlyAtFrame:(unsigned long long)frame callback:(void (^)(BOOL,BOOL))callback
{
    __weak AudioController* weakSelf = self;

    __block BOOL done = NO;
    __weak __block dispatch_block_t weakBlock;

    ActivityToken* decoderToken = [[ActivityManager shared] beginActivityWithTitle:@"Decoding Sample" detail:@"" cancellable:NO cancelHandler:nil];

    dispatch_block_t block = dispatch_block_create(DISPATCH_BLOCK_NO_QOS_CLASS, ^{
        done = [weakSelf decode:sample
                          frame:frame
                          token:decoderToken
                   reachedFrame:^ {
            dispatch_async(dispatch_get_main_queue(), ^{
                callback(NO, YES);
            });
        }
                     cancelTest:^BOOL {
            return dispatch_block_testcancel(weakBlock) != 0 ? YES : NO;
        }];
    });

    weakBlock = block;
    self.decodeOperation = block;

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), self.decodeOperation);

    dispatch_block_notify(self.decodeOperation, dispatch_get_main_queue(), ^{
        [[ActivityManager shared] completeActivity:decoderToken];
        callback(done,YES);
    });
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
