//
//  WindowController.m
//  PlayEm
//
//  Created by Till Toenshoff on 29.05.20.
//  Copyright © 2020 Till Toenshoff. All rights reserved.
//

#import <AVFoundation/AVFoundation.h>
#import <MetalKit/MetalKit.h>
#import <CoreImage/CoreImage.h>
#import <AVKit/AVKit.h>
#import <IOKit/pwr_mgt/IOPM.h>
#import <MediaPlayer/MediaPlayer.h>

#import "WaveWindowController.h"
#import "AudioController.h"
#import "WaveScrollView.h"
#import "VisualSample.h"
#import "BeatTrackedSample.h"
#import "KeyTrackedSample.h"
#import "LazySample.h"
#import "BrowserController.h"
#import "PlaylistController.h"
#import "CreditsViewController.h"
#import "LoadState.h"
#import "MediaMetaData.h"
#import "ScopeRenderer.h"
#import "TileLayerDelegate.h"
#import "TotalWaveView.h"
#import "WaveView.h"
#import "UIView+Visibility.h"
#import "InfoPanel.h"
#import "TableHeaderCell.h"
#import "ControlPanelController.h"
#import "IdentifyViewController.h"
#import "Defaults.h"
#import "BeatLayerDelegate.h"
#import "WaveLayerDelegate.h"
#import "ProfilingPointsOfInterest.h"
#import "NSAlert+BetterError.h"
#import "MusicAuthenticationController.h"
#import "EnergyDetector.h"

static const float kShowHidePanelAnimationDuration = 0.3f;

static const float kPixelPerSecond = 120.0f;
static const size_t kReducedVisualSampleWidth = 8000;

const CGFloat kDefaultWindowWidth = 1280.0f;
const CGFloat kDefaultWindowHeight = 920.0f;

const CGFloat kMinWindowWidth = 465.0f;
const CGFloat kMinWindowHeight = 100.0f;    // Constraints on the subviews make this a minimum
                                            // that is never reached.
const CGFloat kMinScopeHeight = 64.0f;      // Smaller would still be ok...
const CGFloat kMinTableHeight = 0.0f;       // Just forget about it.

static const int kSplitPositionCount = 7;

typedef enum : NSUInteger {
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
} LoaderState;

os_log_t pointsOfInterest;

@interface WaveWindowController ()
{
    CGFloat splitPosition[kSplitPositionCount];
    CGFloat splitPositionMemory[kSplitPositionCount];
    CGFloat splitSelectorPositionMemory[kSplitPositionCount];
    
    BeatEventIterator _beatEffectIteratorContext;
    unsigned long long _beatEffectAtFrame;
    unsigned long long _beatEffectRampUpFrames;
    
    float _visibleBPM;
    
    BOOL _mediakeyJustJumped;
    
    LoaderState _loaderState;
}

@property (assign, nonatomic) CGFloat windowBarHeight;
@property (assign, nonatomic) CGRect smallBelowVisualsFrame;
@property (assign, nonatomic) CGFloat smallSplitter1Position;
@property (assign, nonatomic) CGFloat smallSplitter2Position;

@property (strong, nonatomic) ScopeRenderer* renderer;
@property (assign, nonatomic) CGRect preFullscreenFrame;
@property (strong, nonatomic) LazySample* sample;
@property (assign, nonatomic) BOOL inTransition;
@property (strong, nonatomic) PlaylistController* playlist;
@property (strong, nonatomic) MediaMetaData* meta;

@property (strong, nonatomic) ControlPanelController* controlPanelController;
@property (strong, nonatomic) MusicAuthenticationController* authenticator;

@property (strong, nonatomic) NSPopover* popOver;

@property (strong, nonatomic) NSWindowController* infoWindowController;
@property (strong, nonatomic) NSWindowController* identifyWindowController;
@property (strong, nonatomic) NSWindowController* aboutWindowController;

@property (strong, nonatomic) NSViewController* aboutViewController;

@property (strong, nonatomic) BeatLayerDelegate* beatLayerDelegate;
@property (strong, nonatomic) WaveLayerDelegate* waveLayerDelegate;
@property (strong, nonatomic) WaveLayerDelegate* totalWaveLayerDelegate;

//@property (strong, nonatomic) SPMediaKeyTap* keyTap;
@property (strong, nonatomic) AVRouteDetector* routeDetector;
@property (strong, nonatomic) AVRoutePickerView* pickerView;

@property (strong, nonatomic) CADisplayLink* displayLink;

@end


// FIXME: Refactor the shit out of this -- it is far too big.

@implementation WaveWindowController
{
    IOPMAssertionID _noSleepAssertionID;
    dispatch_queue_t _displayLinkQueue;
}

- (void)renderCallback:(CADisplayLink*)sender
{
    //os_signpost_interval_begin(pointsOfInterest, POICADisplayLink, "CADisplayLink");
    // Substract the latency introduced by the output device setup to compensate and get
    // video in sync with audible audio.
    const AVAudioFramePosition delta = [self.audioController totalLatency];
    AVAudioFramePosition frame = self.audioController.currentFrame >= delta ? self.audioController.currentFrame - delta : 0;
    // Add the delay until the video gets visible to the playhead position for compensation.
    frame += [self.audioController frameCountDeltaWithTimeDelta:sender.duration];

    //os_signpost_interval_begin(pointsOfInterest, POISetCurrentFrame, "SetCurrentFrame");
    self.currentFrame = frame;
    //os_signpost_interval_end(pointsOfInterest, POISetCurrentFrame, "SetCurrentFrame");
    //os_signpost_interval_end(pointsOfInterest, POICADisplayLink, "CADisplayLink");
}

- (id)init
{
    self = [super initWithWindowNibName:@""];
    if (self) {
        pointsOfInterest = os_log_create("com.toenshoff.playem", OS_LOG_CATEGORY_POINTS_OF_INTEREST);
        _noSleepAssertionID = 0;
        _loaderState = LoaderStateReady;
    }
    return self;
}

- (void)updateScopeFrame:(AVAudioFramePosition)frame
{
    _renderer.currentFrame = frame;
}

- (void)dealloc
{
    [_displayLink invalidate];
}

//- (void)setLazySample:(LazySample*)sample
//{
//    if (_lazySample == sample) {
//        return;
//    }
//    _lazySample = sample;
//    NSLog(@"sample %@ assigned", sample.description);
//}

- (void)updateSongsCount:(size_t)songs
{
    if (songs == 0) {
        _songsCount.stringValue = @"nothing";
    } else if (songs == 1) {
        _songsCount.stringValue = @"1 song";
    } else {
        _songsCount.stringValue = [NSString stringWithFormat:@"%ld songs", songs];
    }
}

- (void)beatEffectStart
{
    NSLog(@"re-starting beat effect");
    _beatEffectRampUpFrames = 0;
    _beatEffectAtFrame = [_beatSample seekToFirstBeat:&_beatEffectIteratorContext];
    
    float songTempo = floorf([_beatSample currentTempo:&_beatEffectIteratorContext]);
    float effectiveTempo = floorf(songTempo * _audioController.tempoShift);

    [self setBPM:effectiveTempo];
}

- (BOOL)beatEffectNext
{
    _beatEffectAtFrame = [_beatSample seekToNextBeat:&_beatEffectIteratorContext];
    return _beatEffectAtFrame != ULONG_LONG_MAX;
}

- (void)beatEffectRun
{
    float songTempo = floorf([_beatSample currentTempo:&_beatEffectIteratorContext]);
    float effectiveTempo = floorf(songTempo * _audioController.tempoShift);

    // FIXME: Consider moving this into a notification handler for the beat effect.
    [self setBPM:effectiveTempo];
    
    const BeatEvent* event = _beatEffectIteratorContext.currentEvent;
    NSDictionary* dict = @{
        kBeatNotificationKeyBeat:  @(event->index + 1),
        kBeatNotificationKeyStyle: @(event->style),
        kBeatNotificationKeyTempo: @(effectiveTempo),
        kBeatNotificationKeyFrame: @(event->frame),
        kBeatNotificationKeyLocalEnergy: @(event->energy),
        kBeatNotificationKeyTotalEnergy: @(_beatSample.energy.rms),
        kBeatNotificationKeyLocalPeak: @(event->peak),
        kBeatNotificationKeyTotalPeak: @(_beatSample.energy.peak),
    };
    [[NSNotificationCenter defaultCenter] postNotificationName:kBeatTrackedSampleBeatNotification object:dict];
}

#pragma mark Toolbar delegate

static const NSString* kPlaylistToolbarIdentifier = @"Playlist";
static const NSString* kIdentifyToolbarIdentifier = @"Identify";
//static const NSString* kRouteToolbarIdentifier = @"Route";

- (NSArray*)toolbarDefaultItemIdentifiers:(NSToolbar*)toolbar
{
    return @[
        NSToolbarFlexibleSpaceItemIdentifier,
//        kRouteToolbarIdentifier,
//        NSToolbarSpaceItemIdentifier,
        kIdentifyToolbarIdentifier,
        NSToolbarSpaceItemIdentifier,
        kPlaylistToolbarIdentifier
    ];
}

- (NSArray*)toolbarAllowedItemIdentifiers:(NSToolbar*)toolbar
{
    return @[
        NSToolbarFlexibleSpaceItemIdentifier,
//        kRouteToolbarIdentifier,
//        NSToolbarSpaceItemIdentifier,
        kIdentifyToolbarIdentifier,
        NSToolbarSpaceItemIdentifier,
        kPlaylistToolbarIdentifier
    ];
}

-(BOOL)validateToolbarItem:(NSToolbarItem*)toolbarItem
{
    BOOL enable = YES;
    if ([[toolbarItem itemIdentifier] isEqual:kIdentifyToolbarIdentifier]) {
        enable = _audioController.playing;
    }
    return enable;
}

- (NSSet<NSToolbarItemIdentifier> *)toolbarImmovableItemIdentifiers:(NSToolbar *)toolbar
{
    return [NSSet setWithObjects:kPlaylistToolbarIdentifier, kIdentifyToolbarIdentifier, nil];
}

- (NSToolbarItem *)toolbar:(NSToolbar *)toolbar itemForItemIdentifier:(NSToolbarItemIdentifier)itemIdentifier willBeInsertedIntoToolbar:(BOOL)flag
{
    if (itemIdentifier == kPlaylistToolbarIdentifier) {
        NSToolbarItem* item = [[NSToolbarItem alloc] initWithItemIdentifier:itemIdentifier];
        item.target = self;
        item.action = @selector(showPlaylist:);
        item.label = @"playlist";
        item.bordered = NO;
        item.image = [NSImage imageWithSystemSymbolName:@"list.bullet" accessibilityDescription:@""];
        return item;
    }
    if (itemIdentifier == kIdentifyToolbarIdentifier) {
        NSToolbarItem* item = [[NSToolbarItem alloc] initWithItemIdentifier:itemIdentifier];
        item.target = self;
        item.action = @selector(showIdentifier:);
        item.label = @"identify";
        item.bordered = NO;
        item.image = [NSImage imageWithSystemSymbolName:@"waveform.and.magnifyingglass" accessibilityDescription:@""];
        return item;
    }
    return nil;
}

#pragma mark Window lifecycle

/// Allow screen sleep.
- (BOOL)unlockScreen
{
    if (_noSleepAssertionID == 0) {
        return NO;
    }

    IOReturn ret = IOPMAssertionRelease(_noSleepAssertionID);
    NSLog(@"screen unlocked with result %d", ret);
    _noSleepAssertionID = 0;
    return ret == kIOReturnSuccess;
}

/// Prevent screen sleep.
- (BOOL)lockScreen
{
    if (_noSleepAssertionID != 0) {
        NSLog(@"already have an assertion up");
        return NO;
    }

    NSString* reason = @"projecting audio visual simulation";
    IOReturn ret = IOPMAssertionCreateWithName(kIOPMAssertionTypeNoDisplaySleep,
                                               (IOPMAssertionLevel)kIOPMAssertionLevelOn,
                                               (__bridge CFStringRef)reason,
                                               &_noSleepAssertionID);
    NSLog(@"screen locked with result %d", ret);

    return ret == kIOReturnSuccess;
}

