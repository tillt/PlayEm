//
//  WaveWindowController+Loader.m
//  PlayEm
//
//  Created by Till Toenshoff on 2026-01-16.
//  Copyright (c) 2026 Till Toenshoff. All rights reserved.
//

#import "WaveWindowController+Loader.h"

#import <objc/runtime.h>

#import "ActivityManager.h"
#import "AudioDevice.h"
#import "BeatTrackedSample.h"
#import "BrowserController+DeepScan.h"
#import "ControlPanelController.h"
#import "FXViewController.h"
#import "KeyTrackedSample.h"
#import "LazySample.h"
#import "MediaMetaData.h"
#import "MediaMetaData+TrackList.h"
#import "MetaController.h"
#import "NSAlert+BetterError.h"
#import "PlaylistController.h"
#import "TracklistController.h"
#import "VisualSample.h"
#import "WaveViewController.h"

typedef NS_ENUM(NSUInteger, LoaderState) {
    LoaderStateReady,

    LoaderStateMeta,
    LoaderStateDecoder,
    LoaderStateBeatDetection,
    LoaderStateKeyDetection,

    LoaderStateAbortingMeta,
    LoaderStateAbortingDecoder,
    LoaderStateAbortingBeatDetection,
    LoaderStateAbortingKeyDetection,

    LoaderStateAborted,
};

typedef struct {
    BOOL playing;
    unsigned long long frame;
    NSString* path;
    MediaMetaData* meta;
} LoaderContext;

@interface WaveWindowController ()
@property (assign, nonatomic) LoaderState loaderState;
@property (nonatomic, strong) MetaController* metaController;
@property (nonatomic, strong) MediaMetaData* meta;
@property (nonatomic, strong) LazySample* sample;
@property (nonatomic, strong) ControlPanelController* controlPanelController;
@property (nonatomic, strong) FXViewController* fxViewController;
@property (nonatomic, strong) PlaylistController* playlist;
@property (nonatomic, strong) TracklistController* tracklist;
@property (nonatomic, strong) WaveViewController* scrollingWaveViewController;
@property (nonatomic, strong) WaveViewController* totalWaveViewController;

- (NSInteger)storedEffectSelectionIndex;
- (void)setBPM:(float)bpm;
- (void)beatEffectStart;
@end

@implementation WaveWindowController (Loader)

static void* kLoaderStateKey = &kLoaderStateKey;

- (LoaderState)loaderState
{
    NSNumber* value = objc_getAssociatedObject(self, kLoaderStateKey);
    if (value == nil) {
        return LoaderStateReady;
    }
    return (LoaderState) value.unsignedIntegerValue;
}

