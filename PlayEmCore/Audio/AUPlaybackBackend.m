//
//  AUPlaybackBackend.m
//  PlayEm
//
//  Created by Till Toenshoff on 01/05/26.
//  Copyright © 2026 Till Toenshoff. All rights reserved.
//

#import "AUPlaybackBackend.h"

#import <AudioToolbox/AudioToolbox.h>

#import "AudioDevice.h"
#import "LazySample.h"

@interface AUPlaybackBackend () {
    AudioComponentInstance _outputUnit;
    AUGraph _graph;
    AudioUnit _mixerUnit;
    AudioUnit _timePitchUnit;
    AudioUnit _effectUnit;
    AUNode _outputNode;
    AUNode _mixerNode;
    AUNode _timePitchNode;
    AUNode _effectNode;
    BOOL _playing;
    BOOL _paused;
    float _volume;
    float _tempo;
    BOOL _hasEffect;
    AudioComponentDescription _effectDescription;
}
@property (nonatomic, strong) LazySample* sample;
@property (nonatomic, copy) void (^tapBlock)(unsigned long long, float*, unsigned int);
@property (atomic) unsigned long long baseFrame;
@property (atomic) signed long long latencyFrames;
@property (atomic) unsigned long long tapFrame;
- (OSStatus)createGraphAndNodes;
- (OSStatus)configureFormats;
- (OSStatus)installRenderCallback;
- (OSStatus)connectGraph;
- (OSStatus)installTapNotify;
- (OSStatus)initializeGraph;
- (AudioStreamBasicDescription)streamFormatForSample;
- (void)applyTempo;
- (AudioUnit)tapSourceUnit;
- (BOOL)hasEffectUnit;
@end

static OSStatus AUPlaybackRender(void* inRefCon, AudioUnitRenderActionFlags* ioActionFlags, const AudioTimeStamp* inTimeStamp, UInt32 inBusNumber,
                                 UInt32 inNumberFrames, AudioBufferList* ioData);
static OSStatus AUPlaybackTapNotify(void* inRefCon, AudioUnitRenderActionFlags* ioActionFlags, const AudioTimeStamp* inTimeStamp, UInt32 inBusNumber,
                                    UInt32 inNumberFrames, AudioBufferList* ioData);

@implementation AUPlaybackBackend

@synthesize playing = _playing;
@synthesize paused = _paused;
@synthesize volume = _volume;
@synthesize tempo = _tempo;
@synthesize delegate = _delegate;

- (instancetype)init
{
    self = [super init];
    if (self) {
        _volume = 1.0f;
        _tempo = 1.0f;
        _baseFrame = 0;
        _latencyFrames = 0;
        _tapFrame = 0;
        _hasEffect = NO;
        memset(&_effectDescription, 0, sizeof(_effectDescription));
    }
    return self;
}

- (void)dealloc
{
    [self stop];
    if (_outputUnit != NULL) {
        AudioComponentInstanceDispose(_outputUnit);
        _outputUnit = NULL;
    }
    if (_graph != NULL) {
        AUGraphStop(_graph);
        AUGraphUninitialize(_graph);
        AUGraphClose(_graph);
        DisposeAUGraph(_graph);
        _graph = NULL;
    }
}