- (void)loadWindow
{
    NSLog(@"loadWindow...");
    
    NSWindowStyleMask style = NSWindowStyleMaskTitled
    | NSWindowStyleMaskClosable
    | NSWindowStyleMaskUnifiedTitleAndToolbar
    | NSWindowStyleMaskMiniaturizable
    | NSWindowStyleMaskResizable;

    self.shouldCascadeWindows = NO;

    NSScreen* screen = [NSScreen mainScreen];
    self.window = [[NSWindow alloc] initWithContentRect:NSMakeRect((screen.frame.size.width - kDefaultWindowWidth) / 2.0,
                                                                   (screen.frame.size.height - kDefaultWindowHeight) / 2.0,
                                                                   kDefaultWindowWidth,
                                                                   kDefaultWindowHeight)
                                              styleMask:style
                                                backing:NSBackingStoreBuffered defer:YES];
    self.window.minSize = NSMakeSize(kMinWindowWidth, kMinWindowHeight);
    self.window.titlebarSeparatorStyle = NSTitlebarSeparatorStyleLine;
    self.window.titlebarAppearsTransparent = YES;
    self.window.titleVisibility = NO;
    self.window.movableByWindowBackground = YES;
    self.window.appearance = [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];
    self.window.autorecalculatesKeyViewLoop = YES;

    self.window.contentView.wantsLayer = YES;
    self.window.contentView.layer.backgroundColor = [[[Defaults sharedDefaults] backColor] CGColor];
    self.window.contentView.autoresizesSubviews = YES;
    self.window.contentView.translatesAutoresizingMaskIntoConstraints = YES;
    self.window.contentView.autoresizingMask = NSViewHeightSizable | NSViewWidthSizable;

    NSString* name = @"PlayEmMainWindow";
    [self.window setFrameUsingName:name];
    self.window.frameAutosaveName = name;
    
    NSToolbar* toolBar = [[NSToolbar alloc] init];
    toolBar.displayMode = NSToolbarDisplayModeIconOnly;
    toolBar.allowsUserCustomization = NO;
    toolBar.autosavesConfiguration = NO;
    toolBar.delegate = self;
    self.window.toolbar = toolBar;

    _beatLayerDelegate = [BeatLayerDelegate new];

    WaveWindowController* __weak weakSelf = self;
    
    self.waveLayerDelegate = [WaveLayerDelegate new];
    self.waveLayerDelegate.offsetBlock = ^CGFloat{
        return weakSelf.waveView.enclosingScrollView.documentVisibleRect.origin.x;
    };
    self.waveLayerDelegate.widthBlock = ^CGFloat{
        return weakSelf.waveView.enclosingScrollView.documentVisibleRect.size.width;
    };

    self.totalWaveLayerDelegate = [WaveLayerDelegate new];
    self.totalWaveLayerDelegate.visualSample = self.totalVisual;
    self.totalWaveLayerDelegate.offsetBlock = ^CGFloat{
        return 0.0;
    };
    self.totalWaveLayerDelegate.widthBlock = ^CGFloat{
        return weakSelf.totalView.frame.size.width;
    };

    _controlPanelController = [[ControlPanelController alloc] initWithDelegate:self];
    _controlPanelController.layoutAttribute = NSLayoutAttributeLeft;
    [self.window addTitlebarAccessoryViewController:_controlPanelController];

    _splitViewController = [NSSplitViewController new];

    [self loadViews];

    _beatLayerDelegate.waveView = _waveView;

    self.totalWaveLayerDelegate.fillColor = _waveView.color;
    self.totalWaveLayerDelegate.outlineColor = _waveView.color;

    self.waveLayerDelegate.fillColor = _waveView.color;
    self.waveLayerDelegate.outlineColor = [_waveView.color colorWithAlphaComponent:0.2];

    [self subscribeToRemoteCommands];
    
//    self.authenticator = [MusicAuthenticationController new];
//    [self.authenticator requestAppleMusicDeveloperTokenWithCompletion:^(NSString* token){
//        NSLog(@"token: %@", token);
//    }];
}

- (NSMenu*)songMenu
{
    NSMenu* menu = [NSMenu new];
    
    NSMenuItem* item = [[NSMenuItem alloc] initWithTitle:@"Play Next"
                                                  action:@selector(playNextInPlaylist:)
                                           keyEquivalent:@"n"];
    [item setKeyEquivalentModifierMask:NSEventModifierFlagCommand];
    [menu addItem:item];

    item = [[NSMenuItem alloc] initWithTitle:@"Play Later"
                                      action:@selector(playLaterInPlaylist:)
                               keyEquivalent:@"l"];
    [item setKeyEquivalentModifierMask:NSEventModifierFlagCommand];
    [menu addItem:item];

    [menu addItem:[NSMenuItem separatorItem]];

    item = [menu addItemWithTitle:@"Show Info"
                           action:@selector(showInfoForSelectedSongs:)
                    keyEquivalent:@""];
    item.target = _browser;

    [menu addItem:[NSMenuItem separatorItem]];

    item = [menu addItemWithTitle:@"Show in Finder"
                    action:@selector(showInFinder:)
             keyEquivalent:@""];
    item.target = _browser;

// TODO: allow disabling depending on the number of songs selected. Note to myself, this here is the wrong place!
//    size_t numberOfSongsSelected = ;
//    showInFinder.enabled = numberOfSongsSelected > 1;
  
    return menu;
}

/// Moves window to screen indexed by the sender's tag.
- (void)moveToOtherScreen:(id)sender
{
    NSMenuItem* item = sender;

    NSArray<NSScreen*>* screens = [NSScreen screens];
    assert(screens.count > item.tag);
    NSScreen* screen = screens[item.tag];

    NSPoint pos = NSMakePoint(NSMidX(screen.visibleFrame) - self.window.frame.size.width * 0.5,
                              NSMidY(screen.visibleFrame) - self.window.frame.size.height * 0.5);

    WaveWindowController* __weak weakSelf = self;

    [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
        [context setDuration:0.7];
        [weakSelf.window.animator setFrame:NSMakeRect(pos.x, pos.y, weakSelf.window.frame.size.width, weakSelf.window.frame.size.height) display:YES];
    } completionHandler:^{
    }];
}

/// Creates a menu when we got more than a single screen connected, allowing for moving the
/// application window to any other screen.
- (NSMenu*)dockMenu
{
    NSArray<NSScreen*>* screens = [NSScreen screens];
    if (screens.count < 2) {
        return nil;
    }
    
    NSMenuItem* item = nil;
    _dockMenu = [NSMenu new];

    for (int i=0; i < screens.count;i++) {
        NSScreen* screen = screens[i];
        if (screen == self.window.screen) {
            NSLog(@"we can spare the screen we are already on (%@)", screen.localizedName);
            continue;
        }
        item = [[NSMenuItem alloc] initWithTitle:[NSString stringWithFormat:@"􀢹 Move to %@", screen.localizedName]
                                          action:@selector(moveToOtherScreen:)
                                   keyEquivalent:@"m"];
        item.tag = i;
        [item setKeyEquivalentModifierMask:NSEventModifierFlagCommand];
        [_dockMenu addItem:item];
    }

    return _dockMenu;
}