- (void)setLoaderState:(LoaderState)loaderState
{
    objc_setAssociatedObject(self, kLoaderStateKey, @(loaderState), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (LoaderContext)loaderSetupWithURL:(NSURL*)url
{
    LoaderContext loaderOut;
    NSURLComponents* components = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:YES];

    NSPredicate* predicate = [NSPredicate predicateWithFormat:@"name=%@", @"CurrentFrame"];
    NSURLQueryItem* item = [[components.queryItems filteredArrayUsingPredicate:predicate] firstObject];
    long long frame = [[item value] longLongValue];

    if (frame < 0) {
        NSLog(@"not fixing a bug here due to lazyness -- hope it happens rarely");
        frame = 0;
    }

    predicate = [NSPredicate predicateWithFormat:@"name=%@", @"Playing"];
    item = [[components.queryItems filteredArrayUsingPredicate:predicate] firstObject];
    loaderOut.playing = [[item value] boolValue];
    loaderOut.path = url.path;
    loaderOut.frame = frame;
    return loaderOut;
}

- (BOOL)loadDocumentFromURL:(NSURL*)url meta:(MediaMetaData*)meta
{
    NSError* error = nil;
    if (self.audioController == nil) {
        self.audioController = [AudioController new];
        self.fxViewController.audioController = self.audioController;
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(AudioControllerPlaybackStateChange:)
                                                     name:kAudioControllerChangedPlaybackStateNotification
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(AudioControllerFXStateChange:)
                                                     name:kPlaybackFXStateChanged
                                                   object:nil];
        __weak typeof(self) weakSelf = self;
        [self.audioController refreshAvailableEffectsAsync:^(NSArray<NSDictionary*>* effects) {
            [weakSelf.fxViewController updateEffects:effects];
            BOOL enabled = (weakSelf.audioController.currentEffectIndex >= 0);
            if (!enabled) {
                NSInteger stored = [weakSelf storedEffectSelectionIndex];
                BOOL storedEnabled = [[NSUserDefaults standardUserDefaults] boolForKey:kFXLastEffectEnabledKey];
                if (storedEnabled && stored >= 0) {
                    if ([weakSelf.audioController selectEffectAtIndex:stored]) {
                        enabled = YES;
                        [weakSelf.fxViewController selectEffectIndex:stored];
                        [weakSelf.fxViewController applyCurrentSelection];
                        [weakSelf.fxViewController setEffectEnabledState:YES];
                    }
                }
            }
            [weakSelf.controlPanelController setEffectsEnabled:(weakSelf.audioController.currentEffectIndex >= 0)];
        }];
    }

    if (url == nil) {
        return NO;
    }

    NSLog(@"loadDocumentFromURL url: %@ - known meta: %@", url, meta);

    // Check if that file is even readable.
    if (![url checkResourceIsReachableAndReturnError:&error]) {
        if (error != nil) {
            NSAlert* alert = [NSAlert betterAlertWithError:error
                                                   action:NSLocalizedString(@"error.action.load", @"Error action: load")
                                                      url:url];
            [alert runModal];
        }
        return NO;
    }

    LoaderContext context = [self loaderSetupWithURL:url];

    // This seems pointless by now -- we will re-read that meta anyway.
    context.meta = meta;

    // FIXME: This is far too localized -- lets not update the screen whenever we
    // change the status explicitly -- this should happen implicitly.

    self.loaderState = LoaderStateAbortingKeyDetection;

    WaveWindowController* __weak weakSelf = self;
    // The loader may already be active at this moment -- we abort it and hand
    // over our payload block when abort did its job.
    [self abortLoader:^{
        NSLog(@"loading new meta from: %@ ...", context.path);
        weakSelf.loaderState = LoaderStateMeta;
        [weakSelf loadMetaWithContext:context];
    }];

    return YES;
}

- (void)loadMetaWithContext:(LoaderContext)context
{
    if (self.loaderState == LoaderStateAborted) {
        return;
    }

    self.loaderState = LoaderStateMeta;
    WaveWindowController* __weak weakSelf = self;

    ActivityToken* token = [[ActivityManager shared] beginActivityWithTitle:NSLocalizedString(@"activity.metadata.parse.title", @"Title for metadata parsing activity")
                                                                     detail:NSLocalizedString(@"activity.metadata.parse.loading_core", @"Detail while loading core metadata")
                                                                cancellable:NO
                                                              cancelHandler:nil];

    [self.metaController loadAsyncWithPath:context.path
                                  callback:^(MediaMetaData* meta) {
                                      [[ActivityManager shared] updateActivity:token progress:-1.0 detail:NSLocalizedString(@"activity.metadata.parse.loaded", @"Detail when metadata is loaded")];
                                      if (meta != nil) {
                                          LoaderContext c = context;
                                          c.meta = meta;

                                          if (meta.trackList == nil || meta.trackList.tracks.count == 0) {
                                              NSLog(@"We dont seem to have a tracklist yet - lets see "
                                                    @"if we can recover one...");

                                              // Not being able to get the tracklist is not a reason to
                                              // fail the load process.
                                              [meta recoverTracklistWithCallback:^(BOOL completed, NSError* error) {
                                                  if (!completed) {
                                                      NSLog(@"tracklist recovery failed: %@", error);
                                                  }
                                                  [[ActivityManager shared] updateActivity:token progress:-1.0 detail:NSLocalizedString(@"activity.metadata.tracklist.loaded", @"Detail when tracklist is loaded")];
                                                  [weakSelf metaLoadedWithContext:c];
                                                  [[ActivityManager shared] completeActivity:token];
                                              }];
                                          } else {
                                              [weakSelf metaLoadedWithContext:c];
                                              [[ActivityManager shared] completeActivity:token];
                                          }
                                      } else {
                                          LoaderContext c = context;
                                          c.meta = nil;
                                          [weakSelf metaLoadedWithContext:c];
                                          [[ActivityManager shared] completeActivity:token];
                                      }
                                  }];
}