- (OSStatus)configureGraph
{
    NSLog(@"AUPlaybackBackend: configureGraph begin (hasEffect=%d type=0x%08x subtype=0x%08x manuf=0x%08x)", _hasEffect,
          (unsigned int) _effectDescription.componentType, (unsigned int) _effectDescription.componentSubType,
          (unsigned int) _effectDescription.componentManufacturer);
    if (_graph != NULL) {
        AUGraphStop(_graph);
        AUGraphUninitialize(_graph);
        AUGraphClose(_graph);
        DisposeAUGraph(_graph);
        _graph = NULL;
        _outputUnit = NULL;
        _mixerUnit = NULL;
        _timePitchUnit = NULL;
        _effectUnit = NULL;
        _outputNode = 0;
        _mixerNode = 0;
        _timePitchNode = 0;
        _effectNode = 0;
    }
    OSStatus res = [self createGraphAndNodes];
    if (res != noErr) {
        return res;
    }
    res = [self configureFormats];
    if (res != noErr) {
        return res;
    }
    res = [self installRenderCallback];
    if (res != noErr) {
        return res;
    }
    res = [self connectGraph];
    if (res != noErr) {
        return res;
    }
    res = [self installTapNotify];
    if (res != noErr) {
        return res;
    }
    res = [self initializeGraph];
    if (res != noErr) {
        return res;
    }
    [self applyTempo];
    // Set initial volumes.
    AudioUnitParameterValue vol = _volume;
    AudioUnitSetParameter(_mixerUnit, kMultiChannelMixerParam_Volume, kAudioUnitScope_Input, 0, vol, 0);
    AudioUnitSetParameter(_mixerUnit, kMultiChannelMixerParam_Volume, kAudioUnitScope_Output, 0, vol, 0);
    NSLog(@"AUPlaybackBackend: configureGraph finished res=%d", (int) res);
    return res;
}

- (void)prepareWithSample:(LazySample*)sample
{
    [self stop];
    self.sample = sample;
    self.baseFrame = 0;
    self.tapFrame = 0;
    AudioObjectID deviceId = [AudioDevice defaultOutputDevice];
    self.latencyFrames = [AudioDevice latencyForDevice:deviceId scope:kAudioDevicePropertyScopeOutput];
    OSStatus res = [self configureGraph];
    if (res != noErr) {
        NSLog(@"AUPlaybackBackend configureGraph failed: %d", (int) res);
    }
}

- (void)play
{
    if (_playing || self.sample == nil) {
        return;
    }
    AudioOutputUnitStart(_outputUnit);
    AUGraphStart(_graph);
    _playing = YES;
    _paused = NO;
    [self.delegate playbackBackendDidStart:self];
}

- (void)pause
{
    if (!_playing) {
        return;
    }
    AudioOutputUnitStop(_outputUnit);
    _paused = YES;
    _playing = NO;
    [self.delegate playbackBackendDidPause:self];
}

- (void)stop
{
    if (_outputUnit != NULL) {
        AudioOutputUnitStop(_outputUnit);
    }
    if (_graph != NULL) {
        AUGraphStop(_graph);
    }
    _playing = NO;
    _paused = NO;
    _timePitchUnit = NULL;
    _effectUnit = NULL;
}

- (void)seekToFrame:(unsigned long long)frame
{
    self.baseFrame = frame;
    self.tapFrame = frame;
}

- (unsigned long long)currentFrame
{
    signed long long adjusted = (signed long long) self.baseFrame - self.latencyFrames;
    if (adjusted < 0) {
        adjusted = 0;
    }
    return (unsigned long long) adjusted;
}

- (NSTimeInterval)currentTime
{
    if (self.sample == nil) {
        return 0;
    }
    return ((NSTimeInterval)[self currentFrame] / self.sample.sampleFormat.rate);
}

- (void)setVolume:(float)volume
{
    _volume = volume;
    if (_mixerUnit != NULL) {
        AudioUnitParameterValue vol = _volume;
        AudioUnitSetParameter(_mixerUnit, kMultiChannelMixerParam_Volume, kAudioUnitScope_Input, 0, vol, 0);
        AudioUnitSetParameter(_mixerUnit, kMultiChannelMixerParam_Volume, kAudioUnitScope_Output, 0, vol, 0);
    }
}

- (float)volume
{
    return _volume;
}

- (void)setTempo:(float)tempo
{
    _tempo = tempo;
    [self applyTempo];
}