- (void)loadViews
{
    const CGFloat totalHeight = self.window.contentView.bounds.size.height;
    
    const CGFloat totalWaveViewHeight = 46.0;
    const CGFloat scrollingWaveViewHeight = 158.0;

    const CGFloat playlistFxViewWidth = 280.0f;
    const CGFloat statusLineHeight = 14.0f;
    const CGFloat songsTableViewHeight = floor(totalHeight / 4.0f);
    const CGFloat selectorTableViewWidth = floor(self.window.contentView.bounds.size.width / 7.0f);
    const CGFloat selectorTableViewHeight = floor(totalHeight / 5.0f);
    const CGFloat selectorTableViewMinWidth = 70.0f;

    const CGFloat selectorTableViewHalfWidth = floor(selectorTableViewWidth / 2.0f);
    
    const CGFloat selectorColumnInset = 17.0;
    
    const CGFloat trackColumnWidth = 54.0f;
    const CGFloat titleColumnWidth = 220.0f;
    const CGFloat timeColumnWidth = 80.0f;
    const CGFloat artistColumnWidth = 160.0f;
    const CGFloat albumColumnWidth = 160.0f;
    const CGFloat genreColumnWidth = 110.0f;
    const CGFloat addedColumnWidth = 80.0f;
    const CGFloat tempoColumnWidth = 80.0f;
    const CGFloat keyColumnWidth = 60.0f;
    const CGFloat ratingColumnWidth = 60.0f;
    const CGFloat tagsColumnWidth = 160.0f;

    const CGFloat progressIndicatorWidth = 32.0f;
    const CGFloat progressIndicatorHeight = 32.0f;

    CGFloat scopeViewHeight = self.window.contentView.bounds.size.height - (songsTableViewHeight + selectorTableViewHeight + totalWaveViewHeight + scrollingWaveViewHeight);
    if (scopeViewHeight <= kMinScopeHeight) {
        scopeViewHeight = kMinScopeHeight;
    }
    const NSAutoresizingMaskOptions kViewFullySizeable = NSViewHeightSizable | NSViewWidthSizable;
    
    // Status Line.
    _songsCount = [[NSTextField alloc] initWithFrame:NSMakeRect(self.window.contentView.bounds.origin.x,
                                                                self.window.contentView.bounds.origin.y,
                                                                self.window.contentView.bounds.size.width,
                                                                statusLineHeight)];
    _songsCount.font = [NSFont systemFontOfSize:11.0];
    _songsCount.textColor = [[Defaults sharedDefaults] tertiaryLabelColor];
    _songsCount.bordered = NO;
    _songsCount.alignment = NSTextAlignmentCenter;
    _songsCount.selectable = NO;
    _songsCount.autoresizingMask = NSViewWidthSizable;
    _songsCount.translatesAutoresizingMaskIntoConstraints = YES;
    
    [self.window.contentView addSubview:_songsCount];

    // Below Visuals.
    CGFloat height = scopeViewHeight +
    scrollingWaveViewHeight +
    totalWaveViewHeight;

    _split = [[NSSplitView alloc] initWithFrame:NSMakeRect(self.window.contentView.bounds.origin.x,
                                                           self.window.contentView.bounds.origin.y + statusLineHeight,
                                                           self.window.contentView.bounds.size.width,
                                                           self.window.contentView.bounds.size.height - statusLineHeight)];
    _split.autoresizingMask = kViewFullySizeable;
    _split.autoresizesSubviews = YES;
    _split.dividerStyle = NSSplitViewDividerStyleThin;
    _split.delegate = self;
    _split.identifier = @"VerticalSplitterID";
    _split.translatesAutoresizingMaskIntoConstraints = YES;
    
    _belowVisuals = [[NSView alloc] initWithFrame:NSMakeRect(self.window.contentView.bounds.origin.x,
                                                             self.window.contentView.bounds.origin.y,
                                                             self.window.contentView.bounds.size.width,
                                                             height)];
    _belowVisuals.autoresizingMask = kViewFullySizeable;
    _belowVisuals.autoresizesSubviews = YES;
    _belowVisuals.wantsLayer = YES;
    _belowVisuals.translatesAutoresizingMaskIntoConstraints = YES;
    
    _totalView = [[TotalWaveView alloc] initWithFrame:NSMakeRect(_belowVisuals.bounds.origin.x,
                                                                 _belowVisuals.bounds.origin.y,
                                                                 _belowVisuals.bounds.size.width,
                                                                 totalWaveViewHeight)];
    _totalView.layerDelegate = self.totalWaveLayerDelegate;
    _totalView.autoresizingMask = NSViewWidthSizable;
    _totalView.translatesAutoresizingMaskIntoConstraints = YES;
    [_belowVisuals addSubview:_totalView];
    
    WaveScrollView* tiledSV = [[WaveScrollView alloc] initWithFrame:NSMakeRect(_belowVisuals.bounds.origin.x,
                                                                                 _belowVisuals.bounds.origin.y + totalWaveViewHeight,
                                                                                 _belowVisuals.bounds.size.width,
                                                                                 scrollingWaveViewHeight)];
    tiledSV.layerDelegate = _waveLayerDelegate;

    tiledSV.autoresizingMask = NSViewWidthSizable;
    tiledSV.drawsBackground = NO;
    tiledSV.translatesAutoresizingMaskIntoConstraints = YES;
    tiledSV.verticalScrollElasticity = NSScrollElasticityNone;

    _waveView = [[WaveView alloc] initWithFrame:tiledSV.bounds];
    _waveView.autoresizingMask = NSViewNotSizable;
    _waveView.translatesAutoresizingMaskIntoConstraints = YES;
    _waveView.waveLayerDelegate = self.waveLayerDelegate;
    _waveView.headDelegate = tiledSV;
    _waveView.color = [[Defaults sharedDefaults] regularBeamColor];
    _waveView.beatLayerDelegate = self.beatLayerDelegate;

    tiledSV.documentView = _waveView;
    [_belowVisuals addSubview:tiledSV];
    
    NSBox* line = [[NSBox alloc] initWithFrame:NSMakeRect(_belowVisuals.bounds.origin.x, _belowVisuals.bounds.origin.y + totalWaveViewHeight, _belowVisuals.bounds.size.width, 1.0)];
    line.boxType = NSBoxSeparator;
    line.autoresizingMask = NSViewWidthSizable;
    [_belowVisuals addSubview:line];

    line = [[NSBox alloc] initWithFrame:NSMakeRect(_belowVisuals.bounds.origin.x, _belowVisuals.bounds.origin.y + scrollingWaveViewHeight + totalWaveViewHeight - 1, _belowVisuals.bounds.size.width, 1.0)];
    line.boxType = NSBoxSeparator;
    line.autoresizingMask = NSViewWidthSizable;
    [_belowVisuals addSubview:line];
    
    _effectBelowPlaylist = [[NSVisualEffectView alloc] initWithFrame:NSMakeRect(_belowVisuals.bounds.size.width,
                                                                                _belowVisuals.bounds.origin.y,
                                                                                playlistFxViewWidth,
                                                                                height)];
    _effectBelowPlaylist.autoresizingMask = NSViewHeightSizable | NSViewMinXMargin;
    
    NSScrollView* sv = [[NSScrollView alloc] initWithFrame:_effectBelowPlaylist.bounds];
    sv.hasVerticalScroller = YES;
    sv.autoresizingMask = kViewFullySizeable;
    sv.drawsBackground = NO;
    _playlistTable = [[NSTableView alloc] initWithFrame:NSZeroRect];
    _playlistTable.backgroundColor = [NSColor clearColor];
    _playlistTable.autoresizingMask = kViewFullySizeable;
    _playlistTable.headerView = nil;
    _playlistTable.rowHeight = 36.0;
    _playlistTable.intercellSpacing = NSMakeSize(0.0, 0.0);

    NSTableColumn* col = [[NSTableColumn alloc] init];
    col.title = @"";
    col.identifier = @"CoverColumn";
    col.width = _playlistTable.rowHeight;
    [_playlistTable addTableColumn:col];

    col = [[NSTableColumn alloc] init];
    col.title = @"";
    col.identifier = @"TitleColumn";
    col.width = _effectBelowPlaylist.bounds.size.width - _playlistTable.rowHeight;
    [_playlistTable addTableColumn:col];

    sv.documentView = _playlistTable;
    [_effectBelowPlaylist addSubview:sv];

    ScopeView* scv = [[ScopeView alloc] initWithFrame:NSMakeRect(_belowVisuals.bounds.origin.x,
                                                                _belowVisuals.bounds.origin.y + totalWaveViewHeight + scrollingWaveViewHeight,
                                                                _belowVisuals.bounds.size.width,
                                                                scopeViewHeight)
                                              device:MTLCreateSystemDefaultDevice()];
    [_belowVisuals addSubview:scv];
    
    [_belowVisuals addConstraint:[NSLayoutConstraint constraintWithItem:scv
                                                       attribute:NSLayoutAttributeHeight
                                                       relatedBy:NSLayoutRelationGreaterThanOrEqual
                                                          toItem:nil
                                                       attribute:NSLayoutAttributeNotAnAttribute
                                                      multiplier:1.0
                                                        constant:kMinScopeHeight]];

    [_scopeView removeFromSuperview];
    _scopeView = scv;
    
    [_belowVisuals addSubview:_effectBelowPlaylist positioned:NSWindowAbove relativeTo:nil];

    _renderer = [[ScopeRenderer alloc] initWithMetalKitView:scv
                                                      color:[[Defaults sharedDefaults] lightBeamColor]
                                                   fftColor:[[Defaults sharedDefaults] fftColor]
                                                 background:[[Defaults sharedDefaults] backColor]
                                                   delegate:self];
    _renderer.level = self.controlPanelController.level;
    scv.delegate = _renderer;

    [_renderer mtkView:scv drawableSizeWillChange:scv.bounds.size];

    if (_audioController && _visualSample) {
        [_renderer play:_audioController visual:_visualSample scope:scv];
    }

    _smallScopeView = _scopeView;
    
    [_belowVisuals addSubview:_effectBelowPlaylist];
    
    [_split addArrangedSubview:_belowVisuals];
    
    ///
    /// Genre, Artist, Album, BPM, Key Tables.
    ///
    _splitSelectors = [[NSSplitView alloc] initWithFrame:NSMakeRect(_split.bounds.origin.x,
                                                                    _split.bounds.origin.y,
                                                                    _split.bounds.size.width,
                                                                    selectorTableViewHeight)];
    _splitSelectors.vertical = YES;
    _splitSelectors.delegate = self;
    _splitSelectors.identifier = @"HorizontalSplittersID";
    _splitSelectors.dividerStyle = NSSplitViewDividerStyleThin;
    
    sv = [[NSScrollView alloc] initWithFrame:NSMakeRect(  0.0,
                                                          0.0,
                                                          selectorTableViewWidth,
                                                          selectorTableViewHeight)];
    sv.hasVerticalScroller = YES;
    sv.autoresizingMask = kViewFullySizeable;
    sv.drawsBackground = NO;
    _genreTable = [[NSTableView alloc] initWithFrame:NSZeroRect];
    _genreTable.tag = VIEWTAG_GENRE;
    
    col = [[NSTableColumn alloc] init];
    col.title = @"Genre";
    col.identifier = @"Genre";
    col.width = selectorTableViewWidth - selectorColumnInset;
    col.minWidth = selectorTableViewMinWidth;
    [_genreTable addTableColumn:col];
    sv.documentView = _genreTable;
    [_splitSelectors addArrangedSubview:sv];
    [_splitSelectors addConstraint:[NSLayoutConstraint constraintWithItem:sv
                                                                attribute:NSLayoutAttributeWidth
                                                                relatedBy:NSLayoutRelationGreaterThanOrEqual
                                                                   toItem:nil
                                                                attribute:NSLayoutAttributeNotAnAttribute
                                                               multiplier:1.0
                                                                 constant:selectorTableViewMinWidth]];

    [_splitSelectors addConstraint:[NSLayoutConstraint constraintWithItem:sv
              attribute:NSLayoutAttributeHeight
              relatedBy:NSLayoutRelationGreaterThanOrEqual
              toItem:nil
              attribute:NSLayoutAttributeNotAnAttribute
              multiplier:1.0
              constant:kMinTableHeight]];

    sv = [[NSScrollView alloc] initWithFrame:NSMakeRect(0.0,
                                                        0.0,
                                                        selectorTableViewWidth,
                                                        selectorTableViewHeight)];
    sv.drawsBackground = NO;
    sv.hasVerticalScroller = YES;
    sv.autoresizingMask = kViewFullySizeable;
    _artistsTable = [[NSTableView alloc] initWithFrame:NSZeroRect];
    _artistsTable.tag = VIEWTAG_ARTISTS;

    col = [[NSTableColumn alloc] init];
    col.title = @"Artist";
    col.width = selectorTableViewWidth - selectorColumnInset;
    col.minWidth = selectorTableViewMinWidth;
    [_artistsTable addTableColumn:col];
    sv.documentView = _artistsTable;
    [_splitSelectors addArrangedSubview:sv];
    [_splitSelectors addConstraint:[NSLayoutConstraint constraintWithItem:sv
                                                                attribute:NSLayoutAttributeWidth
                                                                relatedBy:NSLayoutRelationGreaterThanOrEqual
                                                                   toItem:nil
                                                                attribute:NSLayoutAttributeNotAnAttribute
                                                               multiplier:1.0
                                                                 constant:selectorTableViewMinWidth]];

    sv = [[NSScrollView alloc] initWithFrame:NSMakeRect(0.0,
                                                        0.0,
                                                        selectorTableViewWidth,
                                                        selectorTableViewHeight)];
    sv.hasVerticalScroller = YES;
    sv.autoresizingMask = kViewFullySizeable;
    sv.drawsBackground = NO;
    _albumsTable = [[NSTableView alloc] initWithFrame:sv.bounds];
    _albumsTable.tag = VIEWTAG_ALBUMS;

    col = [[NSTableColumn alloc] init];
    col.title = @"Album";
    col.width = selectorTableViewWidth - selectorColumnInset;
    col.minWidth = selectorTableViewMinWidth;
    [_albumsTable addTableColumn:col];
    sv.documentView = _albumsTable;
    [_splitSelectors addArrangedSubview:sv];
    [_splitSelectors addConstraint:[NSLayoutConstraint constraintWithItem:sv
                                                                attribute:NSLayoutAttributeWidth
                                                                relatedBy:NSLayoutRelationGreaterThanOrEqual
                                                                   toItem:nil
                                                                attribute:NSLayoutAttributeNotAnAttribute
                                                               multiplier:1.0
                                                                 constant:selectorTableViewMinWidth]];

    sv = [[NSScrollView alloc] initWithFrame:NSMakeRect(0.0,
                                                        0.0,
                                                        selectorTableViewHalfWidth,
                                                        selectorTableViewHeight)];
    sv.hasVerticalScroller = YES;
    sv.autoresizingMask = kViewFullySizeable;
    sv.drawsBackground = NO;
    _temposTable = [[NSTableView alloc] initWithFrame:sv.bounds];
    _temposTable.tag = VIEWTAG_TEMPO;
    col = [[NSTableColumn alloc] init];
    col.title = @"BPM";
    col.width = selectorTableViewHalfWidth - selectorColumnInset;
    col.minWidth = selectorTableViewMinWidth;
    [_temposTable addTableColumn:col];
    sv.documentView = _temposTable;
    [_splitSelectors addArrangedSubview:sv];
    [_splitSelectors addConstraint:[NSLayoutConstraint constraintWithItem:sv
                                                                attribute:NSLayoutAttributeWidth
                                                                relatedBy:NSLayoutRelationGreaterThanOrEqual
                                                                   toItem:nil
                                                                attribute:NSLayoutAttributeNotAnAttribute
                                                               multiplier:1.0
                                                                 constant:selectorTableViewMinWidth]];

    sv = [[NSScrollView alloc] initWithFrame:NSMakeRect(0.0,
                                                        0.0,
                                                        selectorTableViewHalfWidth,
                                                        selectorTableViewHeight)];
    sv.hasVerticalScroller = YES;
    sv.autoresizingMask = kViewFullySizeable;
    sv.drawsBackground = NO;
    _keysTable = [[NSTableView alloc] initWithFrame:NSZeroRect];
    _keysTable.tag = VIEWTAG_KEY;
    col = [[NSTableColumn alloc] init];
    col.title = @"Key";
    col.width = selectorTableViewHalfWidth - selectorColumnInset;
    col.minWidth = selectorTableViewMinWidth;
    [_keysTable addTableColumn:col];
    sv.documentView = _keysTable;
    [_splitSelectors addArrangedSubview:sv];
    [_splitSelectors addConstraint:[NSLayoutConstraint constraintWithItem:sv
                                                                attribute:NSLayoutAttributeWidth
                                                                relatedBy:NSLayoutRelationGreaterThanOrEqual
                                                                   toItem:nil
                                                                attribute:NSLayoutAttributeNotAnAttribute
                                                               multiplier:1.0
                                                                 constant:selectorTableViewMinWidth]];

    sv = [[NSScrollView alloc] initWithFrame:NSMakeRect(0.0,
                                                        0.0,
                                                        selectorTableViewHalfWidth,
                                                        selectorTableViewHeight)];
    sv.hasVerticalScroller = YES;
    sv.autoresizingMask = kViewFullySizeable;
    sv.drawsBackground = NO;
    _ratingsTable = [[NSTableView alloc] initWithFrame:NSZeroRect];
    _ratingsTable.tag = VIEWTAG_RATING;
    col = [[NSTableColumn alloc] init];
    col.title = @"Rating";
    col.width = selectorTableViewHalfWidth - selectorColumnInset;
    col.minWidth = selectorTableViewMinWidth;
    [_ratingsTable addTableColumn:col];
    sv.documentView = _ratingsTable;
    [_splitSelectors addArrangedSubview:sv];
    [_splitSelectors addConstraint:[NSLayoutConstraint constraintWithItem:sv
                                                                attribute:NSLayoutAttributeWidth
                                                                relatedBy:NSLayoutRelationGreaterThanOrEqual
                                                                   toItem:nil
                                                                attribute:NSLayoutAttributeNotAnAttribute
                                                               multiplier:1.0
                                                                 constant:selectorTableViewMinWidth]];

    sv = [[NSScrollView alloc] initWithFrame:NSMakeRect(0.0,
                                                        0.0,
                                                        selectorTableViewHalfWidth,
                                                        selectorTableViewHeight)];
    sv.hasVerticalScroller = YES;
    sv.autoresizingMask = kViewFullySizeable;
    sv.drawsBackground = NO;
    _tagsTable = [[NSTableView alloc] initWithFrame:NSZeroRect];
    _tagsTable.tag = VIEWTAG_TAGS;
    col = [[NSTableColumn alloc] init];
    col.title = @"Tags";
    col.width = selectorTableViewWidth - selectorColumnInset;
    col.minWidth = selectorTableViewMinWidth;
    [_tagsTable addTableColumn:col];
    sv.documentView = _tagsTable;
    [_splitSelectors addArrangedSubview:sv];
    [_splitSelectors addConstraint:[NSLayoutConstraint constraintWithItem:sv
                                                                attribute:NSLayoutAttributeWidth
                                                                relatedBy:NSLayoutRelationGreaterThanOrEqual
                                                                   toItem:nil
                                                                attribute:NSLayoutAttributeNotAnAttribute
                                                               multiplier:1.0
                                                                 constant:selectorTableViewMinWidth]];

    [_split addArrangedSubview:_splitSelectors];
    
    ///
    /// Songs Table.
    ///
    sv = [[NSScrollView alloc] initWithFrame:NSMakeRect(_split.bounds.origin.x,
                                                        _split.bounds.origin.y,
                                                        _split.bounds.size.width,
                                                        songsTableViewHeight)];
    sv.hasVerticalScroller = YES;
    sv.drawsBackground = NO;
    sv.autoresizingMask = kViewFullySizeable;
    _songsTable = [[NSTableView alloc] initWithFrame:NSZeroRect];
    _songsTable.tag = VIEWTAG_SONGS;
    _songsTable.menu = [self songMenu];
    _songsTable.autoresizingMask = NSViewNotSizable;
    _songsTable.columnAutoresizingStyle = NSTableViewLastColumnOnlyAutoresizingStyle;
    _songsTable.allowsMultipleSelection = YES;
    [_songsTable selectionHighlightStyle];

    col = [[NSTableColumn alloc] initWithIdentifier:kSongsColTrackNumber];
    col.title = @"Track";
    col.width = trackColumnWidth - selectorColumnInset;
    col.minWidth = (trackColumnWidth - selectorColumnInset) / 2.0f;
    col.resizingMask = NSTableColumnUserResizingMask;
    col.sortDescriptorPrototype = [[NSSortDescriptor alloc] initWithKey:@"track" ascending:YES selector:@selector(compare:)];
    [_songsTable addTableColumn:col];
    
    col = [[NSTableColumn alloc] initWithIdentifier:kSongsColTitle];
    col.title = @"Title";
    col.width = titleColumnWidth - selectorColumnInset;
    col.minWidth = (titleColumnWidth - selectorColumnInset) / 2.0f;
    col.resizingMask = NSTableColumnUserResizingMask;
    col.sortDescriptorPrototype = [[NSSortDescriptor alloc] initWithKey:@"title" ascending:YES selector:@selector(compare:)];
    [_songsTable addTableColumn:col];

    col = [[NSTableColumn alloc] initWithIdentifier:kSongsColTime];
    col.title = @"Time";
    col.width = timeColumnWidth - selectorColumnInset;
    col.minWidth = (timeColumnWidth - selectorColumnInset) / 2.0;
    col.resizingMask = NSTableColumnUserResizingMask;
    col.sortDescriptorPrototype = [[NSSortDescriptor alloc] initWithKey:@"duration" ascending:YES selector:@selector(compare:)];
    [_songsTable addTableColumn:col];

    col = [[NSTableColumn alloc] initWithIdentifier:kSongsColArtist];
    col.title = @"Artist";
    col.width = artistColumnWidth - selectorColumnInset;
    col.minWidth = (artistColumnWidth - selectorColumnInset) / 2.0;
    col.resizingMask = NSTableColumnUserResizingMask;
    col.sortDescriptorPrototype = [[NSSortDescriptor alloc] initWithKey:@"artist" ascending:YES selector:@selector(compare:)];
    [_songsTable addTableColumn:col];

    col = [[NSTableColumn alloc] initWithIdentifier:kSongsColAlbum];
    col.title = @"Album";
    col.width = albumColumnWidth - selectorColumnInset;
    col.minWidth = (albumColumnWidth - selectorColumnInset) / 2.0;
    col.resizingMask = NSTableColumnUserResizingMask;
    col.sortDescriptorPrototype = [[NSSortDescriptor alloc] initWithKey:@"album" ascending:YES selector:@selector(compare:)];
    [_songsTable addTableColumn:col];

    col = [[NSTableColumn alloc] initWithIdentifier:kSongsColGenre];
    col.title = @"Genre";
    col.width = genreColumnWidth - selectorColumnInset;
    col.minWidth = (genreColumnWidth - selectorColumnInset) / 2.0;
    col.resizingMask = NSTableColumnAutoresizingMask | NSTableColumnUserResizingMask;
    col.sortDescriptorPrototype = [[NSSortDescriptor alloc] initWithKey:@"genre" ascending:YES selector:@selector(compare:)];
    [_songsTable addTableColumn:col];

    col = [[NSTableColumn alloc] initWithIdentifier:kSongsColAdded];
    col.title = @"Added";
    col.width = addedColumnWidth - selectorColumnInset;
    col.minWidth = (addedColumnWidth - selectorColumnInset) / 2.0;
    col.resizingMask = NSTableColumnUserResizingMask;
    col.sortDescriptorPrototype = [[NSSortDescriptor alloc] initWithKey:@"added" ascending:YES selector:@selector(compare:)];
    [_songsTable addTableColumn:col];

    col = [[NSTableColumn alloc] initWithIdentifier:kSongsColTempo];
    col.title = @"Tempo";
    col.width = tempoColumnWidth - selectorColumnInset;
    col.minWidth = (tempoColumnWidth - selectorColumnInset) / 2.0;
    col.resizingMask = NSTableColumnUserResizingMask;
    col.sortDescriptorPrototype = [[NSSortDescriptor alloc] initWithKey:@"tempo" ascending:YES selector:@selector(compare:)];
    [_songsTable addTableColumn:col];

    col = [[NSTableColumn alloc] initWithIdentifier:kSongsColKey];
    col.title = @"Key";
    col.width = keyColumnWidth - selectorColumnInset;
    col.minWidth = (keyColumnWidth - selectorColumnInset) / 2.0;
    col.resizingMask = NSTableColumnUserResizingMask;
    col.sortDescriptorPrototype = [[NSSortDescriptor alloc] initWithKey:@"key" ascending:YES selector:@selector(compare:)];
    [_songsTable addTableColumn:col];

    col = [[NSTableColumn alloc] initWithIdentifier:kSongsColRating];
    col.title = @"Rating";
    col.width = ratingColumnWidth - selectorColumnInset;
    col.minWidth = (ratingColumnWidth - selectorColumnInset) / 2.0;
    col.resizingMask = NSTableColumnUserResizingMask;
    col.sortDescriptorPrototype = [[NSSortDescriptor alloc] initWithKey:@"rating" ascending:YES selector:@selector(compare:)];
    [_songsTable addTableColumn:col];

    col = [[NSTableColumn alloc] initWithIdentifier:kSongsColTags];
    col.title = @"Tags";
    col.minWidth = (tagsColumnWidth - selectorColumnInset) / 2.0;
    col.resizingMask = NSTableColumnAutoresizingMask;
    col.sortDescriptorPrototype = [[NSSortDescriptor alloc] initWithKey:@"tags" ascending:YES selector:@selector(compare:)];
    [_songsTable addTableColumn:col];

    sv.documentView = _songsTable;
    [_split addArrangedSubview:sv];

    [_split addConstraint:[NSLayoutConstraint constraintWithItem:sv
              attribute:NSLayoutAttributeHeight
              relatedBy:NSLayoutRelationGreaterThanOrEqual
              toItem:nil
              attribute:NSLayoutAttributeNotAnAttribute
              multiplier:1.0
              constant:kMinTableHeight]];

    [self.window.contentView addSubview:_split];
    
    _progress = [[NSProgressIndicator alloc] initWithFrame:NSMakeRect((self.window.contentView.bounds.size.width - progressIndicatorWidth) / 2.0,
                                                                      (self.window.contentView.bounds.size.height - progressIndicatorHeight) / 4.0,
                                                                      progressIndicatorWidth,
                                                                      progressIndicatorHeight)];
    _progress.style = NSProgressIndicatorStyleSpinning;
    _progress.displayedWhenStopped = NO;
    _progress.autoresizingMask =  NSViewNotSizable | NSViewMinXMargin | NSViewMaxXMargin| NSViewMinYMargin | NSViewMaxYMargin;
    
    [self.window.contentView addSubview:_progress];
    
    _trackRenderProgress = [[NSProgressIndicator alloc] initWithFrame:NSMakeRect((self.window.contentView.bounds.size.width - progressIndicatorWidth) / 2.0,
                                                                                 (self.window.contentView.bounds.size.height - progressIndicatorHeight) / 2.0,
                                                                                 progressIndicatorWidth,
                                                                                 progressIndicatorHeight)];
    _trackRenderProgress.style = NSProgressIndicatorStyleSpinning;
    _trackRenderProgress.displayedWhenStopped = NO;
    _trackRenderProgress.autoresizingMask = NSViewNotSizable | NSViewMinXMargin | NSViewMaxXMargin| NSViewMinYMargin | NSViewMaxYMargin;
    
    [self.window.contentView addSubview:_trackRenderProgress];

    _trackLoadProgress = [[NSProgressIndicator alloc] initWithFrame:NSMakeRect((self.window.contentView.bounds.size.width - progressIndicatorWidth) / 2.0,
                                                                               (self.window.contentView.bounds.size.height - progressIndicatorHeight) / 2.0,
                                                                               progressIndicatorWidth,
                                                                               progressIndicatorHeight)];
    _trackLoadProgress.style = NSProgressIndicatorStyleSpinning;
    _trackLoadProgress.displayedWhenStopped = NO;
    _trackLoadProgress.autoresizingMask =  NSViewNotSizable | NSViewMinXMargin | NSViewMaxXMargin| NSViewMinYMargin | NSViewMaxYMargin;
    
    [self.window.contentView addSubview:_trackLoadProgress];
}