- (void)metaLoadedWithContext:(LoaderContext)context
{
    WaveWindowController* __weak weakSelf = self;

    MediaMetaData* meta = context.meta;
    if (context.meta == nil) {
        NSLog(@"!!!no meta available - makeing something up!!!");
        meta = [MediaMetaData emptyMediaDataWithURL:[NSURL fileURLWithPath:context.path]];
    }

    [self setMeta:meta];

    NSError* error = nil;
    LazySample* lazySample = [[LazySample alloc] initWithPath:context.path error:&error];
    if (lazySample == nil) {
        if (error) {
            NSAlert* alert = [NSAlert betterAlertWithError:error
                                                   action:NSLocalizedString(@"error.action.read", @"Error action: read")
                                                      url:[NSURL fileURLWithPath:context.path]];
            [alert runModal];
        }
        return;
    }
    [[NSDocumentController sharedDocumentController] noteNewRecentDocumentURL:[NSURL fileURLWithPath:context.path]];

    Float64 sourceRate = lazySample.fileSampleRate;

    // We now know about the sample rate used for encoding the file, tell the world.
    [[NSNotificationCenter defaultCenter] postNotificationName:kPlaybackGraphChanged
                                                        object:self.audioController
                                                      userInfo:@{kGraphChangeReasonKey : @"fileRate",
                                                                 @"sample" : lazySample ?: [NSNull null]}];

    self.loaderState = LoaderStateAbortingKeyDetection;
    // The loader may already be active at this moment -- we abort it and hand
    // over our payload block when abort did its job.
    [self abortLoader:^{
        AudioObjectID deviceId = [AudioDevice defaultOutputDevice];
        BOOL followFileRate = ([[[NSProcessInfo processInfo] environment][@"PLAYEM_FIXED_DEVICE_RATE"] length] == 0);
        Float64 targetRate = sourceRate;
        if (!followFileRate) {
            Float64 highest = [AudioDevice highestSupportedSampleRateForDevice:deviceId];
            if (highest > 0) {
                targetRate = highest;
            } else {
                Float64 current = [AudioDevice sampleRateForDevice:deviceId];
                if (current > 0) {
                    targetRate = current;
                }
            }
        }
        // Reflect intended render rate/length early so visuals/UI scale correctly before decode completes.
        if (targetRate > 0) {
            lazySample.renderedSampleRate = targetRate;
            if (lazySample.fileSampleRate > 0 && lazySample.source.length > 0) {
                double factor = targetRate / lazySample.fileSampleRate;
                unsigned long long predictedFrames = (unsigned long long) llrint((double) lazySample.source.length * factor);
                lazySample.renderedLength = predictedFrames;
                lazySample.sampleFormat = (SampleFormat){.channels = lazySample.sampleFormat.channels, .rate = (long) targetRate};
            }
        }
        // Try to switch to a new rate, if needed.
        [AudioDevice switchDevice:deviceId toSampleRate:targetRate timeout:3.0 completion:^(BOOL done) {
            NSLog(@"loading new sample from %@ to match %.1f kHz device rate ...", context.path, targetRate);
            Float64 deviceRate = [AudioDevice sampleRateForDevice:deviceId];

            // We now know the device rate to be used in our pipeline, lets tell the world.
            [[NSNotificationCenter defaultCenter] postNotificationName:kPlaybackGraphChanged
                                                                object:weakSelf.audioController
                                                              userInfo:@{kGraphChangeReasonKey : @"deviceRate",
                                                                         kGraphChangeDeviceIdKey : @(deviceId),
                                                                         kGraphChangeDeviceRateKey : @(deviceRate)}];

            if (!done && followFileRate && ![[NSUserDefaults standardUserDefaults] boolForKey:kSkipRateMismatchWarning]) {
                NSString* deviceName = [AudioDevice nameForDevice:deviceId] ?: @"audio device";

                NSAlert* alert = [[NSAlert alloc] init];
                alert.alertStyle = NSAlertStyleInformational;
                alert.messageText = NSLocalizedString(@"alert.resample.message", @"Resample alert title");
                NSString* infoFormat = NSLocalizedString(@"alert.resample.informative_format", @"Resample alert body format");
                alert.informativeText = [NSString localizedStringWithFormat:infoFormat,
                                         sourceRate / 1000.0,
                                         deviceName,
                                         deviceRate / 1000.0];
                [alert addButtonWithTitle:NSLocalizedString(@"alert.resample.ok", @"Resample alert OK button")];

                NSButton* checkbox = [[NSButton alloc] initWithFrame:NSZeroRect];
                checkbox.buttonType = NSButtonTypeSwitch;
                checkbox.title = NSLocalizedString(@"alert.resample.dont_show_again", @"Resample alert checkbox title");
                [checkbox sizeToFit];
                NSView* accessory = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, checkbox.frame.size.width, checkbox.frame.size.height)];
                [accessory addSubview:checkbox];
                alert.accessoryView = accessory;

                __block NSButton* blockCheckbox = checkbox;
                [alert beginSheetModalForWindow:self.window
                              completionHandler:^(NSModalResponse response) {
                                  if (blockCheckbox.state == NSControlStateValueOn) {
                                      [[NSUserDefaults standardUserDefaults] setBool:YES forKey:kSkipRateMismatchWarning];
                                  }
                              }];
            }

            weakSelf.loaderState = LoaderStateDecoder;
            [weakSelf loadSample:lazySample context:context];
        }];
    }];
}