- (BOOL)setEffectWithDescription:(AudioComponentDescription)description
{
    NSLog(@"AUPlaybackBackend: setEffectWithDescription type=0x%08x subtype=0x%08x manuf=0x%08x", (unsigned int) description.componentType,
          (unsigned int) description.componentSubType, (unsigned int) description.componentManufacturer);
    BOOL wasPlaying = _playing;
    [self stop];
    BOOL enable = !(description.componentType == 0 && description.componentSubType == 0 && description.componentManufacturer == 0);
    _hasEffect = enable;
    _effectDescription = description;
    OSStatus res = [self configureGraph];
    if (res == noErr && wasPlaying && self.sample != nil) {
        [self play];
    }
    if (res != noErr) {
        NSLog(@"AUPlaybackBackend: setEffectWithDescription failed res=%d", (int) res);
    }
    return (res == noErr);
}

- (float)tempo
{
    return _tempo;
}

- (void)setTapBlock:(void (^)(unsigned long long, float*, unsigned int))tapBlock
{
    _tapBlock = [tapBlock copy];
}

- (OSStatus)createGraphAndNodes
{
    OSStatus res = NewAUGraph(&_graph);
    if (res != noErr) {
        NSLog(@"AUPlaybackBackend: NewAUGraph failed: %d", (int) res);
        return res;
    }
    AudioComponentDescription halDesc = {0};
    halDesc.componentType = kAudioUnitType_Output;
    halDesc.componentSubType = kAudioUnitSubType_HALOutput;
    halDesc.componentManufacturer = kAudioUnitManufacturer_Apple;

    AudioComponentDescription timePitchDesc = {0};
    timePitchDesc.componentType = kAudioUnitType_FormatConverter;
    timePitchDesc.componentSubType = kAudioUnitSubType_NewTimePitch;
    timePitchDesc.componentManufacturer = kAudioUnitManufacturer_Apple;

    AudioComponentDescription effectDesc = _effectDescription;

    AudioComponentDescription mixerDesc = {0};
    mixerDesc.componentType = kAudioUnitType_Mixer;
    mixerDesc.componentSubType = kAudioUnitSubType_MultiChannelMixer;
    mixerDesc.componentManufacturer = kAudioUnitManufacturer_Apple;

    res = AUGraphAddNode(_graph, &mixerDesc, &_mixerNode);
    if (res != noErr) {
        NSLog(@"AUPlaybackBackend: AddNode mixer failed: %d", (int) res);
        return res;
    }
    if (_hasEffect) {
        res = AUGraphAddNode(_graph, &effectDesc, &_effectNode);
        if (res != noErr) {
            NSLog(@"AUPlaybackBackend: AddNode effect failed: %d", (int) res);
            return res;
        }
    }
    res = AUGraphAddNode(_graph, &timePitchDesc, &_timePitchNode);
    if (res != noErr) {
        NSLog(@"AUPlaybackBackend: AddNode time-pitch failed: %d", (int) res);
        return res;
    }
    res = AUGraphAddNode(_graph, &halDesc, &_outputNode);
    if (res != noErr) {
        NSLog(@"AUPlaybackBackend: AddNode output failed: %d", (int) res);
        return res;
    }
    res = AUGraphOpen(_graph);
    if (res != noErr) {
        NSLog(@"AUPlaybackBackend: AUGraphOpen failed: %d", (int) res);
        return res;
    }
    res = AUGraphNodeInfo(_graph, _outputNode, NULL, &_outputUnit);
    if (res != noErr) {
        NSLog(@"AUPlaybackBackend: NodeInfo output failed: %d", (int) res);
        return res;
    }
    res = AUGraphNodeInfo(_graph, _mixerNode, NULL, &_mixerUnit);
    if (res != noErr) {
        NSLog(@"AUPlaybackBackend: NodeInfo mixer failed: %d", (int) res);
        return res;
    }
    if (_hasEffect) {
        res = AUGraphNodeInfo(_graph, _effectNode, NULL, &_effectUnit);
        if (res != noErr) {
            NSLog(@"AUPlaybackBackend: NodeInfo effect failed: %d", (int) res);
            return res;
        }
    }
    res = AUGraphNodeInfo(_graph, _timePitchNode, NULL, &_timePitchUnit);
    if (res != noErr) {
        NSLog(@"AUPlaybackBackend: NodeInfo time-pitch failed: %d", (int) res);
        return res;
    }
    if (_hasEffect) {
        NSLog(@"AUPlaybackBackend: effect node added type=0x%08x subtype=0x%08x manuf=0x%08x", (unsigned int) _effectDescription.componentType,
              (unsigned int) _effectDescription.componentSubType, (unsigned int) _effectDescription.componentManufacturer);
        AudioComponentDescription actual = {0};
        AudioComponentGetDescription(AudioComponentInstanceGetComponent(_effectUnit), &actual);
        NSLog(@"AUPlaybackBackend: effect instantiated type=0x%08x subtype=0x%08x manuf=0x%08x", (unsigned int) actual.componentType,
              (unsigned int) actual.componentSubType, (unsigned int) actual.componentManufacturer);
    }
    return res;
}