- (void)windowDidLoad
{
    [super windowDidLoad];
    
    NSUserDefaults* userDefaults = [NSUserDefaults standardUserDefaults];
    
    // The following assignments can not happen earlier - they rely on the fact
    // that the controls in question have a parent view / window.
    _split.autosaveName = @"VerticalSplitters";
    _splitSelectors.autosaveName = @"HorizontalSplitters";
    
    _genreTable.autosaveName = @"GenresTable";
    _artistsTable.autosaveName = @"ArtistsTable";
    _albumsTable.autosaveName = @"AlbumsTable";
    _temposTable.autosaveName = @"TemposTable";
    _keysTable.autosaveName = @"KeysTable";
    _ratingsTable.autosaveName = @"RatingsTable";
    _tagsTable.autosaveName = @"TagsTable";
    _songsTable.autosaveName = @"SongsTable";

    // Replace the header cell in all of the main tables on this view.
    NSArray<NSTableView*>* fixupTables = @[ _songsTable,
                                            _genreTable,
                                            _artistsTable,
                                            _albumsTable,
                                            _temposTable,
                                            _keysTable,
                                            _ratingsTable,
                                            _tagsTable];
    for (NSTableView *table in fixupTables) {
        for (NSTableColumn *column in [table tableColumns]) {
            TableHeaderCell* cell = [[TableHeaderCell alloc] initTextCell:[[column headerCell] stringValue]];
            [column setHeaderCell:cell];
        }
        table.backgroundColor = [NSColor clearColor];
        table.style = NSTableViewStylePlain;
        table.autosaveTableColumns = YES;
        table.allowsEmptySelection = NO;
        table.headerView.wantsLayer = YES;
    }

    _browser = [[BrowserController alloc] initWithGenresTable:_genreTable
                                                 artistsTable:_artistsTable
                                                  albumsTable:_albumsTable
                                                  temposTable:_temposTable
                                                   songsTable:_songsTable
                                                    keysTable:_keysTable
                                                  ratingsTable:_ratingsTable
                                                    tagsTable:_tagsTable
                                                     delegate:self];
    for (NSTableView *table in fixupTables) {
        table.delegate = _browser;
        table.dataSource = _browser;
    }
    
    _sample = nil;
    
    _inTransition = NO;
    
    _effectBelowPlaylist.material = NSVisualEffectMaterialMenu;
    _effectBelowPlaylist.blendingMode = NSVisualEffectBlendingModeWithinWindow;
    _effectBelowPlaylist.alphaValue = 0.0f;
    
    _smallBelowVisualsFrame = _belowVisuals.frame;
    
    {
        CIFilter* colorFilter = [CIFilter filterWithName:@ "CIFalseColor"];
        
        [colorFilter setDefaults];
        
        CIColor* color1 = [CIColor colorWithRed:(CGFloat)0xFA / 255.0
                                          green:(CGFloat)0xB0 / 255.0
                                           blue:(CGFloat)0x59 / 255.0
                                          alpha:(CGFloat)0.4];
        
        CIColor* color2 = [CIColor colorWithRed:(CGFloat)0xFA / 255.0
                                          green:(CGFloat)0xB0 / 255.0
                                           blue:(CGFloat)0x59 / 255.0
                                          alpha:(CGFloat)1.0];
        
        [colorFilter setValue:color1 forKey:@"inputColor0"];
        [colorFilter setValue:color2 forKey:@"inputColor1"];
        
        self.trackLoadProgress.contentFilters = @[colorFilter];
    }
    
    {
        CIFilter* colorFilter = [CIFilter filterWithName:@ "CIFalseColor"];
        
        [colorFilter setDefaults];
        
        CIColor* color1 = [CIColor colorWithRed:(CGFloat)0x00 / 255.0
                                          green:(CGFloat)0x00 / 255.0
                                           blue:(CGFloat)0x00 / 255.0
                                          alpha:(CGFloat)0.0];
        
        CIColor* color2 = [CIColor colorWithRed:(CGFloat)0xFA / 255.0
                                          green:(CGFloat)0xB0 / 255.0
                                           blue:(CGFloat)0x59 / 255.0
                                          alpha:(CGFloat)1.0];
        
        [colorFilter setValue:color1 forKey:@"inputColor0"];
        [colorFilter setValue:color2 forKey:@"inputColor1"];
        
        self.trackRenderProgress.contentFilters = @[colorFilter];
    }
    
    CGRect rect = CGRectMake(0.0, 0.0, self.window.frame.size.width, self.window.frame.size.height);
    CGRect contentRect = [self.window contentRectForFrameRect:rect];
    _windowBarHeight = self.window.frame.size.height - contentRect.size.height;
    
    [self.window registerForDraggedTypes:[NSArray arrayWithObjects: NSPasteboardTypeFileURL, NSPasteboardTypeSound, nil]];
    self.window.delegate = self;
    
    _playlist = [[PlaylistController alloc] initWithPlaylistTable:_playlistTable
                                                         delegate:self];
    
    [self.renderer loadMetalWithView:self.scopeView];

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(ScrollViewStartsLiveScrolling:) name:@"NSScrollViewWillStartLiveScrollNotification" object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(ScrollViewEndsLiveScrolling:) name:@"NSScrollViewDidEndLiveScrollNotification" object:nil];
    
    NSNumber* fullscreenValue = [userDefaults objectForKey:@"fullscreen"];
    if ([fullscreenValue boolValue]) {
        [self.window toggleFullScreen:self];
    }
}

- (void)setupDisplayLink
{
    NSLog(@"setting up display link...");
    if (_displayLink != nil) {
        [_displayLink invalidate];
        _displayLink = nil;
    }
    _displayLink = [self.window displayLinkWithTarget:self selector:@selector(renderCallback:)];
    _displayLink.preferredFrameRateRange = CAFrameRateRangeMake(60.0, 120.0, 120.0);
    [_displayLink addToRunLoop:[NSRunLoop currentRunLoop]
                       forMode:NSRunLoopCommonModes];
}