- (void)abortLoader:(void (^)(void))callback
{
    WaveWindowController* __weak weakSelf = self;

    switch (self.loaderState) {
    case LoaderStateAbortingKeyDetection:
        if (self.keySample != nil) {
            NSLog(@"attempting to abort key detection...");
            [self.keySample abortWithCallback:^{
                NSLog(@"key detector aborted, calling back...");
                NSURL* url = [self deepScanURLForSample:self.keySample.sample];
                if (url != nil) {
                    [self.browser cancelForegroundDeepScanForURL:url];
                }
                weakSelf.loaderState = LoaderStateAbortingBeatDetection;
                [weakSelf abortLoader:callback];
            }];
        } else {
            NSLog(@"key detector was not active, calling back...");
            self.loaderState = LoaderStateAbortingBeatDetection;
            [self abortLoader:callback];
        }
        break;
    case LoaderStateAbortingBeatDetection:
        if (self.beatSample != nil) {
            NSLog(@"attempting to abort beat detection...");
            [self.beatSample abortWithCallback:^{
                NSLog(@"beat detector aborted, calling back...");
                NSURL* url = [self deepScanURLForSample:self.beatSample.sample];
                if (url != nil) {
                    [self.browser cancelForegroundDeepScanForURL:url];
                }
                weakSelf.loaderState = LoaderStateAbortingDecoder;
                [weakSelf abortLoader:callback];
            }];
        } else {
            NSLog(@"beat detector was not active, calling back...");
            self.loaderState = LoaderStateAbortingDecoder;
            [self abortLoader:callback];
        }
        break;
    case LoaderStateAbortingDecoder:
        if (self.sample != nil) {
            NSLog(@"attempting to abort decoder...");
            [self.audioController decodeAbortWithCallback:^{
                NSLog(@"decoder aborted, calling back...");
                weakSelf.loaderState = LoaderStateAbortingMeta;
                [weakSelf abortLoader:callback];
            }];
        } else {
            NSLog(@"decoder wasnt active, calling back...");
            self.loaderState = LoaderStateAbortingMeta;
            [self abortLoader:callback];
        }
        break;
    case LoaderStateAbortingMeta:
        if (self.meta != nil) {
            NSLog(@"attempting to abort meta loader...");
            [self.metaController loadAbortWithCallback:^{
                NSLog(@"meta loader aborted, calling back...");
                weakSelf.loaderState = LoaderStateAborted;
                callback();
            }];
        } else {
            NSLog(@"meta loader wasnt active, calling back...");
            self.loaderState = LoaderStateAborted;
            callback();
        }
        break;
    default:
        NSLog(@"catch all states, claiming all stages aborted...");
        self.loaderState = LoaderStateAbortingKeyDetection;
        [self abortLoader:callback];
    }
}