- (OSStatus)configureFormats
{
    UInt32 busCount = 1;
    OSStatus res = AudioUnitSetProperty(_mixerUnit, kAudioUnitProperty_ElementCount, kAudioUnitScope_Input, 0, &busCount, sizeof(busCount));
    if (res != noErr) {
        NSLog(@"AUPlaybackBackend: set bus count failed: %d", (int) res);
        return res;
    }

    AudioStreamBasicDescription fmt = [self streamFormatForSample];
    res = AudioUnitSetProperty(_mixerUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 0, &fmt, sizeof(fmt));
    if (res != noErr) {
        NSLog(@"AUPlaybackBackend: mixer input format failed: %d", (int) res);
        return res;
    }

    res = AudioUnitSetProperty(_mixerUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 0, &fmt, sizeof(fmt));
    if (res != noErr) {
        NSLog(@"AUPlaybackBackend: mixer output format failed: %d", (int) res);
        return res;
    }

    if (_hasEffect) {
        NSLog(@"AUPlaybackBackend: configuring effect formats");
        res = AudioUnitSetProperty(_effectUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 0, &fmt, sizeof(fmt));
        if (res != noErr) {
            NSLog(@"AUPlaybackBackend: effect input format failed: %d", (int) res);
            return res;
        }
        res = AudioUnitSetProperty(_effectUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 0, &fmt, sizeof(fmt));
        if (res != noErr) {
            NSLog(@"AUPlaybackBackend: effect output format failed: %d", (int) res);
            return res;
        }
    }

    res = AudioUnitSetProperty(_timePitchUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 0, &fmt, sizeof(fmt));
    if (res != noErr) {
        NSLog(@"AUPlaybackBackend: time-pitch input format failed: %d", (int) res);
        return res;
    }

    res = AudioUnitSetProperty(_timePitchUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 0, &fmt, sizeof(fmt));
    if (res != noErr) {
        NSLog(@"AUPlaybackBackend: time-pitch output format failed: %d", (int) res);
        return res;
    }

    res = AudioUnitSetProperty(_outputUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 0, &fmt, sizeof(fmt));
    if (res != noErr) {
        NSLog(@"AUPlaybackBackend: output stream format failed: %d", (int) res);
    }
    NSLog(@"AUPlaybackBackend: configureFormats success");
    return res;
}

- (OSStatus)installRenderCallback
{
    AURenderCallbackStruct render;
    render.inputProc = AUPlaybackRender;
    render.inputProcRefCon = (__bridge void*) self;
    OSStatus res = AudioUnitSetProperty(_mixerUnit, kAudioUnitProperty_SetRenderCallback, kAudioUnitScope_Input, 0, &render, sizeof(render));
    if (res != noErr) {
        NSLog(@"AUPlaybackBackend: SetRenderCallback mixer failed: %d", (int) res);
    }
    return res;
}