/**
 This method is used in the process of finding a target for an action method. If this
 NSResponder instance does not itself respondsToSelector:action, then
 supplementalTargetForAction:sender: is called. This method should return an object which
 responds to the action; if this responder does not have a supplemental object that does
 that, the implementation of this method should call super's
 supplementalTargetForAction:sender:.
 
 NSResponder's implementation returns nil.
**/
- (id)supplementalTargetForAction:(SEL)action sender:(id)sender
{
    NSLog(@"action: %@", NSStringFromSelector(action));
    id target = [super supplementalTargetForAction:action sender:sender];

    if (target != nil) {
        return target;
    }
    
    NSArray* controllers = @[_browser, _playlist];

    for (NSResponder *childViewController in controllers) {
        target = [NSApp targetForAction:action to:childViewController from:sender];

        if (![target respondsToSelector:action]) {
            target = [target supplementalTargetForAction:action sender:sender];
        }

        if ([target respondsToSelector:action]) {
            return target;
        }
    }

    return nil;
}

- (void)windowWillClose:(NSNotification *)notification
{
    NSUserDefaults* userDefaults = [NSUserDefaults standardUserDefaults];

    BOOL isFullscreen = (self.window.styleMask & NSWindowStyleMaskFullScreen) == NSWindowStyleMaskFullScreen;
    [userDefaults setObject:[NSNumber numberWithBool:isFullscreen] forKey:@"fullscreen"];
    
    // Take a snapshot of the current playback state.
    BOOL playing = [_audioController playing];
    NSNumber* playingValue = [NSNumber numberWithBool:playing];
    AVAudioFramePosition currentFrame = 0;

    currentFrame = [_audioController currentFrame];

    NSNumber* currentFrameValue = [NSNumber numberWithLongLong:currentFrame];
    
    NSDocumentController* dc = [NSDocumentController sharedDocumentController];
    NSURL* recentURL = dc.recentDocumentURLs[0];
    NSLog(@"current file:%@", [recentURL filePathURL]);
    NSLog(@"current frame: %lld", currentFrame);
    
    NSError* error = nil;

    NSURLComponents* components = [NSURLComponents componentsWithString:[recentURL.filePathURL absoluteString]];
    NSMutableArray<NSURLQueryItem*>* queryItems = [NSMutableArray array];
    NSURLQueryItem* item = [NSURLQueryItem queryItemWithName:@"CurrentFrame" value:[currentFrameValue stringValue]];
    [queryItems addObject:item];
    item = [NSURLQueryItem queryItemWithName:@"Playing" value:[playingValue stringValue]];
    [queryItems addObject:item];
    components.queryItems = queryItems;
    
    recentURL = [components URL];

    NSData* bookmark = nil;
    bookmark = [recentURL bookmarkDataWithOptions:NSURLBookmarkCreationWithSecurityScope
                   includingResourceValuesForKeys:nil
                                    relativeToURL:nil // Make it app-scoped
                                            error:&error];
    if (error) {
        NSLog(@"Error creating bookmark for URL (%@): %@", recentURL, error);
        [NSApp presentError:error];
    }
    [userDefaults setObject:bookmark forKey:@"bookmark"];
    
    // Abort all the async operations that might be in flight.
    [_audioController decodeAbortWithCallback:^{}];
    //[BeatTrackedSample abort];
    // Finish playback, if anything was ongoing.
}

- (void)windowDidEndLiveResize:(NSNotification *)notification
{
    // The scope view takes are of itself by reacting to `viewDidEndLiveResize`.
//    [_waveView ];
    
    [_totalVisual setPixelPerSecond:_totalView.bounds.size.width / _sample.duration];
    [_totalView resize];
    [_totalView refresh];
}

- (void)windowDidResize:(NSNotification *)notification
{
    NSLog(@"windowDidResize with `ContentView` to height %f", self.window.contentView.bounds.size.height);
    NSLog(@"windowDidResize with `BelowVisuals` to height %f", _belowVisuals.bounds.size.height);

    NSSize newSize = NSMakeSize(_belowVisuals.bounds.size.width,
                                _belowVisuals.bounds.size.height - (_totalView.bounds.size.height + _waveView.bounds.size.height));
    if (_scopeView.frame.size.width != newSize.width ||
        _scopeView.frame.size.height != newSize.height) {
        NSLog(@"windowDidResize with `ScopeView` to %f x %f", newSize.width, newSize.height);
        [_renderer mtkView:_scopeView drawableSizeWillChange:newSize];
    } else {
        NSLog(@"windowDidResize with `ScopeView` remaining as is");
    }
}

- (void)windowWillEnterFullScreen:(NSNotification *)notification
{
    NSLog(@"windowWillEnterFullScreen: %@\n", notification);
    _inTransition = YES;

    _preFullscreenFrame = self.window.frame;
    _smallBelowVisualsFrame = _belowVisuals.frame;
}

- (void)windowDidEnterFullScreen:(NSNotification *)notification
{
    NSLog(@"windowDidEnterFullScreen\n");
    _inTransition = NO;
}

- (void)windowWillExitFullScreen:(NSNotification *)notification
{
    NSLog(@"windowWillExitFullScreen\n");
    _inTransition = YES;
}

- (void)windowDidExitFullScreen:(NSNotification *)notification
{
    NSLog(@"windowDidExitFullScreen\n");
    _inTransition = NO;
}

- (NSArray *)customWindowsToEnterFullScreenForWindow:(NSWindow *)window
{
    return [NSArray arrayWithObjects:[self window], nil];
}

- (NSArray *)customWindowsToExitFullScreenForWindow:(NSWindow *)window
{
    return [NSArray arrayWithObjects:[self window], nil];
}

- (void)window:(NSWindow *)window startCustomAnimationToEnterFullScreenWithDuration:(NSTimeInterval)duration
{
    NSLog(@"startCustomAnimationToEnterFullScreenWithDuration\n");
    
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
        [context setDuration:duration];
        [self relayoutAnimated:YES];
        [window.animator setFrame:[[NSScreen mainScreen] frame] display:YES];
    } completionHandler:^{
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        [window setStyleMask:([window styleMask] | NSWindowStyleMaskFullScreen)];
        //[window.contentView addSubview:self.belowVisuals];
        self.belowVisuals.frame = NSMakeRect(0.0f, 0.0f, window.screen.frame.size.width, window.screen.frame.size.height);
        //[self putScopeViewWithFrame:NSMakeRect(0.0f, 0.0f, window.screen.frame.size.width, window.screen.frame.size.height) onView:window.contentView];
        [CATransaction commit];
    }];
}

- (void)window:(NSWindow *)window startCustomAnimationToExitFullScreenWithDuration:(NSTimeInterval)duration
{
    NSLog(@"startCustomAnimationToExitFullScreenWithDuration\n");
    
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
        [context setDuration:duration];
        [window.animator setFrame:_preFullscreenFrame display:YES];
        [self relayoutAnimated:NO];
    } completionHandler:^{
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        [window setStyleMask:([window styleMask] & ~NSWindowStyleMaskFullScreen)];
        //[self.split replaceSubview:<#(nonnull NSView *)#> with:<#(nonnull NSView *)#>];
        //self.belowVisuals.frame = self.smallBelowVisualsFrame;
        //[self putScopeViewWithFrame:self.smallBelowVisualsFrame onView:self.belowVisuals];
        [CATransaction commit];
    }];
}

- (void)relayoutAnimated:(bool)toFullscreen
{
    // Rebuild the view stack and only show the scope view in fullscreen.
    _genreTable.enclosingScrollView.animator.hidden = toFullscreen ? YES : NO;
    _albumsTable.enclosingScrollView.animator.hidden = toFullscreen ? YES : NO;
    _artistsTable.enclosingScrollView.animator.hidden = toFullscreen ? YES : NO;
    _temposTable.enclosingScrollView.animator.hidden = toFullscreen ? YES : NO;
    _keysTable.enclosingScrollView.animator.hidden = toFullscreen ? YES : NO;
    _ratingsTable.enclosingScrollView.animator.hidden = toFullscreen ? YES : NO;
    _tagsTable.enclosingScrollView.animator.hidden = toFullscreen ? YES : NO;

    if (toFullscreen) {
        memcpy(splitPositionMemory, splitPosition, sizeof(CGFloat) * kSplitPositionCount);
        // Restore the old positions.
        [_splitSelectors setPosition:splitSelectorPositionMemory[0] ofDividerAtIndex:0];
        [_splitSelectors setPosition:splitSelectorPositionMemory[1] ofDividerAtIndex:1];
        [_splitSelectors setPosition:splitSelectorPositionMemory[2] ofDividerAtIndex:2];
        [_splitSelectors setPosition:splitSelectorPositionMemory[3] ofDividerAtIndex:3];
        [_splitSelectors setPosition:splitSelectorPositionMemory[4] ofDividerAtIndex:4];
        [_splitSelectors setPosition:splitSelectorPositionMemory[5] ofDividerAtIndex:5];
        [_splitSelectors setPosition:splitSelectorPositionMemory[6] ofDividerAtIndex:6];
    }

    [_splitSelectors adjustSubviews];

    _splitSelectors.animator.hidden = toFullscreen ? YES : NO;

    _songsTable.enclosingScrollView.animator.hidden = toFullscreen ? YES : NO;

    if (!toFullscreen) {
        // We quickly stash the position memory for making sure the first position set
        // can trash the stored positions immediately.
        CGFloat positions[kSplitPositionCount];
        memcpy(positions, splitPositionMemory, sizeof(CGFloat) * kSplitPositionCount);
        [_split setPosition:splitPositionMemory[0] ofDividerAtIndex:0];
        [_split setPosition:splitPositionMemory[1] ofDividerAtIndex:1];
    }
    [_split adjustSubviews];
    NSLog(@"relayout to fullscreen %X\n", toFullscreen);
}

- (void)setPlaybackActive:(BOOL)active
{
    [self loadProgress:_controlPanelController.autoplayProgress state:LoadStateStopped value:0.0];
    
    _controlPanelController.playPause.state = active ? NSControlStateValueOn : NSControlStateValueOff;
    //_browser.playPause = active ? NSControlStateValueOn : NSControlStateValueOff;
}

- (void)showInfoForMetas:(NSArray*)metas
{
    NSApplication* sharedApplication = [NSApplication sharedApplication];

    InfoPanelController* info = [[InfoPanelController alloc] initWithMetas:metas];
    info.delegate = self;

    self.infoWindowController = [NSWindowController new];
    NSWindow* window = [NSWindow windowWithContentViewController:info];
    window.titleVisibility = NSWindowTitleHidden;
    window.movableByWindowBackground = YES;
    window.titlebarAppearsTransparent = YES;
    window.appearance = sharedApplication.mainWindow.appearance;
    [window standardWindowButton:NSWindowZoomButton].hidden = YES;
    [window standardWindowButton:NSWindowCloseButton].hidden = YES;
    [window standardWindowButton:NSWindowMiniaturizeButton].hidden = YES;
    _infoWindowController.window = window;

    [sharedApplication runModalForWindow:_infoWindowController.window];
}

- (void)showInfoForCurrentSong:(id)sender
{
    [_browser showInfoForCurrentSong:sender];
}

- (void)showPlaylist:(id)sender
{
    BOOL isShow = _effectBelowPlaylist.alphaValue <= 0.05f;
    
//    NSArray<NSToolbarItem*>* items = self.window.toolbar.visibleItems;
//    for (NSToolbarItem* item in items) {
//        NSToolbarItemIdentifier ident = item.itemIdentifier;
//        if ([ident isEqualToString:kPlaylistToolbarIdentifier]) {
//        }
//    }
    
//    kPlaylistToolbarIdentifier
    
    if (isShow) {
        _effectBelowPlaylist.alphaValue = 1.0f;
    }
    
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
        //CGFloat maxX = 0;
        [context setDuration:kShowHidePanelAnimationDuration];
        if (isShow) {
            _effectBelowPlaylist.animator.frame = NSMakeRect(self.window.contentView.frame.origin.x + self.window.contentView.frame.size.width - _effectBelowPlaylist.frame.size.width,
                                                             _effectBelowPlaylist.frame.origin.y,
                                                             _effectBelowPlaylist.frame.size.width,
                                                             _effectBelowPlaylist.frame.size.height);
        } else {
            _effectBelowPlaylist.animator.frame = NSMakeRect(self.window.contentView.frame.origin.x + self.window.contentView.frame.size.width,
                                                             _effectBelowPlaylist.frame.origin.y,
                                                             _effectBelowPlaylist.frame.size.width,
                                                             _effectBelowPlaylist.frame.size.height);
        }
    } completionHandler:^{
        if (!isShow) {
            self.effectBelowPlaylist.alphaValue = 0.0f;
        }
    }];
}

- (void)showAbout:(id)sender
{
    NSPanel* window = nil;

    if (_aboutWindowController == nil) {
        self.aboutWindowController = [NSWindowController new];
    }
    if (_aboutViewController == nil) {
        self.aboutViewController = [[CreditsViewController alloc] init];
        [_aboutViewController view];
        NSPanel* panel = [NSPanel windowWithContentViewController:_aboutViewController];
        window = panel;
        window.styleMask &= ~(NSWindowStyleMaskResizable | NSWindowStyleMaskMiniaturizable);
        window.titleVisibility = NSWindowTitleHidden;
        window.movableByWindowBackground = YES;
        window.titlebarAppearsTransparent = YES;
        window.level = NSFloatingWindowLevel;
        _aboutWindowController.window = window;
    } else {
        window = (NSPanel*)self.aboutWindowController.window;
    }
    [window setFloatingPanel:YES];
    [window makeKeyAndOrderFront:nil];
}