- (NSURL*)deepScanURLForSample:(LazySample*)sample
{
    if (sample != nil && sample.source.url != nil) {
        return sample.source.url;
    }
    if (self.meta != nil && self.meta.location != nil) {
        return self.meta.location;
    }
    return nil;
}

- (void)storeForegroundAnalysisResults
{
    NSURL* url = [self deepScanURLForSample:self.sample];
    if (url == nil || self.browser == nil) {
        return;
    }

    NSNumber* duration = nil;
    if (self.sample != nil && self.sample.duration > 0.0 && (self.meta.duration == nil || self.meta.duration.doubleValue <= 0.0)) {
        duration = @(self.sample.duration * 1000.0);
    }

    NSNumber* tempo = nil;
    if (self.beatSample != nil) {
        float bpm = [self.beatSample averageTempo];
        if (bpm > 0.0f && (self.meta.tempo == nil || self.meta.tempo.doubleValue <= 0.0)) {
            tempo = @(bpm);
        }
    }

    NSString* key = nil;
    if (self.keySample != nil && self.keySample.key.length > 0 && (self.meta.key == nil || self.meta.key.length == 0)) {
        key = self.keySample.key;
    }

    [self.browser finishForegroundDeepScanForURL:url duration:duration tempo:tempo key:key];
}

- (void)loadSample:(LazySample*)sample context:(LoaderContext)context
{
    if (self.loaderState == LoaderStateAborted) {
        return;
    }
    NSLog(@"previous sample %p should get unretained now", self.sample);
    self.sample = sample;
    self.visualSample = nil;
    self.totalVisual = nil;
    self.beatSample = nil;
    self.keySample = nil;
    self.scrollingWaveViewController.beatSample = nil;
    self.scrollingWaveViewController.visualSample = nil;
    self.totalWaveViewController.beatSample = nil;
    self.totalWaveViewController.frames = 0;
    self.totalWaveViewController.visualSample = nil;

    [self setBPM:0.0];

    NSURL* deepScanURL = [self deepScanURLForSample:sample];
    if (deepScanURL != nil) {
        [self.browser beginForegroundDeepScanForURL:deepScanURL];
    }

    self.visualSample = [[VisualSample alloc] initWithSample:sample pixelPerSecond:kPixelPerSecond tileWidth:self.scrollingWaveViewController.tileWidth];
    self.scrollingWaveViewController.visualSample = self.visualSample;
    assert(sample.renderedSampleRate > 0);

    // Ensure visuals size themselves using the actual render rate; warn if we are still at file rate in max-rate mode.
    BOOL followFileRate = ([[[NSProcessInfo processInfo] environment][@"PLAYEM_FIXED_DEVICE_RATE"] length] == 0);
    if (!followFileRate && fabs(sample.renderedSampleRate - sample.fileSampleRate) < 1.0) {
        NSLog(@"WaveWindowController: visuals created before renderedSampleRate updated (still at file rate %.1f kHz)",
              sample.fileSampleRate / 1000.0);
    }
    self.totalVisual = [[VisualSample alloc] initWithSample:sample
                                         pixelPerSecond:self.totalWaveViewController.view.bounds.size.width / sample.duration
                                              tileWidth:self.totalWaveViewController.tileWidth
                                           reducedWidth:kReducedVisualSampleWidth];

    self.totalWaveViewController.visualSample = self.totalVisual;

    self.scrollingWaveViewController.frames = sample.frames;
    self.totalWaveViewController.frames = sample.frames;

    self.scrollingWaveViewController.view.frame = CGRectMake(0.0, 0.0, self.visualSample.width, self.scrollingWaveViewController.view.bounds.size.height);

    NSTimeInterval duration = [self.visualSample.sample timeForFrame:sample.frames];
    [self.controlPanelController setKeyHidden:duration > kBeatSampleDurationThreshold];
    [self.controlPanelController setKey:@"" hint:@""];

    NSLog(@"playback starting...");

    self.loaderState = LoaderStateDecoder;
    WaveWindowController* __weak weakSelf = self;
    [self.audioController decodeAsyncWithSample:self.sample
                             notifyEarlyAtFrame:context.frame
                                       callback:^(BOOL decodeFinished, BOOL frameReached) {
        NSLog(@"decoder has something to say");
        if (decodeFinished) {
            NSLog(@"decoder done");
            [weakSelf sampleDecoded];
        } else {
            if (frameReached) {
                NSLog(@"decoder reached requested frame");
                [weakSelf.audioController playSample:sample
                                               frame:context.frame
                                              paused:!context.playing];
            } else {
                NSLog(@"never finished the decoding");
            }
       }
   }];
}