- (OSStatus)connectGraph
{
    AUNode sink = _timePitchNode;
    AUNode source = _mixerNode;
    OSStatus res = noErr;
    if (_hasEffect) {
        res = AUGraphConnectNodeInput(_graph, _mixerNode, 0, _effectNode, 0);
        if (res != noErr) {
            NSLog(@"AUPlaybackBackend: connect mixer->effect failed: %d", (int) res);
            return res;
        }
        source = _effectNode;
    }
    res = AUGraphConnectNodeInput(_graph, source, 0, sink, 0);
    if (res != noErr) {
        NSLog(@"AUPlaybackBackend: connect upstream->time-pitch failed: %d", (int) res);
        return res;
    }
    res = AUGraphConnectNodeInput(_graph, _timePitchNode, 0, _outputNode, 0);
    if (res != noErr) {
        NSLog(@"AUPlaybackBackend: connect time-pitch->output failed: %d", (int) res);
    }
    return res;
}

- (OSStatus)installTapNotify
{
    AudioUnit tapUnit = [self tapSourceUnit];
    OSStatus res = AudioUnitAddRenderNotify(tapUnit, AUPlaybackTapNotify, (__bridge void*) self);
    if (res != noErr) {
        NSLog(@"AUPlaybackBackend: AddRenderNotify failed: %d", (int) res);
    }
    return res;
}

- (OSStatus)initializeGraph
{
    OSStatus res = AUGraphInitialize(_graph);
    if (res != noErr) {
        NSLog(@"AUPlaybackBackend: AUGraphInitialize failed: %d", (int) res);
    }
    return res;
}

- (AudioStreamBasicDescription)streamFormatForSample
{
    AudioStreamBasicDescription fmt = {0};
    fmt.mSampleRate = (Float64) self.sample.sampleFormat.rate;
    fmt.mFormatID = kAudioFormatLinearPCM;
    fmt.mFormatFlags = kLinearPCMFormatFlagIsFloat | kAudioFormatFlagIsPacked | kAudioFormatFlagIsNonInterleaved;
    fmt.mFramesPerPacket = 1;
    fmt.mChannelsPerFrame = (uint32_t) self.sample.sampleFormat.channels;
    fmt.mBytesPerFrame = sizeof(float);
    fmt.mBytesPerPacket = sizeof(float);
    fmt.mBitsPerChannel = 32;
    return fmt;
}

- (AudioUnit)tapSourceUnit
{
    if (_timePitchUnit != NULL) {
        return _timePitchUnit;
    }
    if (_effectUnit != NULL) {
        return _effectUnit;
    }
    return _mixerUnit;
}

- (void)applyTempo
{
    if (_timePitchUnit == NULL) {
        return;
    }
    AudioUnitParameterValue rate = _tempo;
    AudioUnitSetParameter(_timePitchUnit, kNewTimePitchParam_Rate, kAudioUnitScope_Global, 0, rate, 0);
}

- (BOOL)hasEffectUnit
{
    return _effectUnit != NULL;
}

- (NSArray<NSNumber*>*)effectParameterList
{
    if (![self hasEffectUnit]) {
        return @[];
    }
    UInt32 dataSize = 0;
    OSStatus res = AudioUnitGetPropertyInfo(_effectUnit, kAudioUnitProperty_ParameterList, kAudioUnitScope_Global, 0, &dataSize, NULL);
    if (res != noErr || dataSize == 0 || (dataSize % sizeof(AudioUnitParameterID)) != 0) {
        return @[];
    }
    UInt32 count = dataSize / sizeof(AudioUnitParameterID);
    AudioUnitParameterID* ids = (AudioUnitParameterID*) malloc(dataSize);
    if (ids == NULL) {
        return @[];
    }
    res = AudioUnitGetProperty(_effectUnit, kAudioUnitProperty_ParameterList, kAudioUnitScope_Global, 0, ids, &dataSize);
    if (res != noErr) {
        free(ids);
        return @[];
    }
    NSMutableArray<NSNumber*>* list = [NSMutableArray arrayWithCapacity:count];
    for (UInt32 i = 0; i < count; i++) {
        [list addObject:@(ids[i])];
    }
    free(ids);
    return list;
}