- (void)showIdentifier:(id)sender
{
    NSApplication* sharedApplication = [NSApplication sharedApplication];
    
    if (_identifyWindowController == nil) {
        self.identifyWindowController = [NSWindowController new];
    }

    NSPanel* window;
    if (_iffy == nil) {
        self.iffy = [[IdentifyViewController alloc] initWithAudioController:_audioController];
        [_iffy view];
        NSPanel* panel = [NSPanel windowWithContentViewController:_iffy];
        window = panel;
        window.styleMask &= ~NSWindowStyleMaskResizable | NSWindowStyleMaskTitled;
        window.styleMask |= NSWindowStyleMaskUtilityWindow;
        window.titleVisibility = NSWindowTitleHidden;
        window.movableByWindowBackground = YES;
        window.titlebarAppearsTransparent = YES;
        window.level = NSFloatingWindowLevel;
        window.appearance = sharedApplication.mainWindow.appearance;
        [window standardWindowButton:NSWindowZoomButton].hidden = NO;
        [window standardWindowButton:NSWindowCloseButton].hidden = NO;
        [window standardWindowButton:NSWindowMiniaturizeButton].hidden = YES;
        _identifyWindowController.window = window;
    } else {
        window = (NSPanel*)_identifyWindowController.window;
    }
    [window setFloatingPanel:YES];
    [window makeKeyAndOrderFront:nil];
}

- (void)ScrollViewStartsLiveScrolling:(NSNotification*)notification
{
    if (notification.object == self.waveView.enclosingScrollView) {
        [self.waveView userInitiatedScrolling];
    }
}

- (void)ScrollViewEndsLiveScrolling:(NSNotification*)notification
{
    if (notification.object == self.waveView.enclosingScrollView) {
        [self.waveView userEndsScrolling];
    }
}

- (void)setBPM:(float)bpm
{
    if (_visibleBPM == bpm) {
        return;
    }
    NSString* display = bpm < 0.5f ? @"" : [NSString stringWithFormat:@"%3.0f BPM", floorf(bpm)];

    _controlPanelController.bpm.stringValue = display;

    NSNumber* number = [NSNumber numberWithFloat:bpm];
    [[NSNotificationCenter defaultCenter] postNotificationName:kBeatTrackedSampleTempoChangeNotification object:number];

    _visibleBPM = bpm;
}

- (void)setCurrentFrame:(unsigned long long)frame
{
    [self updateScopeFrame:frame];

    if (_waveView.currentFrame == frame) {
        return;
    }
    os_signpost_interval_begin(pointsOfInterest, POIStringStuff, "StringStuff");
    _controlPanelController.duration.stringValue = [_sample beautifulTimeWithFrame:_sample.frames - frame];
    _controlPanelController.time.stringValue = [_sample beautifulTimeWithFrame:frame];
    os_signpost_interval_end(pointsOfInterest, POIStringStuff, "StringStuff");

    os_signpost_interval_begin(pointsOfInterest, POIWaveViewSetCurrentFrame, "WaveViewSetCurrentFrame");
    _waveView.currentFrame = frame;
    os_signpost_interval_end(pointsOfInterest, POIWaveViewSetCurrentFrame, "WaveViewSetCurrentFrame");

    os_signpost_interval_begin(pointsOfInterest, POITotalViewSetCurrentFrame, "TotalViewSetCurrentFrame");
    _totalView.currentFrame = frame;
    os_signpost_interval_end(pointsOfInterest, POITotalViewSetCurrentFrame, "TotalViewSetCurrentFrame");

    os_signpost_interval_begin(pointsOfInterest, POIBeatStuff, "BeatStuff");
    if (_beatSample.ready) {
        if (frame + _beatEffectRampUpFrames > _beatEffectAtFrame) {
            [self beatEffectRun];
            while (frame + _beatEffectRampUpFrames > _beatEffectAtFrame) {
                if (![self beatEffectNext]) {
                    NSLog(@"end of beats reached - wont fire again until reset");
                    return;
                }
            };
        }
    }
    os_signpost_interval_end(pointsOfInterest, POIBeatStuff, "BeatStuff");
}

- (IBAction)loadITunesLibrary:(id)sender
{
    [_browser loadITunesLibrary];
}

#pragma mark - Splitter delegate

- (BOOL)splitView:(NSSplitView *)splitView canCollapseSubview:(NSView *)subview
{
    return YES;
}

- (void)splitViewDidResizeSubviews:(NSNotification *)notification
{
/*
     A notification that is posted to the default notification center by NSSplitView when a
     split view has just resized its subviews either as a result of its own resizing or during
     the dragging of one of its dividers by the user.
     Starting in Mac OS 10.5, if the notification is being sent because the user is dragging
     a divider, the notification's user info dictionary contains an entry whose key is
     @"NSSplitViewDividerIndex" and whose value is an NSInteger-wrapping NSNumber that is
     the index of the divider being dragged. Starting in Mac OS 12.0, the notification will
     contain the user info dictionary during resize and layout events as well.
*/
    NSSplitView* sv = notification.object;
    NSNumber* indexNumber = notification.userInfo[@"NSSplitViewDividerIndex"];

    if (indexNumber == nil) {
        return;
    }

    if (sv == _splitSelectors) {
        switch(indexNumber.intValue) {
            case 0:
                splitSelectorPositionMemory[0] = _genreTable.enclosingScrollView.bounds.size.width;
                break;
            case 1:
                splitSelectorPositionMemory[1] = _artistsTable.enclosingScrollView.bounds.size.width;
                break;
            case 2:
                splitSelectorPositionMemory[2] = _albumsTable.enclosingScrollView.bounds.size.width;
                break;
            case 3:
                splitSelectorPositionMemory[3] = _temposTable.enclosingScrollView.bounds.size.width;
                break;
            case 4:
                splitSelectorPositionMemory[4] = _keysTable.enclosingScrollView.bounds.size.width;
                break;
            case 5:
                splitSelectorPositionMemory[5] = _ratingsTable.enclosingScrollView.bounds.size.width;
                break;
            case 6:
                splitSelectorPositionMemory[6] = _tagsTable.enclosingScrollView.bounds.size.width;
                break;
        }
    } else if (sv == _split) {
        switch(indexNumber.intValue) {
            case 0: {
                NSSize newSize = NSMakeSize(_belowVisuals.bounds.size.width,
                                            _belowVisuals.bounds.size.height - (_totalView.bounds.size.height + _waveView.bounds.size.height));

                if (_scopeView.frame.size.width != newSize.width ||
                    _scopeView.frame.size.height != newSize.height) {
                    NSLog(@"splitViewDidResizeSubviews with `ScopeView` to %f x %f", newSize.width, newSize.height);
                    [_renderer mtkView:_scopeView drawableSizeWillChange:newSize];
                } else {
                    NSLog(@"splitViewDidResizeSubviews with `ScopeView` remaining as is");
                }
                break;
            }
        }
        splitPosition[0] = _belowVisuals.bounds.size.height;
        splitPosition[1] = _belowVisuals.bounds.size.height + _splitSelectors.bounds.size.height;
    }
}

#pragma mark - Media Remote Commands

- (NSArray*)remoteCommands
{
    MPRemoteCommandCenter *cc = [MPRemoteCommandCenter sharedCommandCenter];
    return @[
        cc.playCommand,
        cc.pauseCommand,
        cc.stopCommand,
        cc.togglePlayPauseCommand,
        cc.nextTrackCommand,
        cc.previousTrackCommand,
        cc.skipForwardCommand,
        cc.skipBackwardCommand,
        cc.changePlaybackPositionCommand,
    ];
}

- (MPRemoteCommandHandlerStatus )remoteCommandEvent:(MPRemoteCommandEvent*)event
{
    MPRemoteCommandCenter *cc = [MPRemoteCommandCenter sharedCommandCenter];
    if (event.command == cc.playCommand) {
        [_audioController play];
        return MPRemoteCommandHandlerStatusSuccess;
    }
    if (event.command == cc.pauseCommand) {
        [_audioController pause];
        return MPRemoteCommandHandlerStatusSuccess;
    }
    if (event.command == cc.togglePlayPauseCommand) {
        [_audioController togglePause];
        return MPRemoteCommandHandlerStatusSuccess;
    }
    if (event.command == cc.changePlaybackPositionCommand) {
        MPChangePlaybackPositionCommandEvent *positionEvent = (MPChangePlaybackPositionCommandEvent*)event;
        [self seekToTime:positionEvent.positionTime + 1];
        return MPRemoteCommandHandlerStatusSuccess;
    }
    if (event.command == cc.nextTrackCommand) {
        [self playPrevious:self];
        return MPRemoteCommandHandlerStatusSuccess;
    }
    if (event.command == cc.previousTrackCommand) {
        [self playPrevious:self];
        return MPRemoteCommandHandlerStatusSuccess;
    }
    if (event.command == cc.skipForwardCommand) {
        [self seekToTime:_audioController.currentTime + 10.0];
        return MPRemoteCommandHandlerStatusSuccess;
    }
    if (event.command == cc.skipBackwardCommand) {
        [self seekToTime:_audioController.currentTime - 10.0];
        return MPRemoteCommandHandlerStatusSuccess;
    }

    NSLog(@"%s was not able to handle remote control event '%s'",
          __PRETTY_FUNCTION__,
          [event.description UTF8String]);

    return MPRemoteCommandHandlerStatusCommandFailed;
}

/// Adds this controller as a target for remote commands as issued by
/// the media menu and keys.
- (void)subscribeToRemoteCommands
{
    MPRemoteCommandCenter* commandCenter = [MPRemoteCommandCenter sharedCommandCenter];
    
    commandCenter.ratingCommand.enabled = NO;
    commandCenter.likeCommand.enabled = NO;
    commandCenter.dislikeCommand.enabled = NO;
    commandCenter.bookmarkCommand.enabled = NO;
    commandCenter.enableLanguageOptionCommand.enabled = NO;
    commandCenter.disableLanguageOptionCommand.enabled = NO;
    commandCenter.seekForwardCommand.enabled = NO;
    commandCenter.seekBackwardCommand.enabled = NO;
    commandCenter.skipForwardCommand.preferredIntervals = @[@(10.0)];
    commandCenter.skipBackwardCommand.preferredIntervals = @[@(10.0)];
    for (MPRemoteCommand* command in [self remoteCommands]) {
        [command addTarget:self action:@selector(remoteCommandEvent:)];
    }
}

- (void)unsubscribeFromRemoteCommands
{
    [MPNowPlayingInfoCenter defaultCenter].nowPlayingInfo = nil;

    for (MPRemoteCommand* command in [self remoteCommands]) {
        [command removeTarget:self];
    }
}

#pragma mark - Document lifecycle

- (IBAction)openDocument:(id)sender
{
    NSOpenPanel* openDlg = [NSOpenPanel openPanel];
    [openDlg setCanChooseFiles:YES];
    [openDlg setCanChooseDirectories:YES];
    openDlg.appearance = self.window.appearance;

    if ([openDlg runModal] == NSModalResponseOK) {
        for(NSURL* url in [openDlg URLs]) {
            [self loadDocumentFromURL:[WaveWindowController encodeQueryItemsWithUrl:url frame:0LL playing:YES]
                                 meta:nil];
        }
    } else {
        return;
    }
}

- (void)AudioControllerPlaybackStateChange:(NSNotification*)notification
{
    NSString* state = notification.object;
    if ([state isEqualToString:kPlaybackStateStarted]) {
        [self audioControllerPlaybackStarted];
    } else if ([state isEqualToString:kPlaybackStatePlaying]) {
        [self audioControllerPlaybackPlaying];
    } else if ([state isEqualToString:kPlaybackStatePaused]) {
        [self audioControllerPlaybackPaused];
    } else if ([state isEqualToString:kPlaybackStateEnded]) {
        [self audioControllerPlaybackEnded];
    }
}

- (BOOL)loadDocumentFromURL:(NSURL*)url meta:(MediaMetaData*)meta
{
    NSError* error = nil;
    if (_audioController == nil) {
        _audioController = [AudioController new];

        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(AudioControllerPlaybackStateChange:) name:kAudioControllerChangedPlaybackStateNotification object:nil];
    }
    
    if (url == nil) {
        return NO;
    }
    
    BOOL playing = NO;
    long long frame = 0LL;
    
    NSLog(@"loadDocumentFromURL url: %@ - known meta: %@", url, meta);

    NSURLComponents* components = [NSURLComponents componentsWithURL:url
                                             resolvingAgainstBaseURL:YES];

    NSPredicate* predicate = [NSPredicate predicateWithFormat:@"name=%@", @"CurrentFrame"];
    NSURLQueryItem* item = [[components.queryItems filteredArrayUsingPredicate:predicate] firstObject];
    frame = [[item value] longLongValue];
    
    if (frame < 0) {
        NSLog(@"not fixing a bug here due to lazyness -- hope it happens rarely");
        frame = 0;
    }

    predicate = [NSPredicate predicateWithFormat:@"name=%@", @"Playing"];
    item = [[components.queryItems filteredArrayUsingPredicate:predicate] firstObject];
    playing = [[item value] boolValue];
    if (![url checkResourceIsReachableAndReturnError:&error]) {
        if (error != nil) {
            NSAlert* alert = [NSAlert betterAlertWithError:error action:@"load" url:url];
            [alert runModal];
        }
        return NO;
    }

    _loaderState = LoaderStateMeta;
    if (playing) {
        [self loadProgress:_controlPanelController.autoplayProgress state:LoadStateInit value:0.0];
    }

    if (meta == nil) {
        // Not being able to get metadata is not a reason to error out.
        meta = [MediaMetaData mediaMetaDataWithURL:url error:&error];
    }

    LazySample* lazySample = [[LazySample alloc] initWithPath:url.path error:&error];
    if (lazySample == nil) {
        if (error) {
            NSAlert* alert = [NSAlert betterAlertWithError:error action:@"read" url:url];
            [alert runModal];
        }
        return NO;
    }
    [[NSDocumentController sharedDocumentController] noteNewRecentDocumentURL:url];

    WaveWindowController* __weak weakSelf = self;

    self->_loaderState = LoaderStateAbortingKeyDetection;
    // The loader may already be active at this moment -- we abort it and hand over
    // our payload block when abort did its job.
    [self abortLoader:^{
        NSLog(@"loading new sample from URL:%@ ...", url);
        self->_loaderState = LoaderStateDecoder;
        [weakSelf loadLazySample:lazySample];
        [weakSelf setMeta:meta];

        NSLog(@"playback starting...");
        [self->_audioController playSample:lazySample
                                     frame:frame
                                    paused:!playing];
    }];

    return YES;
}