- (void)sampleDecoded
{
    BeatTrackedSample* beatSample = [[BeatTrackedSample alloc] initWithSample:self.sample];

    self.scrollingWaveViewController.beatSample = beatSample;
    self.totalWaveViewController.beatSample = beatSample;

    [self storeForegroundAnalysisResults];

    WaveWindowController* __weak weakSelf = self;

    if (self.beatSample != nil) {
        NSLog(@"beats tracking may need aborting");
        [self.beatSample abortWithCallback:^{
            [weakSelf loadBeats:beatSample];
        }];
    } else {
        [self loadBeats:beatSample];
    }
}

- (void)loadBeats:(BeatTrackedSample*)beatsSample
{
    if (self.loaderState == LoaderStateAborted) {
        return;
    }
    self.loaderState = LoaderStateBeatDetection;

    self.beatSample = beatsSample;

    WaveWindowController* __weak weakSelf = self;
    [self.beatSample trackBeatsAsyncWithCallback:^(BOOL beatsFinished) {
        WaveWindowController* strongSelf = weakSelf;
        if (strongSelf == nil) {
            return;
        }

        if (beatsFinished) {
            [strongSelf beatsTracked];
        } else {
            NSLog(@"never finished the beat tracking");
            NSURL* url = [strongSelf deepScanURLForSample:beatsSample.sample];
            if (url != nil) {
                [strongSelf.browser cancelForegroundDeepScanForURL:url];
            }
        }
    }];
}

- (void)beatsTracked
{
    [self.scrollingWaveViewController updateBeatMarkLayer];
    [self.totalWaveViewController updateBeatMarkLayer];

    [self beatEffectStart];
    [self storeForegroundAnalysisResults];

    KeyTrackedSample* keySample = [[KeyTrackedSample alloc] initWithSample:self.sample];
    WaveWindowController* __weak weakSelf = self;

    if (self.keySample != nil) {
        NSLog(@"key tracking may need aborting");
        [self.keySample abortWithCallback:^{
            [weakSelf detectKey:keySample];
        }];
    } else {
        [self detectKey:keySample];
    }
}

- (void)detectKey:(KeyTrackedSample*)keySample
{
    if (self.loaderState == LoaderStateAborted) {
        return;
    }

    self.loaderState = LoaderStateKeyDetection;

    self.keySample = keySample;
    [self.keySample trackKeyAsyncWithCallback:^(BOOL keyFinished) {
        if (keyFinished) {
            NSLog(@"key tracking finished");
            [self.controlPanelController setKey:self.keySample.key hint:self.keySample.hint];
        } else {
            NSLog(@"never finished the key tracking");
        }
        [self storeForegroundAnalysisResults];
    }];
}

@end