- (NSDictionary<NSNumber*, NSDictionary*>*)effectParameterInfo
{
    if (![self hasEffectUnit]) {
        return @{};
    }
    NSMutableDictionary<NSNumber*, NSDictionary*>* info = [NSMutableDictionary dictionary];
    NSArray<NSNumber*>* scopes = @[ @(kAudioUnitScope_Global), @(kAudioUnitScope_Input), @(kAudioUnitScope_Output) ];
    for (NSNumber* scopeNum in scopes) {
        AudioUnitScope scope = (AudioUnitScope) scopeNum.unsignedIntValue;
        UInt32 element = 0;

        UInt32 dataSize = 0;
        if (AudioUnitGetPropertyInfo(_effectUnit, kAudioUnitProperty_ParameterList, scope, element, &dataSize, NULL) != noErr || dataSize == 0 ||
            (dataSize % sizeof(AudioUnitParameterID)) != 0) {
            continue;
        }
        UInt32 count = dataSize / sizeof(AudioUnitParameterID);
        AudioUnitParameterID* ids = (AudioUnitParameterID*) malloc(dataSize);
        if (ids == NULL) {
            continue;
        }
        if (AudioUnitGetProperty(_effectUnit, kAudioUnitProperty_ParameterList, scope, element, ids, &dataSize) != noErr) {
            free(ids);
            continue;
        }
        for (UInt32 i = 0; i < count; i++) {
            NSNumber* param = @(ids[i]);
            if (info[param] != nil) {
                continue;
            }
            AudioUnitParameterInfo paramInfo;
            UInt32 size = sizeof(paramInfo);
            if (AudioUnitGetProperty(_effectUnit, kAudioUnitProperty_ParameterInfo, scope, ids[i], &paramInfo, &size) != noErr) {
                continue;
            }
            AudioUnitParameterValue current = paramInfo.defaultValue;
            AudioUnitGetParameter(_effectUnit, ids[i], scope, element, &current);
            NSString* name = @"";
            if (paramInfo.cfNameString != NULL) {
                name = [(__bridge NSString*) paramInfo.cfNameString copy];
            } else if (paramInfo.name[0] != '\0') {
                name = [NSString stringWithUTF8String:paramInfo.name] ?: @"";
            }
            if (name.length == 0) {
                name = [NSString stringWithFormat:@"Param %u", ids[i]];
            }
            NSDictionary* entry = @{
                @"name" : name ?: @"",
                @"min" : @(paramInfo.minValue),
                @"max" : @(paramInfo.maxValue),
                @"default" : @(paramInfo.defaultValue),
                @"current" : @(current),
                @"unit" : @(paramInfo.unit),
                @"flags" : @(paramInfo.flags)
            };
            info[param] = entry;
        }
        free(ids);
    }
    return info;
}

- (BOOL)setEffectParameter:(AudioUnitParameterID)parameter value:(AudioUnitParameterValue)value
{
    if (![self hasEffectUnit]) {
        return NO;
    }
    OSStatus res = AudioUnitSetParameter(_effectUnit, parameter, kAudioUnitScope_Global, 0, value, 0);
    return (res == noErr);
}

- (NSArray<NSDictionary*>*)availableEffects
{
    NSMutableArray<NSDictionary*>* list = [NSMutableArray array];
    NSSet<NSNumber*>* types = [NSSet setWithObjects:@(kAudioUnitType_Effect), @(kAudioUnitType_MusicEffect), nil];
    for (NSNumber* type in types) {
        AudioComponentDescription query;
        memset(&query, 0, sizeof(query));
        query.componentType = (OSType) type.unsignedIntValue;
        AudioComponent comp = NULL;
        while ((comp = AudioComponentFindNext(comp, &query)) != NULL) {
            AudioComponentDescription got;
            if (AudioComponentGetDescription(comp, &got) != noErr) {
                continue;
            }
            AudioComponentInstance inst = NULL;
            if (AudioComponentInstanceNew(comp, &inst) != noErr || inst == NULL) {
                continue;
            }
            AudioComponentInstanceDispose(inst);
            CFStringRef nameRef = NULL;
            AudioComponentCopyName(comp, &nameRef);
            NSString* name = nameRef ? (__bridge_transfer NSString*) nameRef : @"";
            NSValue* packed = [NSValue valueWithBytes:&got objCType:@encode(AudioComponentDescription)];
            NSDictionary* entry = @{
                @"name" : name ?: @"",
                @"type" : @(got.componentType),
                @"subtype" : @(got.componentSubType),
                @"manufacturer" : @(got.componentManufacturer),
                @"component" : packed
            };
            [list addObject:entry];
        }
    }
    return list;
}