- (void)abortLoader:(void (^)(void))callback
{
    WaveWindowController* __weak weakSelf = self;

    switch(_loaderState) {
        case LoaderStateAbortingKeyDetection:
            if (_keySample != nil) {
                NSLog(@"attempting to abort key detection...");
                [self->_keySample abortWithCallback:^{
                    NSLog(@"key detector aborted, calling back...");
                    self->_loaderState = LoaderStateAbortingBeatDetection;
                    [weakSelf abortLoader:callback];
                }];
            } else {
                NSLog(@"key detector was not active, calling back...");
                _loaderState = LoaderStateAbortingBeatDetection;
                [self abortLoader:callback];
            }
            break;
        case LoaderStateAbortingBeatDetection:
            if (_beatSample != nil) {
                NSLog(@"attempting to abort beat detection...");
                [self->_beatSample abortWithCallback:^{
                    NSLog(@"beat detector aborted, calling back...");
                    self->_loaderState = LoaderStateAbortingDecoder;
                    [weakSelf abortLoader:callback];
                }];
            } else {
                NSLog(@"beat detector was not active, calling back...");
                _loaderState = LoaderStateAbortingDecoder;
                [self abortLoader:callback];
            }
            break;
        case LoaderStateAbortingDecoder:
            if (_sample != nil) {
                NSLog(@"attempting to abort decoder...");
                [self->_audioController decodeAbortWithCallback:^{
                    NSLog(@"decoder aborted, calling back...");
                    self->_loaderState = LoaderStateAborted;
                    callback();
                }];
            } else {
                NSLog(@"decoder wasnt active, calling back...");
                _loaderState = LoaderStateAborted;
                callback();
            }
            break;
        default:
            NSLog(@"catch all states, claiming all stages aborted...");
            _loaderState = LoaderStateAbortingKeyDetection;
            [self abortLoader:callback];
    }
}

- (void)loadLazySample:(LazySample*)sample
{
    WaveWindowController* __weak weakSelf = self;

    if (_loaderState == LoaderStateAborted) {
        return;
    }
    //NSLog(@"Retain count is %ld", CFGetRetainCount((__bridge CFTypeRef)_sample));

    NSLog(@"previous sample %p should get unretained now", _sample);
    _sample = sample;
    _waveLayerDelegate.visualSample = nil;
    _visualSample = nil;
    _totalVisual = nil;
    _beatSample = nil;
    _keySample = nil;
    _beatLayerDelegate.beatSample = nil;
    
    [self setBPM:0.0];

    [self loadTrackState:LoadStateInit value:0.0];
    [self loadTrackState:LoadStateStopped value:0.0];

    _visualSample = [[VisualSample alloc] initWithSample:sample
                                          pixelPerSecond:kPixelPerSecond
                                               tileWidth:kDirectWaveViewTileWidth];

    //[_controlPanelController reset];
    
    _waveLayerDelegate.visualSample = self.visualSample;

    _totalVisual = [[VisualSample alloc] initWithSample:sample
                                         pixelPerSecond:_totalView.bounds.size.width / sample.duration
                                              tileWidth:kTotalWaveViewTileWidth
                                           reducedWidth:kReducedVisualSampleWidth];

    _totalWaveLayerDelegate.visualSample = _totalVisual;

    _loaderState = LoaderStateDecoder;
    
    [_audioController decodeAsyncWithSample:sample callback:^(BOOL decodeFinished){
        if (decodeFinished) {
            [weakSelf lazySampleDecoded];
       } else {
            NSLog(@"never finished the decoding");
        }
    }];
    
    _waveView.frames = sample.frames;
    _totalView.frames = sample.frames;
    _waveView.frame = CGRectMake(0.0,
                                 0.0,
                                 self.visualSample.width,
                                 self.waveView.bounds.size.height);
    [_totalView refresh];
    
    NSTimeInterval duration = [self.visualSample.sample timeForFrame:sample.frames];
    [_controlPanelController setKeyHidden:duration > kBeatSampleDurationThreshold];
    [_controlPanelController setKey:@"" hint:@""];
}

- (void)lazySampleDecoded
{
    BeatTrackedSample* beatSample = [[BeatTrackedSample alloc] initWithSample:_sample
                                                               framesPerPixel:self.visualSample.framesPerPixel];
    _beatLayerDelegate.beatSample = beatSample;

    WaveWindowController* __weak weakSelf = self;

    if (_beatSample != nil) {
        NSLog(@"beats tracking may need aborting");
        [_beatSample abortWithCallback:^{
            [weakSelf loadBeats:beatSample];
        }];
    } else {
        [self loadBeats:beatSample];
    }
}

- (void)loadBeats:(BeatTrackedSample*)beatsSample
{
    if (_loaderState == LoaderStateAborted) {
        return;
    }
    
    [self loadProgress:_controlPanelController.beatProgress
                 state:LoadStateInit
                 value:0.0];

    _loaderState = LoaderStateBeatDetection;

    _beatSample = beatsSample;

    WaveWindowController* __weak weakSelf = self;

    [_beatSample trackBeatsAsyncWithCallback:^(BOOL beatsFinished){
        if (beatsFinished) {
            [weakSelf beatsTracked];
        } else {
            NSLog(@"never finished the beat tracking");
        }
        [self loadProgress:self.controlPanelController.beatProgress
                     state:LoadStateStopped
                     value:0.0];
    }];
}

- (void)beatsTracked
{
    [self.waveView invalidateTiles];
    [self beatEffectStart];

    KeyTrackedSample* keySample = [[KeyTrackedSample alloc] initWithSample:_sample];
    WaveWindowController* __weak weakSelf = self;

    if (_keySample != nil) {
        NSLog(@"key tracking may need aborting");
        [_keySample abortWithCallback:^{
            [weakSelf detectKey:keySample];
        }];
    } else {
        [self detectKey:keySample];
    }
}

- (void)detectKey:(KeyTrackedSample*)keySample
{
    if (_loaderState == LoaderStateAborted) {
        return;
    }

    [self loadProgress:_controlPanelController.keyProgress state:LoadStateInit value:0.0];

    _loaderState = LoaderStateKeyDetection;

    _keySample = keySample;
    [_keySample trackKeyAsyncWithCallback:^(BOOL keyFinished){
        if (keyFinished) {
            NSLog(@"key tracking finished");
            [self->_controlPanelController setKey:self->_keySample.key hint:self->_keySample.hint];
        } else {
            NSLog(@"never finished the key tracking");
        }
        [self loadProgress:self.controlPanelController.keyProgress state:LoadStateStopped value:0.0];
    }];
}

- (void)setPlaybackState:(MPNowPlayingPlaybackState)state
{
    MPNowPlayingInfoCenter* center = [MPNowPlayingInfoCenter defaultCenter];
    center.playbackState = state;
}

- (void)setNowPlayingWithMeta:(MediaMetaData*)meta
{
    NSMutableDictionary *songInfo = [[NSMutableDictionary alloc] init];
    [songInfo setObject:meta.title == nil ? @"" : meta.title forKey:MPMediaItemPropertyTitle];
    [songInfo setObject:meta.artist == nil ? @"" : meta.artist forKey:MPMediaItemPropertyArtist];
    [songInfo setObject:meta.album == nil ? @"" : meta.album forKey:MPMediaItemPropertyAlbumTitle];
    if (meta.track != nil) {
        [songInfo setObject:meta.track forKey:MPMediaItemPropertyAlbumTrackNumber];
    }
    if (meta.tracks != nil) {
        [songInfo setObject:meta.tracks forKey:MPMediaItemPropertyAlbumTrackCount];
    }
    if (meta.genre != nil) {
        [songInfo setObject:meta.genre forKey:MPMediaItemPropertyGenre];
    }
    if (meta.year != nil) {
        [songInfo setObject:meta.year forKey:MPMediaItemPropertyReleaseDate];
    }
    if (meta.artwork) {
        NSImage* artworkImage = [meta imageFromArtwork];
        MPMediaItemArtwork* artwork = [[MPMediaItemArtwork alloc] initWithBoundsSize:artworkImage.size requestHandler:^(CGSize size){
            return artworkImage;
        }];
        [songInfo setObject:artwork forKey:MPMediaItemPropertyArtwork];
    }
    
    [songInfo setObject:@(_audioController.expectedDuration) forKey:MPMediaItemPropertyPlaybackDuration];
    [songInfo setObject:@(_audioController.currentTime) forKey:MPNowPlayingInfoPropertyElapsedPlaybackTime];
    [songInfo setObject:@(_audioController.tempoShift) forKey:MPNowPlayingInfoPropertyPlaybackRate];
    
    MPNowPlayingInfoCenter* center = [MPNowPlayingInfoCenter defaultCenter];
    center.nowPlayingInfo = songInfo;
}

- (void)setMeta:(MediaMetaData*)meta
{
    _meta = meta;

    [self.playlist setCurrent:meta];
    
    // Update meta data in playback box.
    _controlPanelController.meta = meta;
    
    [_browser setCurrentMeta:meta];
    [self setNowPlayingWithMeta:meta];
}

- (void)updateRemotePosition
{
    NSMutableDictionary *songInfo = [NSMutableDictionary dictionaryWithDictionary:[[MPNowPlayingInfoCenter defaultCenter] nowPlayingInfo]];
    [songInfo setObject:@(_audioController.expectedDuration) forKey:MPMediaItemPropertyPlaybackDuration];
    [songInfo setObject:@(_audioController.currentTime) forKey:MPNowPlayingInfoPropertyElapsedPlaybackTime];
    [[MPNowPlayingInfoCenter defaultCenter] setNowPlayingInfo:songInfo];
}

#pragma mark - Drag & Drop

- (NSDragOperation)draggingEntered:(id <NSDraggingInfo>)sender
{
    NSPasteboard* pboard = [sender draggingPasteboard];
    NSDragOperation sourceDragMask = [sender draggingSourceOperationMask];
 
    if ( [[pboard types] containsObject:NSPasteboardTypeFileURL] ) {
        if (sourceDragMask & NSDragOperationGeneric) {
            return NSDragOperationGeneric;
        } else if (sourceDragMask & NSDragOperationLink) {
            return NSDragOperationLink;
        } else if (sourceDragMask & NSDragOperationCopy) {
            return NSDragOperationCopy;
        }
    }
    return NSDragOperationNone;
}

- (BOOL)prepareForDragOperation:(id<NSDraggingInfo>)sender
{
   return YES;
}

- (BOOL)performDragOperation:(id <NSDraggingInfo>)sender
{
    NSPasteboard* pboard = [sender draggingPasteboard];

    if (pboard.pasteboardItems.count <= 1) {
        NSURL* url = [NSURL URLFromPasteboard:pboard];
        if (url) {
            if ([self loadDocumentFromURL:[WaveWindowController encodeQueryItemsWithUrl:url frame:0LL playing:YES] meta:nil]) {
                return YES;
            }
        }
    }
    return NO;
}

#pragma mark - Mouse events

- (void)mouseDown:(NSEvent*)event
{
    NSPoint locationInWindow = [event locationInWindow];

    NSPoint location = [_waveView convertPoint:locationInWindow fromView:nil];
    if (NSPointInRect(location, _waveView.bounds)) {
        unsigned long long seekTo = (_visualSample.sample.frames * location.x ) / _waveView.frame.size.width;
        NSLog(@"mouse down in wave view %f:%f -- seeking to %lld\n", location.x, location.y, seekTo);
        [self seekToFrame:seekTo];
        if (![_audioController playing]) {
            NSLog(@"not playing, he claims...");
            [_audioController play];
        }
        return;
    }

    location = [_totalView convertPoint:locationInWindow fromView:nil];
    if (NSPointInRect(location, _totalView.bounds)) {
        unsigned long long seekTo = (_totalVisual.sample.frames * location.x ) / _totalView.frame.size.width;
        NSLog(@"mouse down in total wave view %f:%f -- seeking to %lld\n", location.x, location.y, seekTo);
        [self seekToFrame:seekTo];
        if (![_audioController playing]) {
            NSLog(@"not playing, he claims...");
            [_audioController play];
        }
    }
}

- (void)rightMouseDown:(NSEvent*)event
{
    NSPoint locationInWindow = [event locationInWindow];
    NSPoint location = [_waveView convertPoint:locationInWindow fromView:nil];
    if (NSPointInRect(location, _waveView.bounds)) {
        // snap to cursor
        return;
    }
}