@end

static OSStatus AUPlaybackRender(void* inRefCon, AudioUnitRenderActionFlags* ioActionFlags, const AudioTimeStamp* inTimeStamp, UInt32 inBusNumber,
                                 UInt32 inNumberFrames, AudioBufferList* ioData)
{
    AUPlaybackBackend* backend = (__bridge AUPlaybackBackend*) inRefCon;
    if (backend.sample == nil) {
        for (UInt32 i = 0; i < ioData->mNumberBuffers; i++) {
            memset(ioData->mBuffers[i].mData, 0, ioData->mBuffers[i].mDataByteSize);
        }
        return noErr;
    }
    unsigned int channels = (unsigned int) backend.sample.sampleFormat.channels;
    unsigned int frames = inNumberFrames;
    if (ioData->mNumberBuffers < channels) {
        return noErr;
    }
    static NSMutableData* tmp = nil;
    size_t needed = (size_t) frames * channels * sizeof(float);
    if (tmp == nil || tmp.length < needed) {
        tmp = [NSMutableData dataWithLength:needed];
    }
    float* interleaved = (float*) tmp.mutableBytes;
    unsigned long long startFrame = backend.baseFrame;
    backend.tapFrame = startFrame;
    unsigned long long fetched = [backend.sample rawSampleFromFrameOffset:backend.baseFrame frames:frames data:interleaved];
    if (fetched < frames) {
        memset(interleaved + fetched * channels, 0, (frames - fetched) * channels * sizeof(float));
    }
    for (unsigned int ch = 0; ch < channels; ch++) {
        float* dst = (float*) ioData->mBuffers[ch].mData;
        for (unsigned int f = 0; f < frames; f++) {
            dst[f] = interleaved[f * channels + ch];
        }
    }
    backend.baseFrame = backend.baseFrame + fetched;
    return noErr;
}

static OSStatus AUPlaybackTapNotify(void* inRefCon, AudioUnitRenderActionFlags* ioActionFlags, const AudioTimeStamp* inTimeStamp, UInt32 inBusNumber,
                                    UInt32 inNumberFrames, AudioBufferList* ioData)
{
    AUPlaybackBackend* backend = (__bridge AUPlaybackBackend*) inRefCon;
    if (backend.tapBlock == nil || ioData->mNumberBuffers < 1) {
        return noErr;
    }
    unsigned int channels = (unsigned int) backend.sample.sampleFormat.channels;
    unsigned int frames = inNumberFrames;
    static NSMutableData* tmp = nil;
    size_t needed = (size_t) frames * channels * sizeof(float);
    if (tmp == nil || tmp.length < needed) {
        tmp = [NSMutableData dataWithLength:needed];
    }
    float* interleaved = (float*) tmp.mutableBytes;
    for (unsigned int f = 0; f < frames; f++) {
        for (unsigned int ch = 0; ch < channels; ch++) {
            float* src = (float*) ioData->mBuffers[ch].mData;
            interleaved[f * channels + ch] = src ? src[f] : 0.0f;
        }
    }
    unsigned long long framePos = backend.tapFrame;
    unsigned long long available = (backend.baseFrame > backend.tapFrame) ? (backend.baseFrame - backend.tapFrame) : 0;
    unsigned int delivered = (unsigned int) MIN((unsigned long long) frames, available);
    backend.tapFrame = backend.tapFrame + delivered;
    backend.tapBlock(framePos, interleaved, delivered);

    return noErr;
}