- (void)mouseDragged:(NSEvent *)event
{
    NSPoint locationInWindow = [event locationInWindow];
    NSPoint location = [_waveView convertPoint:locationInWindow fromView:nil];
    if (NSPointInRect(location, _waveView.bounds)) {
        unsigned long long seekTo = (_visualSample.sample.frames * location.x ) / _waveView.frame.size.width;
        NSLog(@"mouse down in wave view %f:%f -- seeking to %lld\n", location.x, location.y, seekTo);
        [self seekToFrame:seekTo];
        if (![_audioController playing]) {
            NSLog(@"not playing, he claims...");
            [_audioController play];
        }
        return;
    }
    location = [_totalView convertPoint:locationInWindow fromView:nil];
    if (NSPointInRect(location, _totalView.bounds)) {
        unsigned long long seekTo = (_totalVisual.sample.frames * location.x ) / _totalView.frame.size.width;
        NSLog(@"mouse down in total wave view %f:%f -- seeking to %lld\n", location.x, location.y, seekTo);
        [self seekToFrame:seekTo];
        if (![_audioController playing]) {
            NSLog(@"not playing, he claims...");
            [_audioController play];
        }
    }
}

#pragma mark - Browser delegate

- (MediaMetaData*)currentSongMeta
{
    return _meta;
}

- (void)addToPlaylistNext:(MediaMetaData*)meta
{
    [_playlist addNext:meta];
}

- (void)addToPlaylistLater:(MediaMetaData*)meta
{
    [_playlist addLater:meta];
}

+ (NSURL*)encodeQueryItemsWithUrl:(NSURL*)url frame:(unsigned long long)frame playing:(BOOL)playing
{
    NSNumber* currentFrameValue = @(frame);
    NSNumber* playingValue = @(playing);

    NSURLComponents* components = [NSURLComponents componentsWithString:[url.filePathURL absoluteString]];
    NSMutableArray<NSURLQueryItem*>* queryItems = [NSMutableArray array];

    NSURLQueryItem* item = [NSURLQueryItem queryItemWithName:@"CurrentFrame" value:[currentFrameValue stringValue]];
    [queryItems addObject:item];

    item = [NSURLQueryItem queryItemWithName:@"Playing" value:[playingValue stringValue]];
    [queryItems addObject:item];
    components.queryItems = queryItems;
    return [components URL];
}

- (void)browseSelectedUrl:(NSURL*)url meta:(MediaMetaData*)meta
{
    [self loadDocumentFromURL:[WaveWindowController encodeQueryItemsWithUrl:url frame:0LL playing:YES] meta:meta];
}

- (void)loadProgress:(NSProgressIndicator*)progress state:(LoadState)state value:(double)value
{
    switch(state) {
        case LoadStateInit:
            progress.hidden = NO;
            progress.indeterminate = YES;
            [progress startAnimation:self];
            break;
        case LoadStateStarted:
            [progress stopAnimation:self];
            progress.indeterminate = NO;
            progress.doubleValue = 0.0;
            break;
        case LoadStateLoading:
            progress.doubleValue = value;
            break;
        case LoadStateStopped:
            progress.doubleValue = 1.0;
            progress.hidden = YES;
            break;
    }
}

- (void)loadLibraryState:(LoadState)state
{
    [self loadLibraryState:state value:0.0];
}

- (void)loadLibraryState:(LoadState)state value:(double)value
{
    [self loadProgress:self.progress state:state value:value];
}

- (void)loadTrackState:(LoadState)state
{
    [self loadTrackState:state value:0.0];
}

- (void)loadTrackState:(LoadState)state value:(double)value
{
    [self loadProgress:self.trackLoadProgress state:state value:value];
}

- (void)renderTrackState:(LoadState)state
{
    [self renderTrackState:state value:0.0];
}

- (void)renderTrackState:(LoadState)state value:(double)value
{
    [self loadProgress:self.trackRenderProgress state:state value:value];
}

#pragma mark - Audio delegate

- (void)startVisuals
{
    // Start beats.
    [self beatEffectStart];

    // Start the scope renderer.
    [_renderer play:_audioController visual:_visualSample scope:_scopeView];

    [self setupDisplayLink];
}

- (void)audioControllerPlaybackStarted
{
    NSLog(@"audioControllerPlaybackStarted");
    [self startVisuals];
    [_playlist playedMeta:_meta];
}

- (void)audioControllerPlaybackPlaying
{
    NSLog(@"audioControllerPlaybackPlaying");
    // Make state obvious to user.
    [self setPlaybackActive:YES];

    [_playlist setPlaying:YES];

    // Mark the current song in the browser for we are playing.
    [_browser setNowPlayingWithMeta:_meta];

    // Tell the control bar item for media playback about our song.
    [self setNowPlayingWithMeta:_meta];
    [self setPlaybackState:MPNowPlayingPlaybackStatePlaying];

    [self updateRemotePosition];

    [self lockScreen];
}

- (void)audioControllerPlaybackPaused
{
    NSLog(@"audioControllerPlaybackPaused");
    // Make state obvious to user.
    [self setPlaybackActive:NO];
    [_playlist setPlaying:NO];
    [_browser setPlaying:NO];

    [self setNowPlayingWithMeta:_meta];
    [self setPlaybackState:MPNowPlayingPlaybackStatePaused];
    [self updateRemotePosition];

    [self unlockScreen];
}

- (void)audioControllerPlaybackEnded
{
    NSLog(@"audioControllerPlaybackEnded");
    // Make state obvious to user.
    [self setPlaybackActive:NO];
    [_playlist setPlaying:NO];
    [_browser setPlaying:NO];

    [self setNowPlayingWithMeta:_meta];
    [self setPlaybackState:MPNowPlayingPlaybackStateStopped];
    [self updateRemotePosition];

    [self unlockScreen];

    // Stop the scope rendering.
    [_renderer stop:_scopeView];

    if (_controlPanelController.loop.state == NSControlStateValueOn) {
        [_audioController play];
        return;
    }
    
    [self playNext:self];
}

#pragma mark - Control Panel delegate

- (void)playNext:(id)sender
{
    // Do we have something in our playlist?
    MediaMetaData* meta = [_playlist nextItem];
    if (meta == nil) {
        // Then maybe we can just get the next song from the songs browser list.
        // Find the topmost selected song and use that one to play next.
        meta = [self.browser nextSong];
    }
    if (meta == nil) {
        [_audioController pause];
        return;
    }
    [self loadDocumentFromURL:[WaveWindowController
                               encodeQueryItemsWithUrl:meta.location
                               frame:0LL
                               playing:YES] meta:meta];
}

- (void)playPrevious:(id)sender
{
//    // Do we have something in our playlist?
//    MediaMetaData* meta = [_playlist previousItem];
//    if (meta == nil) {
//        // Then maybe we can just get the next song from the songs browser list.
//        //- (IBAction)playNext:(id)sender
//        // Find the topmost selected song and use that one to play next.
//        [self stop];
//        return;
//    }
//
//    [self loadDocumentFromURL:[WaveWindowController encodeQueryItemsWithUrl:meta.location frame:0LL playing:YES] meta:meta];
}

- (void)volumeChange:(id)sender
{
    _audioController.outputVolume = _controlPanelController.volumeSlider.doubleValue;
}

- (void)volumeIncrease:(id)sender
{
    double newValue = _controlPanelController.volumeSlider.doubleValue + (_controlPanelController.volumeSlider.maxValue / 16);
    if (newValue > _controlPanelController.volumeSlider.maxValue) {
        newValue = _controlPanelController.volumeSlider.maxValue;
    }
    _controlPanelController.volumeSlider.doubleValue = newValue;
}

- (void)volumeDecrease:(id)sender
{
    double newValue = _controlPanelController.volumeSlider.doubleValue - (_controlPanelController.volumeSlider.maxValue / 16);
    if (newValue < 0.0) {
        newValue = 0.0;
    }
    _controlPanelController.volumeSlider.doubleValue = newValue;
}

- (void)tempoChange:(id)sender
{
    _audioController.tempoShift = _controlPanelController.tempoSlider.doubleValue;
}

- (void)resetTempo:(id)sender
{
    _audioController.tempoShift = 1.0;
    _controlPanelController.tempoSlider.doubleValue = 1.0;
}

- (void)togglePause:(id)sender
{
    [_audioController togglePause];
}

- (void)seekToTime:(NSTimeInterval)time
{
    _audioController.currentTime = time;
    [self beatEffectStart];
    [self updateRemotePosition];
}

- (void)seekToFrame:(unsigned long long)frame
{
    _audioController.currentFrame = frame;
    [self beatEffectStart];
    [self updateRemotePosition];
}

- (IBAction)skip1Beat:(id)sender
{
    const unsigned long long nextBeatFrame = [self.beatSample currentEventFrame:&_beatEffectIteratorContext];
    NSLog(@"next beat will be at %lld", nextBeatFrame);
    _audioController.currentFrame = nextBeatFrame;
    [self updateRemotePosition];
}

- (IBAction)repeat1Beat:(id)sender
{
    BeatEventIterator iter;
 
    const unsigned long long nextBeatFrame = [self.beatSample currentEventFrame:&_beatEffectIteratorContext];
 
    [BeatTrackedSample copyIteratorFromSource:&_beatEffectIteratorContext destination:&iter];
    [self.beatSample seekToPreviousBeat:&iter];
    const unsigned long long previousBeatFrame = [self.beatSample seekToPreviousBeat:&iter];
    NSLog(@"previous beat was at %lld - next beat is at %lld", previousBeatFrame, nextBeatFrame);
    _audioController.currentFrame = previousBeatFrame;
    [self updateRemotePosition];
}

- (IBAction)skip1Bar:(id)sender
{
    BeatEventIterator iter;
 
    [BeatTrackedSample copyIteratorFromSource:&_beatEffectIteratorContext destination:&iter];
    
    unsigned long long frame = iter.currentEvent->frame;
    while ((iter.currentEvent->style & BeatEventStyleBar) != BeatEventStyleBar) {
        frame = [self.beatSample seekToNextBeat:&iter];
    };
    NSLog(@"next bar is at %lld", frame);
    _audioController.currentFrame = frame;
    [self updateRemotePosition];
}

- (IBAction)repeat1Bar:(id)sender
{
    BeatEventIterator iter;
 
    [BeatTrackedSample copyIteratorFromSource:&_beatEffectIteratorContext destination:&iter];
    
    unsigned long long frame = iter.currentEvent->frame;
    while ((iter.currentEvent->style & BeatEventStyleBar) != BeatEventStyleBar) {
        frame = [self.beatSample seekToPreviousBeat:&iter];
        NSLog(@"repeating beat at %lld", frame);
    };
    NSLog(@"previous bar is at %lld", frame);
    _audioController.currentFrame = frame;
    [self updateRemotePosition];
}

- (IBAction)skip4Bars:(id)sender
{
    BeatEventIterator iter;
 
    [BeatTrackedSample copyIteratorFromSource:&_beatEffectIteratorContext destination:&iter];
    
    unsigned int barCount = 4;
    unsigned long long frame = iter.currentEvent->frame;
    while (barCount-- > 0) {
        while ((iter.currentEvent->style & BeatEventStyleBar) != BeatEventStyleBar) {
            frame = [self.beatSample seekToNextBeat:&iter];
        };
        if (barCount > 1 && (iter.currentEvent->style & BeatEventStyleBar) == BeatEventStyleBar) {
            frame = [self.beatSample seekToNextBeat:&iter];
        }
    };
    NSLog(@"next bar is at %lld", frame);
    _audioController.currentFrame = frame;
    [self updateRemotePosition];

}

- (IBAction)repeat4Bars:(id)sender
{
    BeatEventIterator iter;
 
    [BeatTrackedSample copyIteratorFromSource:&_beatEffectIteratorContext destination:&iter];

    unsigned int barCount = 4;
    unsigned long long frame = iter.currentEvent->frame;

    while (barCount-- > 0) {
        while ((iter.currentEvent->style & BeatEventStyleBar) != BeatEventStyleBar) {
            frame = [self.beatSample seekToPreviousBeat:&iter];
            NSLog(@"repeating beat at %lld", frame);
        };
        if (barCount > 1 && (iter.currentEvent->style & BeatEventStyleBar) == BeatEventStyleBar) {
            frame = [self.beatSample seekToPreviousBeat:&iter];
        }
    };
    NSLog(@"repeating 4 bars at %lld", frame);
    _audioController.currentFrame = frame;
    [self updateRemotePosition];
}

#pragma mark - Full Screen Support: Persisting and Restoring Window's Non-FullScreen Frame

+ (NSArray *)restorableStateKeyPaths
{
    return [[super restorableStateKeyPaths] arrayByAddingObject:@"frameForNonFullScreenMode"];
}

#pragma mark - Info Panel delegate

- (BOOL)playing
{
    return _audioController.playing;
}

- (NSArray<NSString*>*)knownGenres
{
    return [_browser knownGenres];
}

// FIXME: This screams for an objective c native approach; key value observation
- (void)metaChangedForMeta:(MediaMetaData*)meta updatedMeta:(MediaMetaData*)updatedMeta
{
    NSAssert(meta != nil, @"missing original");
    if (self.meta == meta) {
        [self setMeta:updatedMeta];
    }
    [_browser metaChangedForMeta:meta updatedMeta:updatedMeta];
}

- (void)finalizeMetaUpdates
{
    NSLog(@"reloading browser");
    [_browser reloadData];
}

@end
