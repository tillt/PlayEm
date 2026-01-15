//
//  WindowController.m
//  PlayEm
//
//  Created by Till Toenshoff on 29.05.20.
//  Copyright © 2020 Till Toenshoff. All rights reserved.
//

#import "WaveWindowController.h"

#import <AVFoundation/AVFoundation.h>
#import <AVKit/AVKit.h>
#import <CoreImage/CoreImage.h>
#import <IOKit/pwr_mgt/IOPM.h>
#import <MediaPlayer/MediaPlayer.h>
#import <MetalKit/MetalKit.h>

#import "ActivityManager.h"
#import "ActivityViewController.h"
#import "AudioController.h"
#import "AudioDevice.h"

#import "BeatTrackedSample.h"
#import "BrowserController.h"
#import "ControlPanelController.h"
#import "CreditsViewController.h"
#import "Defaults.h"
#import "EnergyDetector.h"
#import "FXViewController.h"
#import "IdentifyViewController.h"
#import "InfoPanel.h"
#import "KeyTrackedSample.h"
#import "LazySample.h"
#import "LoadState.h"
#import "MediaMetaData.h"
#import "MediaMetaData+TrackList.h"
#import "MetaController.h"
#import "MusicAuthenticationController.h"
#import "NSAlert+BetterError.h"
#import "PhosphorChaserView.h"
#import "PlaylistController.h"
#import "ProfilingPointsOfInterest.h"
#import "GraphStatusViewController.h"
#import "ScopeRenderer.h"
#import "SymbolButton.h"
#import "TableHeaderCell.h"
#import "TotalIdentificationController.h"
#import "TrackList.h"
#import "TracklistController.h"
#import "UIView+Visibility.h"
#import "VisualSample.h"
#import "WaveScrollView.h"
#import "WaveView.h"
#import "WaveViewController.h"

static NSString* const kFXLastEffectDefaultsKey = @"FXLastEffectComponent";
static NSString* const kFXLastEffectEnabledKey = @"FXLastEffectEnabled";
static NSString *const kSkipRateMismatchWarning = @"SkipRateMismatchWarning";

@class BeatLayerDelegate;
@class WaveLayerDelegate;
@class MarkLayerDelegate;

static const float kShowHidePanelAnimationDuration = 0.3f;

static const float kPixelPerSecond = 120.0f;
static const size_t kReducedVisualSampleWidth = 8000;

const CGFloat kDefaultWindowWidth = 1280.0f;
const CGFloat kDefaultWindowHeight = 920.0f;

const CGFloat kMinWindowWidth = 465.0f;
const CGFloat kMinWindowHeight = 100.0f;  // Constraints on the subviews make this a minimum
                                          // that is never reached.
const CGFloat kMinScopeHeight = 64.0f;    // Smaller would still be ok...
const CGFloat kMinTableHeight = 0.0f;     // Just forget about it.
const CGFloat kMinSearchHeight = 25.0f;   // Just forget about it.

static const int kSplitPositionCount = 7;

const size_t kBrowserSplitIndexGenres = 0;
const size_t kBrowserSplitIndexAlbums = 1;
const size_t kBrowserSplitIndexArtists = 2;
const size_t kBrowserSplitIndexTempos = 3;
const size_t kBrowserSplitIndexKey = 4;
const size_t kBrowserSplitIndexRatings = 5;
const size_t kBrowserSplitIndexTags = 6;

const size_t kWindowSplitIndexVisuals = 0;
const size_t kWindowSplitIndexBrowser = 1;

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

@interface WaveWindowController () {
    CGFloat splitPosition[kSplitPositionCount];
    CGFloat splitPositionMemory[kSplitPositionCount];
    CGFloat splitSelectorPositionMemory[kSplitPositionCount];

    BeatEventIterator _beatEffectIteratorContext;
    unsigned long long _beatEffectAtFrame;
    unsigned long long _beatEffectRampUpFrames;

    float _visibleBPM;

    BOOL _mediakeyJustJumped;
    BOOL _filtering;
    
    BOOL _timeUpdateScheduled;

    LoaderState _loaderState;
}
@property (nonatomic, strong) MetaController* metaController;

@property (assign, nonatomic) CGFloat windowBarHeight;
@property (assign, nonatomic) CGRect smallBelowVisualsFrame;
@property (assign, nonatomic) CGFloat smallSplitter1Position;
@property (assign, nonatomic) CGFloat smallSplitter2Position;

@property (strong, nonatomic) ScopeRenderer* renderer;
@property (assign, nonatomic) CGRect preFullscreenFrame;
@property (strong, nonatomic) LazySample* sample;
@property (assign, nonatomic) BOOL inTransition;

@property (strong, nonatomic) PlaylistController* playlist;
@property (strong, nonatomic) TracklistController* tracklist;

@property (strong, nonatomic) MediaMetaData* meta;

@property (strong, nonatomic) ControlPanelController* controlPanelController;
@property (strong, nonatomic) MusicAuthenticationController* authenticator;

@property (strong, nonatomic) TotalIdentificationController* totalIdentificationController;

@property (strong, nonatomic) NSPopover* popOver;

@property (strong, nonatomic) NSWindowController* infoWindowController;
@property (strong, nonatomic) NSWindowController* identifyWindowController;
@property (strong, nonatomic) NSWindowController* aboutWindowController;
@property (strong, nonatomic) NSWindowController* activityWindowController;
@property (strong, nonatomic) NSWindowController* graphStatusWindowController;
@property (strong, nonatomic) FXViewController* fxViewController;

@property (strong, nonatomic) NSViewController* aboutViewController;
@property (strong, nonatomic) NSViewController* activityViewController;

@property (strong, nonatomic) WaveViewController* scrollingWaveViewController;
@property (strong, nonatomic) WaveViewController* totalWaveViewController;

//@property (strong, nonatomic) SPMediaKeyTap* keyTap;
@property (strong, nonatomic) AVRouteDetector* routeDetector;
@property (strong, nonatomic) AVRoutePickerView* pickerView;

@property (assign, nonatomic) CFTimeInterval videoDelay;
@property (strong, nonatomic) CADisplayLink* displayLink;

@property (strong, nonatomic) NSButton* identifyToolbarButton;
@property (strong, nonatomic) NSButton* playlistToolbarButton;
@property (strong, nonatomic) NSButton* totalToolbarButton;

@property (strong, nonatomic) NSTableView* songsTable;
@property (strong, nonatomic) NSTableView* genreTable;
@property (strong, nonatomic) NSTableView* artistsTable;
@property (strong, nonatomic) NSTableView* albumsTable;
@property (strong, nonatomic) NSTableView* temposTable;
@property (strong, nonatomic) NSTableView* keysTable;
@property (strong, nonatomic) NSTableView* ratingsTable;
@property (strong, nonatomic) NSTableView* tagsTable;
@property (strong, nonatomic) NSSearchField* searchField;

//@property (strong, nonatomic) IBOutlet NSTableView* playlistTable;
//@property (strong, nonatomic) IBOutlet NSTableView* tracklistTable;

@property (strong, nonatomic) NSTabView* listsTabView;

@property (strong, nonatomic) NSSegmentedControl* listsSegment;

@property (strong, nonatomic) NSTabViewItem* playlistTabViewItem;
@property (strong, nonatomic) NSTabViewItem* tracklistTabViewItem;

@property (strong, nonatomic) ActivityToken* decoderToken;
@property (strong, nonatomic) PhosphorChaserView* activityChaser;

@property (strong, nonatomic) NSButton* importButton;
@property (strong, nonatomic) NSTextField* importLabel;
@property (strong, nonatomic) NSProgressIndicator* importProgress;
@property (strong, nonatomic) ActivityToken* importToken;

@end

// FIXME: Refactor the shit out of this -- it is far too big.

@implementation WaveWindowController {
    IOPMAssertionID _noSleepAssertionID;
    dispatch_queue_t _displayLinkQueue;
}

- (void)renderCallback:(CADisplayLink*)sender
{
    // os_signpost_interval_begin(pointsOfInterest, POICADisplayLink,
    // "CADisplayLink");
    //  Substract the latency introduced by the output device setup to compensate
    //  and get video in sync with audible audio. (done by the abstraction)
    AVAudioFramePosition frame = self.audioController.currentFrame;

    // Add the delay until the video gets visible to the playhead position for
    // compensation.
    CFTimeInterval timeToDisplay = sender.duration + self.videoDelay;
    frame += [self.audioController frameCountDeltaWithTimeDelta:timeToDisplay];

    // os_signpost_interval_begin(pointsOfInterest, POISetCurrentFrame,
    // "SetCurrentFrame");
    self.currentFrame = frame;

    [_controlPanelController tickWithTimestamp:sender.timestamp];

    // os_signpost_interval_end(pointsOfInterest, POISetCurrentFrame,
    // "SetCurrentFrame"); os_signpost_interval_end(pointsOfInterest,
    // POICADisplayLink, "CADisplayLink");
}

- (id)init
{
    self = [super initWithWindowNibName:@""];
    if (self) {
        pointsOfInterest = os_log_create("com.toenshoff.playem", OS_LOG_CATEGORY_POINTS_OF_INTEREST);
        _noSleepAssertionID = 0;
        _noSleepAssertionID = 0;
        _loaderState = LoaderStateReady;
        _videoDelay = 0.0;
        _metaController = [MetaController new];
        _timeUpdateScheduled = NO;
        _importToken = nil;
    }
    return self;
}

- (void)dealloc
{
    [_displayLink invalidate];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)updateSongsCount:(size_t)songs filtered:(size_t)filtered
{
    NSString* value = nil;
    NSString* unit = nil;

    assert(filtered <= songs);

    if (songs == 0) {
        value = @"Nothing";
    } else {
        if (filtered == songs) {
            value = [NSString stringWithFormat:@"%ld", songs];
        } else {
            value = [NSString stringWithFormat:@"%ld / %ld", filtered, songs];
        }
        if (songs == 1) {
            unit = @"Song";
        } else {
            unit = @"Songs";
        }
    }
    if (unit == nil) {
        _songsCount.stringValue = [NSString stringWithFormat:@"%@", value];
    } else {
        _songsCount.stringValue = [NSString stringWithFormat:@"%@ %@", value, unit];
    }

    // Show import prompt when the library is empty.
    if (_importToken != nil) {
        _importLabel.hidden = NO;
        _importProgress.hidden = NO;
        _importButton.hidden = YES;
    } else {
        _importButton.hidden = (songs > 0);
    }
}

- (void)performFindPanelAction:(id)sender
{
    _filtering = YES;
    [_horizontalSplitView insertArrangedSubview:_searchField atIndex:2];
    //    NSLayoutConstraint* constraint = [NSLayoutConstraint
    //    constraintWithItem:_searchField
    //                                                                  attribute:NSLayoutAttributeHeight
    //                                                                  relatedBy:NSLayoutRelationEqual
    //                                                                     toItem:nil
    //                                                                  attribute:NSLayoutAttributeNotAnAttribute
    //                                                                 multiplier:1.0
    //                                                                   constant:kMinSearchHeight];
    //    [_horizontalSplitView addConstraint:constraint];
    [_searchField.window makeFirstResponder:_searchField];
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

    // FIXME: Consider moving this into a notification handler for the beat
    // effect.
    [self setBPM:effectiveTempo];

    NSDictionary* dict = @{
        kBeatNotificationKeyBeat : @(_beatEffectIteratorContext.currentEvent.index),
        kBeatNotificationKeyStyle : @(_beatEffectIteratorContext.currentEvent.style),
        kBeatNotificationKeyTempo : @(effectiveTempo),
        kBeatNotificationKeyFrame : @(_beatEffectIteratorContext.currentEvent.frame),
        kBeatNotificationKeyLocalEnergy : @(_beatEffectIteratorContext.currentEvent.energy),
        kBeatNotificationKeyTotalEnergy : @(_beatSample.energy.rms),
        kBeatNotificationKeyLocalPeak : @(_beatEffectIteratorContext.currentEvent.peak),
        kBeatNotificationKeyTotalPeak : @(_beatSample.energy.peak),
        kBeatNotificationKeyTotalBeats : @(_beatSample.beatCount),
    };
    [[NSNotificationCenter defaultCenter] postNotificationName:kBeatTrackedSampleBeatNotification object:dict];
}

#pragma mark Toolbar delegate

static const NSString* kPlaylistToolbarIdentifier = @"Playlist";
static const NSString* kIdentifyToolbarIdentifier = @"Live Identify";

- (NSArray*)toolbarDefaultItemIdentifiers:(NSToolbar*)toolbar
{
    return @[ NSToolbarFlexibleSpaceItemIdentifier, kIdentifyToolbarIdentifier, NSToolbarSpaceItemIdentifier, kPlaylistToolbarIdentifier ];
}

- (NSArray*)toolbarAllowedItemIdentifiers:(NSToolbar*)toolbar
{
    return @[ NSToolbarFlexibleSpaceItemIdentifier, kIdentifyToolbarIdentifier, NSToolbarSpaceItemIdentifier, kPlaylistToolbarIdentifier ];
}

- (NSSet<NSToolbarItemIdentifier>*)toolbarImmovableItemIdentifiers:(NSToolbar*)toolbar
{
    return [NSSet setWithObjects:kPlaylistToolbarIdentifier, kIdentifyToolbarIdentifier, nil];
}

- (NSToolbarItem*)toolbar:(NSToolbar*)toolbar itemForItemIdentifier:(NSToolbarItemIdentifier)itemIdentifier willBeInsertedIntoToolbar:(BOOL)flag
{
    NSToolbarItem* item = nil;
    NSImage* image = nil;
    NSButton* button = nil;

    if (itemIdentifier == kPlaylistToolbarIdentifier) {
        item = [[NSToolbarItem alloc] initWithItemIdentifier:itemIdentifier];
        image = [NSImage imageWithSystemSymbolName:@"list.bullet"
                          accessibilityDescription:NSLocalizedString(@"accessibility.playlist", @"Accessibility label for playlist button")];
    } else if (itemIdentifier == kIdentifyToolbarIdentifier) {
        item = [[NSToolbarItem alloc] initWithItemIdentifier:itemIdentifier];
        image = [NSImage imageWithSystemSymbolName:@"waveform.and.magnifyingglass"
                          accessibilityDescription:NSLocalizedString(@"accessibility.live_identify", @"Accessibility label for live identify button")];
    } else {
        assert(NO);
    }

    button = [[NSButton alloc] initWithFrame:NSMakeRect(0, 0, 40.0, 40.0)];
    button.title = @"";
    button.image = image;
    [button setButtonType:NSButtonTypeToggle];
    button.bezelStyle = NSBezelStyleTexturedRounded;

    if (itemIdentifier == kPlaylistToolbarIdentifier) {
        _playlistToolbarButton = button;
        button.action = @selector(showPlaylist:);
    } else if (itemIdentifier == kIdentifyToolbarIdentifier) {
        _identifyToolbarButton = button;
        button.action = @selector(showIdentifier:);
    }

    [item setView:button];

    return item;
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
    IOReturn ret = IOPMAssertionCreateWithName(kIOPMAssertionTypeNoDisplaySleep, (IOPMAssertionLevel) kIOPMAssertionLevelOn, (__bridge CFStringRef) reason,
                                               &_noSleepAssertionID);
    NSLog(@"screen locked with result %d", ret);

    return ret == kIOReturnSuccess;
}

- (void)loadWindow
{
    NSLog(@"loadWindow...");

    NSWindowStyleMask style = NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskUnifiedTitleAndToolbar | NSWindowStyleMaskMiniaturizable |
                              NSWindowStyleMaskResizable;

    self.shouldCascadeWindows = NO;

    NSScreen* screen = [NSScreen mainScreen];
    self.window =
        [[NSWindow alloc] initWithContentRect:NSMakeRect((screen.frame.size.width - kDefaultWindowWidth) / 2.0,
                                                         (screen.frame.size.height - kDefaultWindowHeight) / 2.0, kDefaultWindowWidth, kDefaultWindowHeight)
                                    styleMask:style
                                      backing:NSBackingStoreBuffered
                                        defer:YES];
    self.window.minSize = NSMakeSize(kMinWindowWidth, kMinWindowHeight);
    self.window.titlebarSeparatorStyle = NSTitlebarSeparatorStyleLine;
    self.window.titlebarAppearsTransparent = YES;
    self.window.titleVisibility = NO;
    self.window.allowsConcurrentViewDrawing = YES;
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

    _scrollingWaveViewController = [WaveViewController new];
    _scrollingWaveViewController.delegate = self;
    _scrollingWaveViewController.tileWidth = 256.0;
    _scrollingWaveViewController.markerColor = [[Defaults sharedDefaults] markerColor];
    _scrollingWaveViewController.markerWidth = 2.0;
    _scrollingWaveViewController.beatMask = BeatEventStyleBeat | BeatEventStyleBar;
    _scrollingWaveViewController.beatColor = [[Defaults sharedDefaults] beatColor];
    _scrollingWaveViewController.beatWidth = 3.0;
    _scrollingWaveViewController.barColor = [[Defaults sharedDefaults] barColor];
    _scrollingWaveViewController.barWidth = 3.0;
    _scrollingWaveViewController.markerColor = [[Defaults sharedDefaults] markerColor];
    _scrollingWaveViewController.markerWidth = 5.0;

    _totalWaveViewController = [WaveViewController new];
    _totalWaveViewController.delegate = self;
    _totalWaveViewController.tileWidth = 8.0;
    _totalWaveViewController.beatMask = BeatEventStyleMarkIntro | BeatEventStyleMarkBuildup | BeatEventStyleMarkTeardown | BeatEventStyleMarkOutro;

    _totalWaveViewController.beatColor = [[Defaults sharedDefaults] beatColor];
    _totalWaveViewController.beatWidth = 1.0;
    _totalWaveViewController.barColor = [[Defaults sharedDefaults] barColor];
    _totalWaveViewController.barWidth = 1.0;
    _totalWaveViewController.markerColor = [[Defaults sharedDefaults] markerColor];
    _totalWaveViewController.markerWidth = 2.0;

    _controlPanelController = [[ControlPanelController alloc] initWithDelegate:self];
    _controlPanelController.layoutAttribute = NSLayoutAttributeLeft;
    [self.window addTitlebarAccessoryViewController:_controlPanelController];

    [_controlPanelController setEffectsEnabled:NO];

    _fxViewController = [[FXViewController alloc] initWithAudioController:_audioController];

    __weak typeof(self) weakSelf = self;
    _fxViewController.effectSelectionChanged = ^(NSInteger index) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }
        BOOL enabled = index >= 0;
        [strongSelf.controlPanelController setEffectsEnabled:enabled];
        if (enabled) {
            [strongSelf persistEffectSelectionIndex:index];
        }
        [strongSelf.fxViewController setEffectEnabledState:enabled];
    };

    _splitViewController = [NSSplitViewController new];
    [self loadViews];

    //WaveWindowController* __weak weakSelf = self;

    _scrollingWaveViewController.visualSample = self.visualSample;
    _scrollingWaveViewController.offsetBlock = ^CGFloat {
        return weakSelf.scrollingWaveViewController.view.enclosingScrollView.documentVisibleRect.origin.x;
    };
    _scrollingWaveViewController.widthBlock = ^CGFloat {
        return weakSelf.scrollingWaveViewController.view.enclosingScrollView.documentVisibleRect.size.width;
    };

    _totalWaveViewController.visualSample = self.totalVisual;
    _totalWaveViewController.offsetBlock = ^CGFloat {
        return 0.0;
    };
    _totalWaveViewController.widthBlock = ^CGFloat {
        return weakSelf.totalWaveViewController.view.frame.size.width;
    };

    [_scrollingWaveViewController updateTiles];
    [_scrollingWaveViewController updateTrackDescriptions];
    [_totalWaveViewController updateTiles];
    [_totalWaveViewController updateTrackDescriptions];

    [self subscribeToRemoteCommands];

    //    self.authenticator = [MusicAuthenticationController new];
    //    [self.authenticator
    //    requestAppleMusicDeveloperTokenWithCompletion:^(NSString* token){
    //        NSLog(@"token: %@", token);
    //    }];
}

- (NSMenu*)songMenu
{
    NSMenu* menu = [NSMenu new];

    NSMenuItem* item = [[NSMenuItem alloc] initWithTitle:NSLocalizedString(@"menu.song.play_next", @"Song context menu item: play next")
                                                  action:@selector(playNextInPlaylist:)
                                           keyEquivalent:@"n"];
    [item setKeyEquivalentModifierMask:NSEventModifierFlagCommand];
    [menu addItem:item];

    item = [[NSMenuItem alloc] initWithTitle:NSLocalizedString(@"menu.song.play_later", @"Song context menu item: play later")
                                      action:@selector(playLaterInPlaylist:)
                               keyEquivalent:@"l"];
    [item setKeyEquivalentModifierMask:NSEventModifierFlagCommand];
    [menu addItem:item];

    [menu addItem:[NSMenuItem separatorItem]];

    item = [menu addItemWithTitle:NSLocalizedString(@"menu.song.remove_from_library", @"Song context menu item: remove from library")
                           action:@selector(removeFromLibrary:)
                    keyEquivalent:@""];
    item.target = _browser;

    [menu addItem:[NSMenuItem separatorItem]];

    item = [menu addItemWithTitle:NSLocalizedString(@"menu.common.show_info", @"Menu item: show info")
                           action:@selector(showInfoForSelectedSongs:)
                    keyEquivalent:@""];
    item.target = _browser;

    [menu addItem:[NSMenuItem separatorItem]];

    item = [menu addItemWithTitle:NSLocalizedString(@"menu.song.show_in_finder", @"Song context menu item: show in Finder")
                           action:@selector(showInFinder:)
                    keyEquivalent:@""];
    item.target = _browser;

    // TODO: allow disabling depending on the number of songs selected. Note to
    // myself, this here is the wrong place!
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

    NSPoint pos =
        NSMakePoint(NSMidX(screen.visibleFrame) - self.window.frame.size.width * 0.5, NSMidY(screen.visibleFrame) - self.window.frame.size.height * 0.5);

    WaveWindowController* __weak weakSelf = self;

    [NSAnimationContext
        runAnimationGroup:^(NSAnimationContext* context) {
            [context setDuration:0.7];
            [weakSelf.window.animator setFrame:NSMakeRect(pos.x, pos.y, weakSelf.window.frame.size.width, weakSelf.window.frame.size.height) display:YES];
        }
        completionHandler:^{
        }];
}

/// Creates a menu when we got more than a single screen connected, allowing for
/// moving the application window to any other screen.
- (NSMenu*)dockMenu
{
    NSArray<NSScreen*>* screens = [NSScreen screens];
    if (screens.count < 2) {
        return nil;
    }

    NSMenuItem* item = nil;
    _dockMenu = [NSMenu new];

    for (int i = 0; i < screens.count; i++) {
        NSScreen* screen = screens[i];
        if (screen == self.window.screen) {
            NSLog(@"we can spare the screen we are already on (%@)", screen.localizedName);
            continue;
        }
        NSString* moveFormat = NSLocalizedString(@"menu.window.move_to_screen_format", @"Format for menu item that moves window to another screen");
        item = [[NSMenuItem alloc] initWithTitle:[NSString localizedStringWithFormat:moveFormat, screen.localizedName]
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
    
    const CGFloat playlistFxViewWidth = 320.0f;
    const CGFloat statusLineHeight = 20.0f;
    const CGFloat searchFieldHeight = 25.0f;
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
    
    CGFloat scopeViewHeight =
    self.window.contentView.bounds.size.height - (songsTableViewHeight + selectorTableViewHeight + totalWaveViewHeight + scrollingWaveViewHeight);
    if (scopeViewHeight <= kMinScopeHeight) {
        scopeViewHeight = kMinScopeHeight;
    }
    const NSAutoresizingMaskOptions kViewFullySizeable = NSViewHeightSizable | NSViewWidthSizable;
    
    // Status Line.
    _songsCount = [[NSTextField alloc] initWithFrame:NSMakeRect(self.window.contentView.bounds.origin.x,
                                                                self.window.contentView.bounds.origin.y,
                                                                self.window.contentView.bounds.size.width,
                                                                statusLineHeight - 3)];
    _songsCount.font = [[Defaults sharedDefaults] smallFont];
    _songsCount.textColor = [[Defaults sharedDefaults] tertiaryLabelColor];
    _songsCount.bordered = NO;
    _songsCount.alignment = NSTextAlignmentCenter;
    _songsCount.selectable = NO;
    _songsCount.autoresizingMask = NSViewWidthSizable;
    _songsCount.translatesAutoresizingMaskIntoConstraints = YES;
    
    [self.window.contentView addSubview:_songsCount];
    
    //    const CGFloat chaserSize = 30;
    //    // Phosphor chaser busy indicator (top-right).
    //    CGFloat chaserX = self.window.contentView.bounds.origin.x + 10.0;
    //    CGFloat chaserY =  self.window.contentView.bounds.origin.y - 4.0;
    //    _activityChaser = [[PhosphorChaserView alloc]
    //    initWithFrame:NSMakeRect(chaserX, chaserY, chaserSize, chaserSize)];
    //    _activityChaser.autoresizingMask = NSViewNotSizable;
    //    [self.window.contentView addSubview:_activityChaser];
    //    [self refreshChaserState];
    //
    //    NSClickGestureRecognizer* recognizer = [[NSClickGestureRecognizer alloc]
    //    initWithTarget:self
    //                                                                                     action:@selector(showActivity:)];
    //    recognizer.numberOfClicksRequired = 1;
    //    [_activityChaser addGestureRecognizer:recognizer];
    
    // Below Visuals.
    CGFloat height = scopeViewHeight + scrollingWaveViewHeight + totalWaveViewHeight;
    
    NSRect availableRect = NSMakeRect(self.window.contentView.bounds.origin.x, self.window.contentView.bounds.origin.y + statusLineHeight,
                                      self.window.contentView.bounds.size.width, self.window.contentView.bounds.size.height - statusLineHeight);
    _horizontalSplitView = [[NSSplitView alloc] initWithFrame:availableRect];
    _horizontalSplitView.autoresizingMask = kViewFullySizeable;
    _horizontalSplitView.autoresizesSubviews = YES;
    _horizontalSplitView.dividerStyle = NSSplitViewDividerStyleThin;
    _horizontalSplitView.delegate = self;
    _horizontalSplitView.identifier = @"VerticalSplitterID";
    _horizontalSplitView.translatesAutoresizingMaskIntoConstraints = YES;
    
    _belowVisuals = [[NSView alloc] initWithFrame:NSMakeRect(self.window.contentView.bounds.origin.x, self.window.contentView.bounds.origin.y,
                                                             self.window.contentView.bounds.size.width, height)];
    _belowVisuals.autoresizingMask = kViewFullySizeable;
    _belowVisuals.autoresizesSubviews = YES;
    _belowVisuals.wantsLayer = YES;
    _belowVisuals.translatesAutoresizingMaskIntoConstraints = YES;
    
    _totalWaveViewController.view.frame =
    NSMakeRect(_belowVisuals.bounds.origin.x, _belowVisuals.bounds.origin.y, _belowVisuals.bounds.size.width, totalWaveViewHeight);
    _totalWaveViewController.view.autoresizingMask = NSViewWidthSizable;
    _totalWaveViewController.view.translatesAutoresizingMaskIntoConstraints = YES;
    [_belowVisuals addSubview:_totalWaveViewController.view];
    //[_totalWaveViewController resetTracking];
    
    WaveScrollView* tiledSV =
    [[WaveScrollView alloc] initWithFrame:NSMakeRect(_belowVisuals.bounds.origin.x, _belowVisuals.bounds.origin.y + totalWaveViewHeight,
                                                     _belowVisuals.bounds.size.width, scrollingWaveViewHeight)];
    tiledSV.wantsLayer = YES;
    tiledSV.autoresizingMask = NSViewWidthSizable;
    tiledSV.drawsBackground = NO;
    tiledSV.translatesAutoresizingMaskIntoConstraints = YES;
    tiledSV.verticalScrollElasticity = NSScrollElasticityNone;
    
    _scrollingWaveViewController.view.frame = tiledSV.bounds;
    //[_scrollingWaveViewController resetTracking];
    
    tiledSV.documentView = _scrollingWaveViewController.view;
    [_belowVisuals addSubview:tiledSV];
    
    // Horizontal Line below total wave view.
    NSBox* line = [[NSBox alloc] initWithFrame:NSMakeRect(_belowVisuals.bounds.origin.x, _belowVisuals.bounds.origin.y, _belowVisuals.bounds.size.width, 1.0)];
    line.boxType = NSBoxCustom;
    line.borderColor = [[[Defaults sharedDefaults] lightBeamColor] colorWithAlphaComponent:0.2];
    line.autoresizingMask = NSViewWidthSizable;
    [_belowVisuals addSubview:line];
    
    // Horizontal Line above total wave view.
    line = [[NSBox alloc]
            initWithFrame:NSMakeRect(_belowVisuals.bounds.origin.x, _belowVisuals.bounds.origin.y + totalWaveViewHeight, _belowVisuals.bounds.size.width, 1.0)];
    line.boxType = NSBoxCustom;
    line.borderColor = [[[Defaults sharedDefaults] lightBeamColor] colorWithAlphaComponent:0.2];
    line.autoresizingMask = NSViewWidthSizable;
    [_belowVisuals addSubview:line];
    
    line = [[NSBox alloc] initWithFrame:NSMakeRect(_belowVisuals.bounds.origin.x, _belowVisuals.bounds.origin.y + scrollingWaveViewHeight + totalWaveViewHeight,
                                                   _belowVisuals.bounds.size.width, 1.0)];
    line.boxType = NSBoxCustom;
    line.borderColor = [[[Defaults sharedDefaults] lightBeamColor] colorWithAlphaComponent:0.2];
    line.autoresizingMask = NSViewWidthSizable;
    [_belowVisuals addSubview:line];
    
    _effectBelowPlaylist =
    [[NSVisualEffectView alloc] initWithFrame:NSMakeRect(_belowVisuals.bounds.size.width, _belowVisuals.bounds.origin.y, playlistFxViewWidth, height)];
    _effectBelowPlaylist.autoresizingMask = NSViewHeightSizable | NSViewMinXMargin;
    
    NSSegmentedControl* segment = [NSSegmentedControl segmentedControlWithLabels:@[
        NSLocalizedString(@"tab.playlist", @"Playlist tab title"),
        NSLocalizedString(@"tab.tracklist", @"Tracklist tab title"),
    ]
                                                                    trackingMode:NSSegmentSwitchTrackingSelectOne
                                                                          target:self
                                                                          action:@selector(listsSwitched:)];
    segment.segmentStyle = NSSegmentStyleRounded;
    segment.autoresizingMask = NSViewMinYMargin;
    segment.translatesAutoresizingMaskIntoConstraints = YES;
    const CGFloat sideMargin = 10.0;
    segment.frame = NSMakeRect(sideMargin, _effectBelowPlaylist.bounds.size.height - 35.0, _effectBelowPlaylist.bounds.size.width - (sideMargin * 2.0), 30.0);
    [_effectBelowPlaylist addSubview:segment];
    [segment setSelectedSegment:0];
    
    _listsTabView =
    [[NSTabView alloc] initWithFrame:NSMakeRect(0.0, 0.0, _effectBelowPlaylist.bounds.size.width, _effectBelowPlaylist.bounds.size.height - 30.0)];
    _listsTabView.tabPosition = NSTabPositionTop;
    _listsTabView.tabViewType = NSNoTabsNoBorder;
    _listsTabView.autoresizingMask = kViewFullySizeable;
    
    // Playlist
    _playlist = [PlaylistController new];
    _playlist.delegate = self;
    _playlistTabViewItem = [NSTabViewItem tabViewItemWithViewController:_playlist];
    _playlistTabViewItem.view.frame = _listsTabView.bounds;
    _playlistTabViewItem.initialFirstResponder = _playlist.view;
    [_playlistTabViewItem setLabel:NSLocalizedString(@"tab.playlist", @"Playlist tab title")];
    [_listsTabView addTabViewItem:_playlistTabViewItem];
    
    // Tracklist
    _tracklist = [TracklistController new];
    _tracklist.delegate = self;
    _tracklistTabViewItem = [NSTabViewItem tabViewItemWithViewController:_tracklist];
    _tracklistTabViewItem.view.frame = _listsTabView.bounds;
    _tracklistTabViewItem.initialFirstResponder = _tracklist.view;
    [_tracklistTabViewItem setLabel:NSLocalizedString(@"tab.tracklist", @"Tracklist tab title")];
    [_listsTabView addTabViewItem:_tracklistTabViewItem];
    
    [_effectBelowPlaylist addSubview:_listsTabView];
    
    // Scope / FFT View
    ScopeView* scv = [[ScopeView alloc]
                      initWithFrame:NSMakeRect(_belowVisuals.bounds.origin.x, _belowVisuals.bounds.origin.y + totalWaveViewHeight + scrollingWaveViewHeight + 1.0,
                                               _belowVisuals.bounds.size.width, scopeViewHeight - 2.0)
                      device:MTLCreateSystemDefaultDevice()];
    [_belowVisuals addSubview:scv];
    
    line = [[NSBox alloc] initWithFrame:NSMakeRect(_belowVisuals.bounds.origin.x,
                                                   _belowVisuals.bounds.origin.y + scrollingWaveViewHeight + totalWaveViewHeight + scv.frame.size.height,
                                                   _belowVisuals.bounds.size.width, 1.0)];
    line.boxType = NSBoxCustom;
    line.borderColor = [[[Defaults sharedDefaults] lightBeamColor] colorWithAlphaComponent:0.2];
    // line.borderColor = [NSColor redColor];
    line.autoresizingMask = NSViewWidthSizable | NSViewMinYMargin;
    [_belowVisuals addSubview:line];
    
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
    
    [_horizontalSplitView addArrangedSubview:_belowVisuals];
    
    ///
    /// Genre, Artist, Album, BPM, Key Tables.
    ///
    NSRect verticalRect =
    NSMakeRect(_horizontalSplitView.bounds.origin.x, _horizontalSplitView.bounds.origin.y, _horizontalSplitView.bounds.size.width, selectorTableViewHeight);
    _browserColumnSplitView = [[NSSplitView alloc] initWithFrame:verticalRect];
    _browserColumnSplitView.vertical = YES;
    _browserColumnSplitView.delegate = self;
    _browserColumnSplitView.identifier = @"HorizontalSplittersID";
    _browserColumnSplitView.dividerStyle = NSSplitViewDividerStyleThin;
    
    NSScrollView* sv = [[NSScrollView alloc] initWithFrame:NSMakeRect(0.0, 0.0, selectorTableViewWidth, selectorTableViewHeight)];
    sv.hasVerticalScroller = YES;
    sv.autoresizingMask = kViewFullySizeable;
    sv.drawsBackground = NO;
    _genreTable = [[NSTableView alloc] initWithFrame:NSZeroRect];
    _genreTable.tag = VIEWTAG_GENRE;
    
    NSTableColumn* col = [[NSTableColumn alloc] init];
    col.title = NSLocalizedString(@"table.songs.genre", @"Genre table column title");
    col.identifier = @"Genre";
    col.width = selectorTableViewWidth - selectorColumnInset;
    col.minWidth = selectorTableViewMinWidth;
    [_genreTable addTableColumn:col];
    sv.documentView = _genreTable;
    [_browserColumnSplitView addArrangedSubview:sv];
    [_browserColumnSplitView addConstraint:[NSLayoutConstraint constraintWithItem:sv
                                                                        attribute:NSLayoutAttributeWidth
                                                                        relatedBy:NSLayoutRelationGreaterThanOrEqual
                                                                           toItem:nil
                                                                        attribute:NSLayoutAttributeNotAnAttribute
                                                                       multiplier:1.0
                                                                         constant:selectorTableViewMinWidth]];
    
    [_browserColumnSplitView addConstraint:[NSLayoutConstraint constraintWithItem:sv
                                                                        attribute:NSLayoutAttributeHeight
                                                                        relatedBy:NSLayoutRelationGreaterThanOrEqual
                                                                           toItem:nil
                                                                        attribute:NSLayoutAttributeNotAnAttribute
                                                                       multiplier:1.0
                                                                         constant:kMinTableHeight]];
    
    sv = [[NSScrollView alloc] initWithFrame:NSMakeRect(0.0, 0.0, selectorTableViewWidth, selectorTableViewHeight)];
    sv.drawsBackground = NO;
    sv.hasVerticalScroller = YES;
    sv.autoresizingMask = kViewFullySizeable;
    _artistsTable = [[NSTableView alloc] initWithFrame:NSZeroRect];
    _artistsTable.tag = VIEWTAG_ARTISTS;
    
    col = [[NSTableColumn alloc] init];
    col.title = NSLocalizedString(@"table.songs.artist", @"Artist table column title");
    col.width = selectorTableViewWidth - selectorColumnInset;
    col.minWidth = selectorTableViewMinWidth;
    [_artistsTable addTableColumn:col];
    sv.documentView = _artistsTable;
    [_browserColumnSplitView addArrangedSubview:sv];
    [_browserColumnSplitView addConstraint:[NSLayoutConstraint constraintWithItem:sv
                                                                        attribute:NSLayoutAttributeWidth
                                                                        relatedBy:NSLayoutRelationGreaterThanOrEqual
                                                                           toItem:nil
                                                                        attribute:NSLayoutAttributeNotAnAttribute
                                                                       multiplier:1.0
                                                                         constant:selectorTableViewMinWidth]];
    
    sv = [[NSScrollView alloc] initWithFrame:NSMakeRect(0.0, 0.0, selectorTableViewWidth, selectorTableViewHeight)];
    sv.hasVerticalScroller = YES;
    sv.autoresizingMask = kViewFullySizeable;
    sv.drawsBackground = NO;
    _albumsTable = [[NSTableView alloc] initWithFrame:sv.bounds];
    _albumsTable.tag = VIEWTAG_ALBUMS;
    
    col = [[NSTableColumn alloc] init];
    col.title = NSLocalizedString(@"table.songs.album", @"Album table column title");
    col.width = selectorTableViewWidth - selectorColumnInset;
    col.minWidth = selectorTableViewMinWidth;
    [_albumsTable addTableColumn:col];
    sv.documentView = _albumsTable;
    [_browserColumnSplitView addArrangedSubview:sv];
    [_browserColumnSplitView addConstraint:[NSLayoutConstraint constraintWithItem:sv
                                                                        attribute:NSLayoutAttributeWidth
                                                                        relatedBy:NSLayoutRelationGreaterThanOrEqual
                                                                           toItem:nil
                                                                        attribute:NSLayoutAttributeNotAnAttribute
                                                                       multiplier:1.0
                                                                         constant:selectorTableViewMinWidth]];
    
    sv = [[NSScrollView alloc] initWithFrame:NSMakeRect(0.0, 0.0, selectorTableViewHalfWidth, selectorTableViewHeight)];
    sv.hasVerticalScroller = YES;
    sv.autoresizingMask = kViewFullySizeable;
    sv.drawsBackground = NO;
    _temposTable = [[NSTableView alloc] initWithFrame:sv.bounds];
    _temposTable.tag = VIEWTAG_TEMPO;
    col = [[NSTableColumn alloc] init];
    col.title = NSLocalizedString(@"table.songs.bpm", @"Tempo table column title");
    col.width = selectorTableViewHalfWidth - selectorColumnInset;
    col.minWidth = selectorTableViewMinWidth;
    [_temposTable addTableColumn:col];
    sv.documentView = _temposTable;
    [_browserColumnSplitView addArrangedSubview:sv];
    [_browserColumnSplitView addConstraint:[NSLayoutConstraint constraintWithItem:sv
                                                                        attribute:NSLayoutAttributeWidth
                                                                        relatedBy:NSLayoutRelationGreaterThanOrEqual
                                                                           toItem:nil
                                                                        attribute:NSLayoutAttributeNotAnAttribute
                                                                       multiplier:1.0
                                                                         constant:selectorTableViewMinWidth]];
    
    sv = [[NSScrollView alloc] initWithFrame:NSMakeRect(0.0, 0.0, selectorTableViewHalfWidth, selectorTableViewHeight)];
    sv.hasVerticalScroller = YES;
    sv.autoresizingMask = kViewFullySizeable;
    sv.drawsBackground = NO;
    _keysTable = [[NSTableView alloc] initWithFrame:NSZeroRect];
    _keysTable.tag = VIEWTAG_KEY;
    col = [[NSTableColumn alloc] init];
    col.title = NSLocalizedString(@"table.songs.key", @"Key table column title");
    col.width = selectorTableViewHalfWidth - selectorColumnInset;
    col.minWidth = selectorTableViewMinWidth;
    [_keysTable addTableColumn:col];
    sv.documentView = _keysTable;
    [_browserColumnSplitView addArrangedSubview:sv];
    [_browserColumnSplitView addConstraint:[NSLayoutConstraint constraintWithItem:sv
                                                                        attribute:NSLayoutAttributeWidth
                                                                        relatedBy:NSLayoutRelationGreaterThanOrEqual
                                                                           toItem:nil
                                                                        attribute:NSLayoutAttributeNotAnAttribute
                                                                       multiplier:1.0
                                                                         constant:selectorTableViewMinWidth]];
    
    sv = [[NSScrollView alloc] initWithFrame:NSMakeRect(0.0, 0.0, selectorTableViewHalfWidth, selectorTableViewHeight)];
    sv.hasVerticalScroller = YES;
    sv.autoresizingMask = kViewFullySizeable;
    sv.drawsBackground = NO;
    _ratingsTable = [[NSTableView alloc] initWithFrame:NSZeroRect];
    _ratingsTable.tag = VIEWTAG_RATING;
    col = [[NSTableColumn alloc] init];
    col.title = NSLocalizedString(@"table.songs.rating", @"Rating table column title");
    col.width = selectorTableViewHalfWidth - selectorColumnInset;
    col.minWidth = selectorTableViewMinWidth;
    [_ratingsTable addTableColumn:col];
    sv.documentView = _ratingsTable;
    [_browserColumnSplitView addArrangedSubview:sv];
    [_browserColumnSplitView addConstraint:[NSLayoutConstraint constraintWithItem:sv
                                                                        attribute:NSLayoutAttributeWidth
                                                                        relatedBy:NSLayoutRelationGreaterThanOrEqual
                                                                           toItem:nil
                                                                        attribute:NSLayoutAttributeNotAnAttribute
                                                                       multiplier:1.0
                                                                         constant:selectorTableViewMinWidth]];
    
    sv = [[NSScrollView alloc] initWithFrame:NSMakeRect(0.0, 0.0, selectorTableViewHalfWidth, selectorTableViewHeight)];
    sv.hasVerticalScroller = YES;
    sv.autoresizingMask = kViewFullySizeable;
    sv.drawsBackground = NO;
    _tagsTable = [[NSTableView alloc] initWithFrame:NSZeroRect];
    _tagsTable.tag = VIEWTAG_TAGS;
    col = [[NSTableColumn alloc] init];
    col.title = NSLocalizedString(@"table.tags.title", @"Table column title");
    col.width = selectorTableViewWidth - selectorColumnInset;
    col.minWidth = selectorTableViewMinWidth;
    [_tagsTable addTableColumn:col];
    sv.documentView = _tagsTable;
    [_browserColumnSplitView addArrangedSubview:sv];
    [_browserColumnSplitView addConstraint:[NSLayoutConstraint constraintWithItem:sv
                                                                        attribute:NSLayoutAttributeWidth
                                                                        relatedBy:NSLayoutRelationGreaterThanOrEqual
                                                                           toItem:nil
                                                                        attribute:NSLayoutAttributeNotAnAttribute
                                                                       multiplier:1.0
                                                                         constant:selectorTableViewMinWidth]];
    
    [_horizontalSplitView addArrangedSubview:_browserColumnSplitView];
    NSLayoutConstraint* constraint = [NSLayoutConstraint constraintWithItem:_browserColumnSplitView
                                                                  attribute:NSLayoutAttributeHeight
                                                                  relatedBy:NSLayoutRelationGreaterThanOrEqual
                                                                     toItem:nil
                                                                  attribute:NSLayoutAttributeNotAnAttribute
                                                                 multiplier:1.0
                                                                   constant:kMinTableHeight];
    [_horizontalSplitView addConstraint:constraint];
    
    _searchField = [[NSSearchField alloc] initWithFrame:NSMakeRect(0, 0, _horizontalSplitView.bounds.size.width, searchFieldHeight)];
    _searchField.sendsWholeSearchString = NO;
    _searchField.sendsSearchStringImmediately = YES;
    _searchField.textColor = [[Defaults sharedDefaults] lightFakeBeamColor];
    _searchField.font = [[Defaults sharedDefaults] normalFont];
    _searchField.placeholderString = NSLocalizedString(@"search.placeholder.filter", @"Search field placeholder");
    NSImage* image = [NSImage imageWithSystemSymbolName:@"line.3.horizontal.decrease"
                                accessibilityDescription:NSLocalizedString(@"search.accessibility.filter", @"Accessibility label for filter search button")];
    NSSearchFieldCell* cell = _searchField.cell;
    cell.searchButtonCell.image = image;
    
    ///
    /// Songs Table.
    ///
    sv = [[NSScrollView alloc] initWithFrame:NSMakeRect(_horizontalSplitView.bounds.origin.x, _horizontalSplitView.bounds.origin.y,
                                                        _horizontalSplitView.bounds.size.width, songsTableViewHeight)];
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
    col.title = NSLocalizedString(@"table.songs.track", @"Table column title");
    col.width = trackColumnWidth - selectorColumnInset;
    col.minWidth = (trackColumnWidth - selectorColumnInset) / 2.0f;
    col.resizingMask = NSTableColumnUserResizingMask;
    col.sortDescriptorPrototype = [[NSSortDescriptor alloc] initWithKey:@"track" ascending:YES selector:@selector(compare:)];
    [_songsTable addTableColumn:col];
    
    col = [[NSTableColumn alloc] initWithIdentifier:kSongsColTitle];
    col.title = NSLocalizedString(@"table.songs.title", @"Table column title");
    col.width = titleColumnWidth - selectorColumnInset;
    col.minWidth = (titleColumnWidth - selectorColumnInset) / 2.0f;
    col.resizingMask = NSTableColumnUserResizingMask;
    col.sortDescriptorPrototype = [[NSSortDescriptor alloc] initWithKey:@"title" ascending:YES selector:@selector(compare:)];
    [_songsTable addTableColumn:col];
    
    col = [[NSTableColumn alloc] initWithIdentifier:kSongsColTime];
    col.title = NSLocalizedString(@"table.songs.time", @"Table column title");
    col.width = timeColumnWidth - selectorColumnInset;
    col.minWidth = (timeColumnWidth - selectorColumnInset) / 2.0;
    col.resizingMask = NSTableColumnUserResizingMask;
    col.sortDescriptorPrototype = [[NSSortDescriptor alloc] initWithKey:@"duration" ascending:YES selector:@selector(compare:)];
    [_songsTable addTableColumn:col];
    
    col = [[NSTableColumn alloc] initWithIdentifier:kSongsColArtist];
    col.title = NSLocalizedString(@"table.songs.artist", @"Table column title");
    col.width = artistColumnWidth - selectorColumnInset;
    col.minWidth = (artistColumnWidth - selectorColumnInset) / 2.0;
    col.resizingMask = NSTableColumnUserResizingMask;
    col.sortDescriptorPrototype = [[NSSortDescriptor alloc] initWithKey:@"artist" ascending:YES selector:@selector(compare:)];
    [_songsTable addTableColumn:col];
    
    col = [[NSTableColumn alloc] initWithIdentifier:kSongsColAlbum];
    col.title = NSLocalizedString(@"table.songs.album", @"Table column title");
    col.width = albumColumnWidth - selectorColumnInset;
    col.minWidth = (albumColumnWidth - selectorColumnInset) / 2.0;
    col.resizingMask = NSTableColumnUserResizingMask;
    col.sortDescriptorPrototype = [[NSSortDescriptor alloc] initWithKey:@"album" ascending:YES selector:@selector(compare:)];
    [_songsTable addTableColumn:col];
    
    col = [[NSTableColumn alloc] initWithIdentifier:kSongsColGenre];
    col.title = NSLocalizedString(@"table.songs.genre", @"Table column title");
    col.width = genreColumnWidth - selectorColumnInset;
    col.minWidth = (genreColumnWidth - selectorColumnInset) / 2.0;
    col.resizingMask = NSTableColumnAutoresizingMask | NSTableColumnUserResizingMask;
    col.sortDescriptorPrototype = [[NSSortDescriptor alloc] initWithKey:@"genre" ascending:YES selector:@selector(compare:)];
    [_songsTable addTableColumn:col];
    
    col = [[NSTableColumn alloc] initWithIdentifier:kSongsColAdded];
    col.title = NSLocalizedString(@"table.songs.added", @"Table column title");
    col.width = addedColumnWidth - selectorColumnInset;
    col.minWidth = (addedColumnWidth - selectorColumnInset) / 2.0;
    col.resizingMask = NSTableColumnUserResizingMask;
    col.sortDescriptorPrototype = [[NSSortDescriptor alloc] initWithKey:@"added" ascending:YES selector:@selector(compare:)];
    [_songsTable addTableColumn:col];
    
    col = [[NSTableColumn alloc] initWithIdentifier:kSongsColTempo];
    col.title = NSLocalizedString(@"table.songs.tempo", @"Table column title");
    col.width = tempoColumnWidth - selectorColumnInset;
    col.minWidth = (tempoColumnWidth - selectorColumnInset) / 2.0;
    col.resizingMask = NSTableColumnUserResizingMask;
    col.sortDescriptorPrototype = [[NSSortDescriptor alloc] initWithKey:@"tempo" ascending:YES selector:@selector(compare:)];
    [_songsTable addTableColumn:col];
    
    col = [[NSTableColumn alloc] initWithIdentifier:kSongsColKey];
    col.title = NSLocalizedString(@"table.songs.key", @"Table column title");
    col.width = keyColumnWidth - selectorColumnInset;
    col.minWidth = (keyColumnWidth - selectorColumnInset) / 2.0;
    col.resizingMask = NSTableColumnUserResizingMask;
    col.sortDescriptorPrototype = [[NSSortDescriptor alloc] initWithKey:@"key" ascending:YES selector:@selector(compare:)];
    [_songsTable addTableColumn:col];
    
    col = [[NSTableColumn alloc] initWithIdentifier:kSongsColRating];
    col.title = NSLocalizedString(@"table.songs.rating", @"Table column title");
    col.width = ratingColumnWidth - selectorColumnInset;
    col.minWidth = (ratingColumnWidth - selectorColumnInset) / 2.0;
    col.resizingMask = NSTableColumnUserResizingMask;
    col.sortDescriptorPrototype = [[NSSortDescriptor alloc] initWithKey:@"rating" ascending:YES selector:@selector(compare:)];
    [_songsTable addTableColumn:col];
    
    col = [[NSTableColumn alloc] initWithIdentifier:kSongsColTags];
    col.title = NSLocalizedString(@"table.songs.tags", @"Table column title");
    col.minWidth = (tagsColumnWidth - selectorColumnInset) / 2.0;
    col.resizingMask = NSTableColumnAutoresizingMask;
    col.sortDescriptorPrototype = [[NSSortDescriptor alloc] initWithKey:@"tags" ascending:YES selector:@selector(compare:)];
    [_songsTable addTableColumn:col];
    
    sv.documentView = _songsTable;
    [_horizontalSplitView addArrangedSubview:sv];
    
    // Empty-state prompt to import from Apple Music. Overlays the songs table.
    _importButton = [NSButton buttonWithTitle:NSLocalizedString(@"library.import.button_title", @"Import library button title")
                                       target:self
                                       action:@selector(loadITunesLibrary:)];
    _importButton.translatesAutoresizingMaskIntoConstraints = NO;
    _importButton.bezelStyle = NSBezelStyleRounded;
    _importButton.hidden = YES;
    [sv.contentView addSubview:_importButton];
    [NSLayoutConstraint activateConstraints:@[
        [_importButton.centerXAnchor constraintEqualToAnchor:sv.contentView.centerXAnchor],
        [_importButton.centerYAnchor constraintEqualToAnchor:sv.contentView.centerYAnchor]
    ]];
    
    _importLabel = [NSTextField textFieldWithString:NSLocalizedString(@"library.import.in_progress", @"Import in progress label")];
    _importLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _importLabel.editable = NO;
    _importLabel.font = [[Defaults sharedDefaults] smallFont];
    _importLabel.hidden = YES;
    _importLabel.drawsBackground = NO;
    _importLabel.textColor = [NSColor secondaryLabelColor];
    _importLabel.bordered = NO;
    _importLabel.cell.truncatesLastVisibleLine = YES;
    _importLabel.cell.lineBreakMode = NSLineBreakByTruncatingTail;
    _importLabel.alignment = NSTextAlignmentCenter;
    [sv.contentView addSubview:_importLabel];
    [NSLayoutConstraint activateConstraints:@[
        [_importLabel.centerXAnchor constraintEqualToAnchor:sv.contentView.centerXAnchor],
        [_importLabel.centerYAnchor constraintEqualToAnchor:sv.contentView.centerYAnchor]
    ]];

    _importProgress = [[NSProgressIndicator alloc] initWithFrame:NSZeroRect];
    _importProgress.translatesAutoresizingMaskIntoConstraints = NO;
    _importProgress.indeterminate = NO;
    _importProgress.minValue = 0.0;
    _importProgress.maxValue = 1.0;
    _importProgress.hidden = YES;
    _importProgress.style = NSProgressIndicatorStyleBar;
    _importProgress.controlSize = NSControlSizeMini;
    CIColor* color = [[CIColor alloc] initWithColor:[NSColor whiteColor]];
    CIFilter* colorFilter = [CIFilter filterWithName:@"CIColorMonochrome" withInputParameters:@{@"inputColor" : color}];
    _importProgress.contentFilters = @[ colorFilter ];
    [sv.contentView addSubview:_importProgress];
    [NSLayoutConstraint activateConstraints:@[
        [_importProgress.centerXAnchor constraintEqualToAnchor:sv.contentView.centerXAnchor],
        [_importProgress.topAnchor constraintEqualToAnchor:_importLabel.bottomAnchor constant:8.0],
        [_importProgress.widthAnchor constraintEqualToConstant:300.0]
    ]];

    [self.window.contentView addSubview:_horizontalSplitView];
}

- (void)windowDidLoad
{
    [super windowDidLoad];

    NSUserDefaults* userDefaults = [NSUserDefaults standardUserDefaults];

    // The following assignments can not happen earlier - they rely on the fact
    // that the controls in question have a parent view / window.
    _horizontalSplitView.autosaveName = @"WindowSplitters";
    _browserColumnSplitView.autosaveName = @"BrowserColumnSplitters";

    _genreTable.autosaveName = @"GenresTable";
    _artistsTable.autosaveName = @"ArtistsTable";
    _albumsTable.autosaveName = @"AlbumsTable";
    _temposTable.autosaveName = @"TemposTable";
    _keysTable.autosaveName = @"KeysTable";
    _ratingsTable.autosaveName = @"RatingsTable";
    _tagsTable.autosaveName = @"TagsTable";
    _songsTable.autosaveName = @"SongsTable";

    // Replace the header cell in all of the main tables on this view.
    NSArray<NSTableView*>* fixupTables = @[ _songsTable, _genreTable, _artistsTable, _albumsTable, _temposTable, _keysTable, _ratingsTable, _tagsTable ];
    for (NSTableView* table in fixupTables) {
        for (NSTableColumn* column in [table tableColumns]) {
            TableHeaderCell* cell = [[TableHeaderCell alloc] initTextCell:[[column headerCell] stringValue]];
            [column setHeaderCell:cell];
        }
        table.backgroundColor = [NSColor clearColor];
        table.style = NSTableViewStylePlain;
        table.autosaveTableColumns = YES;
        table.allowsEmptySelection = NO;
    }

    _browser = [[BrowserController alloc] initWithGenresTable:_genreTable
                                                 artistsTable:_artistsTable
                                                  albumsTable:_albumsTable
                                                  temposTable:_temposTable
                                                   songsTable:_songsTable
                                                    keysTable:_keysTable
                                                 ratingsTable:_ratingsTable
                                                    tagsTable:_tagsTable
                                                  searchField:_searchField
                                                     delegate:self];
    for (NSTableView* table in fixupTables) {
        table.delegate = _browser;
        table.dataSource = _browser;
    }

    _sample = nil;

    _inTransition = NO;

    _effectBelowPlaylist.material = NSVisualEffectMaterialMenu;
    _effectBelowPlaylist.blendingMode = NSVisualEffectBlendingModeWithinWindow;
    _effectBelowPlaylist.alphaValue = 0.0f;

    _smallBelowVisualsFrame = _belowVisuals.frame;

    CGRect rect = CGRectMake(0.0, 0.0, self.window.frame.size.width, self.window.frame.size.height);
    CGRect contentRect = [self.window contentRectForFrameRect:rect];
    _windowBarHeight = self.window.frame.size.height - contentRect.size.height;

    [self.window registerForDraggedTypes:[NSArray arrayWithObjects:NSPasteboardTypeFileURL, NSPasteboardTypeSound, nil]];
    self.window.delegate = self;

    [self.renderer loadMetalWithView:self.scopeView];

    [self setupDisplayLink];

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(someWindowWillClose:) name:@"NSWindowWillCloseNotification" object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(activitiesUpdated:) name:ActivityManagerDidUpdateNotification object:nil];

    NSNumber* fullscreenValue = [userDefaults objectForKey:@"fullscreen"];
    if ([fullscreenValue boolValue]) {
        [self.window toggleFullScreen:self];
    }

    [_playlist readFromDefaults];
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
    [_displayLink addToRunLoop:[NSRunLoop currentRunLoop] forMode:NSRunLoopCommonModes];
}

/**
 This method is used in the process of finding a target for an action method. If
this NSResponder instance does not itself respondsToSelector:action, then
 supplementalTargetForAction:sender: is called. This method should return an
object which responds to the action; if this responder does not have a
supplemental object that does that, the implementation of this method should
call super's supplementalTargetForAction:sender:.

 NSResponder's implementation returns nil.
**/
- (id)supplementalTargetForAction:(SEL)action sender:(id)sender
{
    NSLog(@"action: %@", NSStringFromSelector(action));
    id target = [super supplementalTargetForAction:action sender:sender];

    if (target != nil) {
        return target;
    }

    NSArray* controllers = @[ _browser, _playlist, _tracklist ];

    for (NSResponder* childViewController in controllers) {
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

- (void)windowWillClose:(NSNotification*)notification
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

    NSLog(@"current path: %@", [recentURL filePathURL]);
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
                                    relativeToURL:nil  // Make it app-scoped
                                            error:&error];
    if (error) {
        NSLog(@"Error creating bookmark for URL (%@): %@", recentURL, error);
        [NSApp presentError:error];
    }
    [userDefaults setObject:bookmark forKey:@"bookmark"];

    [_playlist writeToDefaults];

    // Abort all the async operations that might be in flight.
    [_audioController decodeAbortWithCallback:^{
    }];
}

- (void)windowDidEndLiveResize:(NSNotification*)notification
{
    // The scope view takes are of itself by reacting to `viewDidEndLiveResize`.
    [_totalVisual setPixelPerSecond:_totalWaveViewController.view.bounds.size.width / _sample.duration];
    [_totalWaveViewController resize];
    [_scrollingWaveViewController resize];
}

- (void)windowDidResize:(NSNotification*)notification
{
    NSLog(@"windowDidResize with `ContentView` to height %f", self.window.contentView.bounds.size.height);
    NSLog(@"windowDidResize with `BelowVisuals` to height %f", _belowVisuals.bounds.size.height);

    NSSize newSize = NSMakeSize(_belowVisuals.bounds.size.width, _belowVisuals.bounds.size.height - (_totalWaveViewController.view.bounds.size.height +
                                                                                                     _scrollingWaveViewController.view.bounds.size.height));
    if (_scopeView.frame.size.width != newSize.width || _scopeView.frame.size.height != newSize.height) {
        NSLog(@"windowDidResize with `ScopeView` to %f x %f", newSize.width, newSize.height);
        [_renderer mtkView:_scopeView drawableSizeWillChange:newSize];
    } else {
        NSLog(@"windowDidResize with `ScopeView` remaining as is");
    }
}

- (void)windowWillEnterFullScreen:(NSNotification*)notification
{
    NSLog(@"windowWillEnterFullScreen: %@\n", notification);
    _inTransition = YES;

    _preFullscreenFrame = self.window.frame;
    _smallBelowVisualsFrame = _belowVisuals.frame;
}

- (void)windowDidEnterFullScreen:(NSNotification*)notification
{
    NSLog(@"windowDidEnterFullScreen\n");
    _inTransition = NO;
}

- (void)windowWillExitFullScreen:(NSNotification*)notification
{
    NSLog(@"windowWillExitFullScreen\n");
    _inTransition = YES;
}

- (void)windowDidExitFullScreen:(NSNotification*)notification
{
    NSLog(@"windowDidExitFullScreen\n");
    _inTransition = NO;
}

- (NSArray*)customWindowsToEnterFullScreenForWindow:(NSWindow*)window
{
    return [NSArray arrayWithObjects:[self window], nil];
}

- (NSArray*)customWindowsToExitFullScreenForWindow:(NSWindow*)window
{
    return [NSArray arrayWithObjects:[self window], nil];
}

- (void)window:(NSWindow*)window startCustomAnimationToEnterFullScreenWithDuration:(NSTimeInterval)duration
{
    NSLog(@"startCustomAnimationToEnterFullScreenWithDuration\n");

    [NSAnimationContext
        runAnimationGroup:^(NSAnimationContext* context) {
            [context setDuration:duration];
            [self relayoutAnimated:YES];
            [window.animator setFrame:[[NSScreen mainScreen] frame] display:YES];
        }
        completionHandler:^{
            [CATransaction begin];
            [CATransaction setDisableActions:YES];
            [window setStyleMask:([window styleMask] | NSWindowStyleMaskFullScreen)];
            //[window.contentView addSubview:self.belowVisuals];
            self.belowVisuals.frame = NSMakeRect(0.0f, 0.0f, window.screen.frame.size.width, window.screen.frame.size.height);
            //[self putScopeViewWithFrame:NSMakeRect(0.0f, 0.0f,
            //window.screen.frame.size.width, window.screen.frame.size.height)
            //onView:window.contentView];
            [CATransaction commit];
        }];
}

- (void)window:(NSWindow*)window startCustomAnimationToExitFullScreenWithDuration:(NSTimeInterval)duration
{
    NSLog(@"startCustomAnimationToExitFullScreenWithDuration\n");

    [NSAnimationContext
        runAnimationGroup:^(NSAnimationContext* context) {
            [context setDuration:duration];
            [window.animator setFrame:_preFullscreenFrame display:YES];
            [self relayoutAnimated:NO];
        }
        completionHandler:^{
            [CATransaction begin];
            [CATransaction setDisableActions:YES];
            [window setStyleMask:([window styleMask] & ~NSWindowStyleMaskFullScreen)];
            //[self.split replaceSubview:<#(nonnull NSView *)#> with:<#(nonnull
            //NSView *)#>]; self.belowVisuals.frame = self.smallBelowVisualsFrame;
            //[self putScopeViewWithFrame:self.smallBelowVisualsFrame
            //onView:self.belowVisuals];
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

    _songsCount.animator.hidden = toFullscreen ? YES : NO;

    if (toFullscreen) {
        memcpy(splitPositionMemory, splitPosition, sizeof(CGFloat) * kSplitPositionCount);
        // Restore the old positions.
        [_browserColumnSplitView setPosition:splitSelectorPositionMemory[kBrowserSplitIndexGenres] ofDividerAtIndex:kBrowserSplitIndexGenres];
        [_browserColumnSplitView setPosition:splitSelectorPositionMemory[kBrowserSplitIndexAlbums] ofDividerAtIndex:kBrowserSplitIndexAlbums];
        [_browserColumnSplitView setPosition:splitSelectorPositionMemory[kBrowserSplitIndexArtists] ofDividerAtIndex:kBrowserSplitIndexArtists];
        [_browserColumnSplitView setPosition:splitSelectorPositionMemory[kBrowserSplitIndexTempos] ofDividerAtIndex:kBrowserSplitIndexTempos];
        [_browserColumnSplitView setPosition:splitSelectorPositionMemory[kBrowserSplitIndexKey] ofDividerAtIndex:kBrowserSplitIndexKey];
        [_browserColumnSplitView setPosition:splitSelectorPositionMemory[kBrowserSplitIndexRatings] ofDividerAtIndex:kBrowserSplitIndexRatings];
        [_browserColumnSplitView setPosition:splitSelectorPositionMemory[kBrowserSplitIndexTags] ofDividerAtIndex:kBrowserSplitIndexTags];
    }

    [_browserColumnSplitView adjustSubviews];

    _browserColumnSplitView.animator.hidden = toFullscreen ? YES : NO;

    _songsTable.enclosingScrollView.animator.hidden = toFullscreen ? YES : NO;

    if (!toFullscreen) {
        // We quickly stash the position memory for making sure the first position
        // set can trash the stored positions immediately.
        // CGFloat positions[kSplitPositionCount];
        // memcpy(positions, splitPositionMemory, sizeof(CGFloat) *
        // kSplitPositionCount);
        [_horizontalSplitView setPosition:splitPositionMemory[kWindowSplitIndexVisuals] ofDividerAtIndex:kWindowSplitIndexVisuals];
        [_horizontalSplitView setPosition:splitPositionMemory[kWindowSplitIndexBrowser] ofDividerAtIndex:kWindowSplitIndexBrowser];
    }
    [_horizontalSplitView adjustSubviews];
    NSLog(@"relayout to fullscreen %X\n", toFullscreen);
}

- (void)someWindowWillClose:(NSNotification*)notification
{
    id object = notification.object;
    if (object == _identifyWindowController.window) {
        _identifyToolbarButton.state = NSControlStateValueOff;
    }
}

- (void)setPlaybackActive:(BOOL)active
{
    _controlPanelController.playPause.state = active ? NSControlStateValueOn : NSControlStateValueOff;
    //_identifyToolbarButton.enabled = active ? YES : NO;
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

- (void)listsSwitched:(id)sender
{
    [_listsTabView selectTabViewItemAtIndex:[sender selectedSegment]];
}

- (void)showActivity:(id)sender
{
    NSPanel* window = nil;

    if (_activityWindowController == nil) {
        self.activityWindowController = [NSWindowController new];
    }
    if (_activityViewController == nil) {
        self.activityViewController = [[ActivityViewController alloc] init];
        [_activityViewController view];
        NSPanel* panel = [NSPanel windowWithContentViewController:_activityViewController];
        window = panel;
        window.styleMask &= ~(NSWindowStyleMaskResizable | NSWindowStyleMaskMiniaturizable);
        window.titleVisibility = NSWindowTitleVisible;
        window.movableByWindowBackground = YES;
        window.hidesOnDeactivate = NO;
        window.floatingPanel = NO;
        window.titlebarAppearsTransparent = NO;
        window.titlebarSeparatorStyle = NSTitlebarSeparatorStyleShadow;
        window.level = NSNormalWindowLevel;
        window.title = NSLocalizedString(@"activity.window_title", @"Title for the Activity window");
        _activityWindowController.window = window;
    } else {
        window = (NSPanel*) self.activityWindowController.window;
    }
    window.floatingPanel = NO;
    [window makeKeyAndOrderFront:nil];
}

- (void)showGraphStatus:(id)sender
{
    NSPanel* window = nil;

    if (_graphStatusWindowController == nil) {
        self.graphStatusWindowController = [NSWindowController new];
    }

    if (_graphStatusWindowController.window == nil) {
        GraphStatusViewController* vc = [[GraphStatusViewController alloc] initWithAudioController:self.audioController sample:self.sample];
        [vc updateSample:self.sample];
        [vc view];
        NSPanel* panel = [NSPanel windowWithContentViewController:vc];
        window = panel;
        window.styleMask &= ~(NSWindowStyleMaskResizable);
        window.titleVisibility = NSWindowTitleVisible;
        window.movableByWindowBackground = YES;
        window.titlebarAppearsTransparent = NO;
        window.level = NSNormalWindowLevel;
        window.hidesOnDeactivate = NO;
        window.floatingPanel = NO;
        window.titlebarSeparatorStyle = NSTitlebarSeparatorStyleShadow;
        window.title = NSLocalizedString(@"graph.status.window_title", @"Title for the audio graph status window");
        NSSize size = NSMakeSize(360.0, 220.0);
        [window setContentSize:size];
        _graphStatusWindowController.window = window;
    } else {
        window = (NSPanel*) _graphStatusWindowController.window;
        if ([window.contentViewController isKindOfClass:[GraphStatusViewController class]]) {
            GraphStatusViewController* vc = (GraphStatusViewController*) window.contentViewController;
            [vc updateSample:self.sample];
        }
    }
    [window makeKeyAndOrderFront:nil];
}

- (void)showEffects:(id)sender
{
    [_fxViewController updateEffects:_audioController.availableEffects];
    [_fxViewController showWithParent:self.window];
}

- (void)showPlaylist:(id)sender
{
    BOOL isShow = _effectBelowPlaylist.alphaValue <= 0.05f;

    _playlistToolbarButton.state = isShow ? NSControlStateValueOn : NSControlStateValueOff;

    if (isShow) {
        _effectBelowPlaylist.alphaValue = 1.0f;
    }

    [NSAnimationContext
        runAnimationGroup:^(NSAnimationContext* context) {
            // CGFloat maxX = 0;
            [context setDuration:kShowHidePanelAnimationDuration];
            if (isShow) {
                _effectBelowPlaylist.animator.frame =
                    NSMakeRect(self.window.contentView.frame.origin.x + self.window.contentView.frame.size.width - _effectBelowPlaylist.frame.size.width,
                               _effectBelowPlaylist.frame.origin.y, _effectBelowPlaylist.frame.size.width, _effectBelowPlaylist.frame.size.height);
            } else {
                _effectBelowPlaylist.animator.frame =
                    NSMakeRect(self.window.contentView.frame.origin.x + self.window.contentView.frame.size.width, _effectBelowPlaylist.frame.origin.y,
                               _effectBelowPlaylist.frame.size.width, _effectBelowPlaylist.frame.size.height);
            }
        }
        completionHandler:^{
            if (!isShow) {
                self.effectBelowPlaylist.alphaValue = 0.0f;
            }
        }];
}

- (void)showIdentifier:(id)sender
{
    _identifyToolbarButton.state = NSControlStateValueOn;

    NSApplication* sharedApplication = [NSApplication sharedApplication];

    NSPanel* window = (NSPanel*) _identifyWindowController.window;
    if (window.isVisible) {
        [window close];
        return;
    }

    if (_identifyWindowController == nil) {
        self.identifyWindowController = [NSWindowController new];
    }

    if (_iffy == nil) {
        self.iffy = [[IdentifyViewController alloc] initWithAudioController:_audioController delegate:self];
        [_iffy view];

        NSPanel* panel = [NSPanel windowWithContentViewController:_iffy];
        window = panel;
        window.styleMask &= ~NSWindowStyleMaskResizable | NSWindowStyleMaskTitled;
        window.floatingPanel = NO;
        window.level = NSNormalWindowLevel;
        window.titleVisibility = NSWindowTitleHidden;
        window.movableByWindowBackground = YES;
        window.becomesKeyOnlyIfNeeded = YES;
        window.hidesOnDeactivate = NO;
        window.titlebarAppearsTransparent = YES;
        window.appearance = sharedApplication.mainWindow.appearance;
        [window standardWindowButton:NSWindowCloseButton].hidden = NO;
        [window standardWindowButton:NSWindowZoomButton].hidden = YES;
        [window standardWindowButton:NSWindowMiniaturizeButton].hidden = YES;
        _identifyWindowController.window = window;
    } else {
        window = (NSPanel*) _identifyWindowController.window;
    }
    [_iffy setCurrentIdentificationSource:_meta.location];
    window.floatingPanel = NO;

    [window makeKeyAndOrderFront:nil];
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
        window = (NSPanel*) self.aboutWindowController.window;
    }
    [window setFloatingPanel:YES];
    [window makeKeyAndOrderFront:nil];
}

- (NSURL*)currentDetectionSourceLocation
{
    return _meta.location;
}

- (void)addTrackToTracklist:(TimedMediaMetaData*)track
{
    [_tracklist addTrack:track];
    [_totalWaveViewController reloadTracklist];
    [_scrollingWaveViewController reloadTracklist];
}

- (void)startTrackDetection:(id)sender
{
    WaveWindowController* __weak weakSelf = self;

    void (^continuation)(void) = ^(void) {
        WaveWindowController* strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }

        strongSelf->_totalIdentificationController = [[TotalIdentificationController alloc] initWithSample:strongSelf->_audioController.sample];
        strongSelf->_totalIdentificationController.referenceArtist = strongSelf->_meta.artist;
#ifdef DEBUG
        strongSelf->_totalIdentificationController.debugScoring = YES;
#endif

        // Start the complete detection and let the tracklist-controller know that
        // we have an ongoing activity - that way this can be reflected visually.
        strongSelf->_tracklist.detectionToken =
            [strongSelf->_totalIdentificationController detectTracklistWithCallback:^(BOOL done, NSError* error, NSArray<TimedMediaMetaData*>* tracks) {
                WaveWindowController* strongSelf = weakSelf;
                if (!strongSelf) {
                    return;
                }
                if (!done) {
                    NSLog(@"detection failed with: %@", error);
                    return;
                }

                [strongSelf->_tracklist addTracks:tracks];
                [strongSelf->_totalWaveViewController reloadTracklist];
                [strongSelf->_scrollingWaveViewController reloadTracklist];
            }];
    };

    // Detect is destructive when it comes to our tracklist.
    if (_meta.trackList.tracks.count > 0) {
        NSAlert* alert = [[NSAlert alloc] init];
        [alert setMessageText:NSLocalizedString(@"alert.tracklist.drop.message", @"Alert message for dropping existing tracklist")];
        [alert setInformativeText:NSLocalizedString(@"alert.tracklist.drop.informative", @"Alert info when dropping tracklist")];
        [alert addButtonWithTitle:NSLocalizedString(@"alert.tracklist.drop.confirm", @"Drop tracklist button title")];
        [alert addButtonWithTitle:NSLocalizedString(@"alert.tracklist.drop.cancel", @"Cancel drop tracklist button title")];
        [alert setAlertStyle:NSAlertStyleWarning];

        [alert beginSheetModalForWindow:self.window
                      completionHandler:^(NSModalResponse returnCode) {
                          WaveWindowController* strongSelf = weakSelf;
                          if (!strongSelf) {
                              return;
                          }

                          if (returnCode == NSAlertSecondButtonReturn) {
                              NSLog(@"user decided to leave tracklist as is");
                              return;
                          }

                          NSLog(@"user decided to overwrite tracklist");
                          [strongSelf->_tracklist clearTracklist];
                          continuation();
                      }];
    } else {
        continuation();
    }
}

- (void)setBPM:(float)bpm
{
    if (_visibleBPM == bpm) {
        return;
    }

    _visibleBPM = bpm;

    NSString* display = bpm < 0.5f ? @"" : [NSString stringWithFormat:@"%3.0f BPM", floorf(bpm)];
    _controlPanelController.bpm.stringValue = display;

    [[NSNotificationCenter defaultCenter] postNotificationName:kBeatTrackedSampleTempoChangeNotification object:@(bpm)];
}

- (void)setCurrentFrame:(unsigned long long)frame
{
    _renderer.currentFrame = frame;

    // There is no deeper meaning in using the scrolling wave view controller as our
    // source of truth here.
    if (_scrollingWaveViewController.currentFrame == frame) {
        return;
    }

    // We throttle the time / duration display updates to easy the load.
    if (!_timeUpdateScheduled && _controlPanelController.durationUnitTime) {
        _timeUpdateScheduled = YES;
        __weak typeof(self) weakSelf = self;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            typeof(self) strongSelf = weakSelf;
            if (strongSelf == nil) {
                return;
            }
            LazySample* sample = strongSelf->_audioController.sample;
            if (sample == nil) {
                return;
            }
            unsigned long long adaptedFrame = (unsigned long long)((float)frame / strongSelf->_audioController.tempoShift);
            unsigned long long adaptedFramesLeft = (unsigned long long)(((float)(sample.frames - frame) + 1.0f) / strongSelf->_audioController.tempoShift);
            NSString* duration = [sample beautifulTimeWithFrame:adaptedFramesLeft];
            NSString* time = [sample beautifulTimeWithFrame:adaptedFrame];
            [strongSelf->_controlPanelController updateDuration:duration time:time];
            strongSelf->_timeUpdateScheduled = NO;
        });
    }

    _scrollingWaveViewController.currentFrame = frame;
    _totalWaveViewController.currentFrame = frame;
    _tracklist.currentFrame = frame;

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
}

- (IBAction)loadITunesLibrary:(id)sender
{
    _importButton.hidden = YES;
    _importLabel.hidden = NO;
    _importProgress.hidden = NO;
    _importToken = [[ActivityManager shared] beginActivityWithTitle:NSLocalizedString(@"activity.library.update_from_apple", @"Title for updating from Apple Music library")
                                                            detail:@""
                                                       cancellable:NO
                                                     cancelHandler:nil];
    [_browser loadITunesLibraryWithToken:_importToken];
}

#pragma mark - Splitter delegate

- (BOOL)splitView:(NSSplitView*)splitView canCollapseSubview:(NSView*)view
{
    return view != _searchField;
}

- (void)splitViewDidResizeSubviews:(NSNotification*)notification
{
    /*
       A notification that is posted to the default notification center by
     NSSplitView when a split view has just resized its subviews either as a
     result of its own resizing or during the dragging of one of its dividers by
     the user. Starting in Mac OS 10.5, if the notification is being sent
     because the user is dragging a divider, the notification's user info
     dictionary contains an entry whose key is
       @"NSSplitViewDividerIndex" and whose value is an NSInteger-wrapping
     NSNumber that is the index of the divider being dragged. Starting in Mac
     OS 12.0, the notification will contain the user info dictionary during
     resize and layout events as well.
  */
    NSSplitView* sv = notification.object;
    NSNumber* indexNumber = notification.userInfo[@"NSSplitViewDividerIndex"];

    if (indexNumber == nil) {
        return;
    }

    if (sv == _browserColumnSplitView) {
        switch (indexNumber.intValue) {
        case kBrowserSplitIndexGenres:
            splitSelectorPositionMemory[kBrowserSplitIndexGenres] = _genreTable.enclosingScrollView.bounds.size.width;
            break;
        case kBrowserSplitIndexArtists:
            splitSelectorPositionMemory[kBrowserSplitIndexArtists] = _artistsTable.enclosingScrollView.bounds.size.width;
            break;
        case kBrowserSplitIndexAlbums:
            splitSelectorPositionMemory[kBrowserSplitIndexAlbums] = _albumsTable.enclosingScrollView.bounds.size.width;
            break;
        case kBrowserSplitIndexTempos:
            splitSelectorPositionMemory[kBrowserSplitIndexTempos] = _temposTable.enclosingScrollView.bounds.size.width;
            break;
        case kBrowserSplitIndexKey:
            splitSelectorPositionMemory[kBrowserSplitIndexKey] = _keysTable.enclosingScrollView.bounds.size.width;
            break;
        case kBrowserSplitIndexRatings:
            splitSelectorPositionMemory[kBrowserSplitIndexRatings] = _ratingsTable.enclosingScrollView.bounds.size.width;
            break;
        case kBrowserSplitIndexTags:
            splitSelectorPositionMemory[kBrowserSplitIndexTags] = _tagsTable.enclosingScrollView.bounds.size.width;
            break;
        }
    } else if (sv == _horizontalSplitView) {
        switch (indexNumber.intValue) {
        case kWindowSplitIndexVisuals: {
            NSSize newSize = NSMakeSize(_belowVisuals.bounds.size.width,
                                        _belowVisuals.bounds.size.height -
                                            (_scrollingWaveViewController.view.bounds.size.height + _totalWaveViewController.view.bounds.size.height));

            if (_scopeView.frame.size.width != newSize.width || _scopeView.frame.size.height != newSize.height) {
                NSLog(@"splitViewDidResizeSubviews with `ScopeView` to %f x %f", newSize.width, newSize.height);
                [_renderer mtkView:_scopeView drawableSizeWillChange:newSize];
            } else {
                NSLog(@"splitViewDidResizeSubviews with `ScopeView` remaining as is");
            }
            break;
        }
        }
        CGFloat y = _belowVisuals.bounds.size.height;
        splitPosition[kWindowSplitIndexVisuals] = y;
        //        if (_filtering) {
        //            splitPosition[kWindowSplitIndexFilter] =
        //            _belowVisuals.bounds.size.height +
        //            _searchField.bounds.size.height;
        //        }
        splitPosition[kWindowSplitIndexBrowser] = _belowVisuals.bounds.size.height + _browserColumnSplitView.bounds.size.height;
    }
}

#pragma mark - Media Remote Commands

- (NSArray*)remoteCommands
{
    MPRemoteCommandCenter* cc = [MPRemoteCommandCenter sharedCommandCenter];
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

- (MPRemoteCommandHandlerStatus)remoteCommandEvent:(MPRemoteCommandEvent*)event
{
    MPRemoteCommandCenter* cc = [MPRemoteCommandCenter sharedCommandCenter];
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
        MPChangePlaybackPositionCommandEvent* positionEvent = (MPChangePlaybackPositionCommandEvent*) event;
        [self seekToTime:positionEvent.positionTime + 1];
        return MPRemoteCommandHandlerStatusSuccess;
    }
    if (event.command == cc.nextTrackCommand) {
        [self playNext:self];
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

    NSLog(@"%s was not able to handle remote control event '%s'", __PRETTY_FUNCTION__, [event.description UTF8String]);

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
    commandCenter.skipForwardCommand.preferredIntervals = @[ @(10.0) ];
    commandCenter.skipBackwardCommand.preferredIntervals = @[ @(10.0) ];
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
        for (NSURL* url in [openDlg URLs]) {
            [self loadDocumentFromURL:[WaveWindowController encodeQueryItemsWithUrl:url frame:0LL playing:YES] meta:nil];
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

- (void)AudioControllerFXStateChange:(NSNotification*)notification
{
    NSDictionary* info = notification.userInfo ?: @{};
    BOOL enabled = [info[@"enabled"] boolValue];
    NSInteger idx = [info[@"index"] integerValue];
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSUserDefaults standardUserDefaults] setBool:enabled forKey:kFXLastEffectEnabledKey];
        [self.controlPanelController setEffectsEnabled:enabled];
        [self.fxViewController setEffectEnabledState:enabled];
        if (idx >= 0) {
            [self.fxViewController selectEffectIndex:idx];
        }
    });
}

typedef struct {
    BOOL playing;
    unsigned long long frame;
    NSString* path;
    MediaMetaData* meta;
} LoaderContext;

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

- (NSInteger)storedEffectSelectionIndex
{
    NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
    NSDictionary* stored = [defaults dictionaryForKey:kFXLastEffectDefaultsKey];
    if (stored == nil) {
        return -1;
    }
    UInt32 storedType = (UInt32)[stored[@"type"] unsignedIntValue];
    UInt32 storedSub = (UInt32)[stored[@"subtype"] unsignedIntValue];
    UInt32 storedManuf = (UInt32)[stored[@"manuf"] unsignedIntValue];

    for (NSUInteger i = 0; i < self.audioController.availableEffects.count; i++) {
        NSDictionary* entry = self.audioController.availableEffects[i];
        NSValue* packed = entry[@"component"];
        if (packed == nil || strcmp([packed objCType], @encode(AudioComponentDescription)) != 0) {
            continue;
        }
        AudioComponentDescription desc = {0};
        [packed getValue:&desc];
        if (desc.componentType == storedType && desc.componentSubType == storedSub && desc.componentManufacturer == storedManuf) {
            return (NSInteger) i;
        }
    }
    return -1;
}

- (void)persistEffectSelectionIndex:(NSInteger)index
{
    if (index < 0 || index >= (NSInteger) self.audioController.availableEffects.count) {
        return;
    }
    NSDictionary* entry = self.audioController.availableEffects[(NSUInteger) index];
    NSValue* packed = entry[@"component"];
    if (packed == nil || strcmp([packed objCType], @encode(AudioComponentDescription)) != 0) {
        return;
    }
    AudioComponentDescription desc = {0};
    [packed getValue:&desc];
    NSDictionary* stored = @{@"type" : @(desc.componentType), @"subtype" : @(desc.componentSubType), @"manuf" : @(desc.componentManufacturer)};
    NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
    [defaults setObject:stored forKey:kFXLastEffectDefaultsKey];
    [defaults setBool:YES forKey:kFXLastEffectEnabledKey];
}

- (void)clearPersistedEffectSelection
{
    NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
    [defaults removeObjectForKey:kFXLastEffectDefaultsKey];
    [defaults setBool:NO forKey:kFXLastEffectEnabledKey];
}

- (BOOL)loadDocumentFromURL:(NSURL*)url meta:(MediaMetaData*)meta
{
    NSError* error = nil;
    if (_audioController == nil) {
        _audioController = [AudioController new];
        _fxViewController.audioController = _audioController;
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(AudioControllerPlaybackStateChange:)
                                                     name:kAudioControllerChangedPlaybackStateNotification
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(AudioControllerFXStateChange:)
                                                     name:kPlaybackFXStateChanged
                                                   object:nil];
        __weak typeof(self) weakSelf = self;
        [_audioController refreshAvailableEffectsAsync:^(NSArray<NSDictionary*>* effects) {
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

    _loaderState = LoaderStateAbortingKeyDetection;

    WaveWindowController* __weak weakSelf = self;
    // The loader may already be active at this moment -- we abort it and hand
    // over our payload block when abort did its job.
    [self abortLoader:^{
        NSLog(@"loading new meta from: %@ ...", context.path);
        self->_loaderState = LoaderStateMeta;
        [weakSelf loadMetaWithContext:context];
    }];

    return YES;
}

- (void)loadMetaWithContext:(LoaderContext)context
{
    if (_loaderState == LoaderStateAborted) {
        return;
    }

    _loaderState = LoaderStateMeta;
    WaveWindowController* __weak weakSelf = self;

    ActivityToken* token = [[ActivityManager shared] beginActivityWithTitle:NSLocalizedString(@"activity.metadata.parse.title", @"Title for metadata parsing activity")
                                                                     detail:NSLocalizedString(@"activity.metadata.parse.loading_core", @"Detail while loading core metadata")
                                                                cancellable:NO
                                                              cancelHandler:nil];

    [_metaController loadAsyncWithPath:context.path
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

    self->_loaderState = LoaderStateAbortingKeyDetection;
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

            self->_loaderState = LoaderStateDecoder;
            [weakSelf loadSample:lazySample context:context];
        }];
    }];
}

- (void)abortLoader:(void (^)(void))callback
{
    WaveWindowController* __weak weakSelf = self;

    switch (_loaderState) {
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
                self->_loaderState = LoaderStateAbortingMeta;
                [self abortLoader:callback];
            }];
        } else {
            NSLog(@"decoder wasnt active, calling back...");
            _loaderState = LoaderStateAbortingMeta;
            [self abortLoader:callback];
        }
        break;
    case LoaderStateAbortingMeta:
        if (_meta != nil) {
            NSLog(@"attempting to abort meta loader...");
            [self->_metaController loadAbortWithCallback:^{
                NSLog(@"meta loader aborted, calling back...");
                self->_loaderState = LoaderStateAborted;
                callback();
            }];
        } else {
            NSLog(@"meta loader wasnt active, calling back...");
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

- (void)loadSample:(LazySample*)sample context:(LoaderContext)context
{
    if (_loaderState == LoaderStateAborted) {
        return;
    }
    NSLog(@"previous sample %p should get unretained now", _sample);
    _sample = sample;
    _visualSample = nil;
    _totalVisual = nil;
    _beatSample = nil;
    _keySample = nil;
    _scrollingWaveViewController.beatSample = nil;
    _scrollingWaveViewController.visualSample = nil;
    _totalWaveViewController.beatSample = nil;
    _totalWaveViewController.frames = 0;
    _totalWaveViewController.visualSample = nil;

    [self setBPM:0.0];
    
    _visualSample = [[VisualSample alloc] initWithSample:sample pixelPerSecond:kPixelPerSecond tileWidth:_scrollingWaveViewController.tileWidth];
    _scrollingWaveViewController.visualSample = _visualSample;
    assert(sample.renderedSampleRate > 0);
    
    // Ensure visuals size themselves using the actual render rate; warn if we are still at file rate in max-rate mode.
    BOOL followFileRate = ([[[NSProcessInfo processInfo] environment][@"PLAYEM_FIXED_DEVICE_RATE"] length] == 0);
    if (!followFileRate && fabs(sample.renderedSampleRate - sample.fileSampleRate) < 1.0) {
        NSLog(@"WaveWindowController: visuals created before renderedSampleRate updated (still at file rate %.1f kHz)",
              sample.fileSampleRate / 1000.0);
    }
    _totalVisual = [[VisualSample alloc] initWithSample:sample
                                         pixelPerSecond:_totalWaveViewController.view.bounds.size.width / sample.duration
                                              tileWidth:_totalWaveViewController.tileWidth
                                           reducedWidth:kReducedVisualSampleWidth];

    _totalWaveViewController.visualSample = _totalVisual;

    _scrollingWaveViewController.frames = sample.frames;
    _totalWaveViewController.frames = sample.frames;

    _scrollingWaveViewController.view.frame = CGRectMake(0.0, 0.0, self.visualSample.width, _scrollingWaveViewController.view.bounds.size.height);

    NSTimeInterval duration = [self.visualSample.sample timeForFrame:sample.frames];
    [_controlPanelController setKeyHidden:duration > kBeatSampleDurationThreshold];
    [_controlPanelController setKey:@"" hint:@""];
    
//    AudioObjectID deviceId = [AudioDevice defaultOutputDevice];
//    Float64 deviceRate = [AudioDevice sampleRateForDevice:deviceId];
//    Float64 sourceRate = sample.fileSampleRate;
//
//    // Inform the user if we will resample (mismatch), but do not switch device rates to avoid pops.
//    if (sourceRate > 0 && deviceRate > 0 && fabs(deviceRate - sourceRate) > 0.5 &&
//        ![[NSUserDefaults standardUserDefaults] boolForKey:kSkipRateMismatchWarning]) {
//        NSString* deviceName = [AudioDevice nameForDevice:deviceId] ?: @"audio device";
//
//        NSAlert* alert = [[NSAlert alloc] init];
//        alert.alertStyle = NSAlertStyleInformational;
//        alert.messageText = @"Resampling to match your audio device";
//        alert.informativeText = [NSString stringWithFormat:@"This file is %.1f kHz.\n%@ runs at %.1f kHz.\nWe'll resample before playback. This may take a little longer.",
//                                                           sourceRate / 1000.0,
//                                                           deviceName,
//                                                           deviceRate / 1000.0];
//        [alert addButtonWithTitle:@"OK"];
//
//        NSButton* checkbox = [[NSButton alloc] initWithFrame:NSZeroRect];
//        checkbox.buttonType = NSButtonTypeSwitch;
//        checkbox.title = @"Don’t show this again";
//        [checkbox sizeToFit];
//        NSView* accessory = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, checkbox.frame.size.width, checkbox.frame.size.height)];
//        [accessory addSubview:checkbox];
//        alert.accessoryView = accessory;
//
//        __block NSButton* blockCheckbox = checkbox;
//        [alert beginSheetModalForWindow:self.window
//                      completionHandler:^(NSModalResponse response) {
//                          if (blockCheckbox.state == NSControlStateValueOn) {
//                              [[NSUserDefaults standardUserDefaults] setBool:YES forKey:kSkipRateMismatchWarning];
//                          }
//                      }];
//    }

    NSLog(@"playback starting...");
    //[weakSelf.audioController playSample:lazySample frame:context.frame paused:!context.playing];


    _loaderState = LoaderStateDecoder;
    WaveWindowController* __weak weakSelf = self;
    [_audioController decodeAsyncWithSample:_sample
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
    BeatTrackedSample* beatSample = [[BeatTrackedSample alloc] initWithSample:_sample];

    _scrollingWaveViewController.beatSample = beatSample;
    _totalWaveViewController.beatSample = beatSample;

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
    _loaderState = LoaderStateBeatDetection;

    _beatSample = beatsSample;

    WaveWindowController* __weak weakSelf = self;

    [_beatSample trackBeatsAsyncWithCallback:^(BOOL beatsFinished) {
        if (beatsFinished) {
            [weakSelf beatsTracked];
        } else {
            NSLog(@"never finished the beat tracking");
        }
    }];
}

- (void)beatsTracked
{
    [_scrollingWaveViewController updateBeatMarkLayer];
    [_totalWaveViewController updateBeatMarkLayer];

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

    _loaderState = LoaderStateKeyDetection;

    _keySample = keySample;
    [_keySample trackKeyAsyncWithCallback:^(BOOL keyFinished) {
        if (keyFinished) {
            NSLog(@"key tracking finished");
            [self->_controlPanelController setKey:self->_keySample.key hint:self->_keySample.hint];
        } else {
            NSLog(@"never finished the key tracking");
        }
    }];
}

- (void)setPlaybackState:(MPNowPlayingPlaybackState)state
{
    MPNowPlayingInfoCenter* center = [MPNowPlayingInfoCenter defaultCenter];
    center.playbackState = state;
}

- (void)setNowPlayingWithMeta:(MediaMetaData*)meta
{
    NSMutableDictionary* songInfo = [[NSMutableDictionary alloc] init];
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
    NSImage* artworkImage = [meta imageFromArtwork];
    MPMediaItemArtwork* artwork = [[MPMediaItemArtwork alloc] initWithBoundsSize:artworkImage.size
                                                                  requestHandler:^(CGSize size) {
                                                                      return artworkImage;
                                                                  }];
    [songInfo setObject:artwork forKey:MPMediaItemPropertyArtwork];

    [songInfo setObject:@(_audioController.expectedDuration) forKey:MPMediaItemPropertyPlaybackDuration];
    [songInfo setObject:@(_audioController.currentTime) forKey:MPNowPlayingInfoPropertyElapsedPlaybackTime];
    [songInfo setObject:@(_audioController.tempoShift) forKey:MPNowPlayingInfoPropertyPlaybackRate];

    MPNowPlayingInfoCenter* center = [MPNowPlayingInfoCenter defaultCenter];
    center.nowPlayingInfo = songInfo;
}

- (void)setMeta:(MediaMetaData*)meta
{
    NSLog(@"WaveWindowController setMeta: %@", meta);
    _meta = meta;

    // FIXME: This feels icky -- we are distributing our state here - is that
    // really needed?

    // Update playlist in playlist box.
    _playlist.current = meta;
    // Update tracklist in tracklist box.
    _tracklist.current = meta;
    // Update meta data in playback box.
    _controlPanelController.meta = meta;
    // Update browser controller to show current song.
    _browser.currentMeta = meta;

    [_iffy setCurrentIdentificationSource:meta.location];

    // Update the media player item in the info bar (top right).
    [self setNowPlayingWithMeta:meta];

    _scrollingWaveViewController.trackList = meta.trackList;
    _totalWaveViewController.trackList = meta.trackList;
}

- (void)updateRemotePosition
{
    NSMutableDictionary* songInfo = [NSMutableDictionary dictionaryWithDictionary:[[MPNowPlayingInfoCenter defaultCenter] nowPlayingInfo]];
    [songInfo setObject:@(_audioController.expectedDuration) forKey:MPMediaItemPropertyPlaybackDuration];
    [songInfo setObject:@(_audioController.currentTime) forKey:MPNowPlayingInfoPropertyElapsedPlaybackTime];
    [[MPNowPlayingInfoCenter defaultCenter] setNowPlayingInfo:songInfo];
}

#pragma mark - Drag & Drop

- (NSDragOperation)draggingEntered:(id<NSDraggingInfo>)sender
{
    NSPasteboard* pboard = [sender draggingPasteboard];
    NSDragOperation sourceDragMask = [sender draggingSourceOperationMask];

    if ([[pboard types] containsObject:NSPasteboardTypeFileURL]) {
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

- (BOOL)performDragOperation:(id<NSDraggingInfo>)sender
{
    NSPasteboard* pboard = [sender draggingPasteboard];
    NSArray<NSURL*>* droppedURLs =
        [pboard readObjectsForClasses:@[ [NSURL class] ] options:@{ NSPasteboardURLReadingFileURLsOnlyKey : @YES }];
    if (droppedURLs.count == 0) {
        return NO;
    }

    NSMutableArray<NSURL*>* fileURLs = [NSMutableArray array];
    for (NSURL* url in droppedURLs) {
        [fileURLs addObjectsFromArray:[self mediaFileURLsFromURL:url]];
    }
    if (fileURLs.count == 0) {
        return NO;
    }

    // Add everything to the library and play the first item.
    [_browser importFilesAtURLs:fileURLs];

    NSURL* firstURL = fileURLs.firstObject;
    return [self loadDocumentFromURL:[WaveWindowController encodeQueryItemsWithUrl:firstURL frame:0LL playing:YES] meta:nil];
}

- (NSArray<NSURL*>*)mediaFileURLsFromURL:(NSURL*)url
{
    if (url == nil || !url.isFileURL) {
        return @[];
    }

    NSNumber* isDirectory = nil;
    if (![url getResourceValue:&isDirectory forKey:NSURLIsDirectoryKey error:nil]) {
        return @[];
    }

    if (![isDirectory boolValue]) {
        return @[ url ];
    }

    NSMutableArray<NSURL*>* files = [NSMutableArray array];
    NSFileManager* fileManager = [NSFileManager defaultManager];
    NSArray<NSURLResourceKey>* keys = @[ NSURLIsDirectoryKey, NSURLIsRegularFileKey ];
    NSDirectoryEnumerator<NSURL*>* enumerator =
        [fileManager enumeratorAtURL:url
          includingPropertiesForKeys:keys
                             options:NSDirectoryEnumerationSkipsHiddenFiles | NSDirectoryEnumerationSkipsPackageDescendants
                        errorHandler:^BOOL(NSURL* _Nonnull errorURL, NSError* _Nonnull error) {
                            NSLog(@"[WaveWindowController] skip %@ due to error: %@", errorURL, error);
                            return YES;
                        }];
    for (NSURL* itemURL in enumerator) {
        NSNumber* isFile = nil;
        if ([itemURL getResourceValue:&isFile forKey:NSURLIsRegularFileKey error:nil] && [isFile boolValue]) {
            [files addObject:itemURL];
        }
    }
    return files;
}

#pragma mark - Browser delegate

- (void)closeFilter
{
    [_horizontalSplitView removeArrangedSubview:_searchField];
}

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

#pragma mark - Audio delegate

- (void)startVisuals
{
    // Start beats.
    [self beatEffectStart];

    // Start the scope renderer.
    [_renderer play:_audioController visual:_visualSample scope:_scopeView];
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
    [self loadDocumentFromURL:[WaveWindowController encodeQueryItemsWithUrl:meta.location frame:0LL playing:YES] meta:meta];
}

- (void)playPrevious:(id)sender
{
    //    // Do we have something in our playlist?
    //    MediaMetaData* meta = [_playlist previousItem];
    //    if (meta == nil) {
    //        // Then maybe we can just get the next song from the songs browser
    //        list.
    //        //- (IBAction)playNext:(id)sender
    //        // Find the topmost selected song and use that one to play next.
    //        [self stop];
    //        return;
    //    }
    //
    //    [self loadDocumentFromURL:[WaveWindowController
    //    encodeQueryItemsWithUrl:meta.location frame:0LL playing:YES] meta:meta];
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

- (void)effectsToggle:(id)sender
{
    // Toggle FX window visibility. Effect on/off depends on selection (None keeps FX off but window open).
    if (_controlPanelController.effectsButton.state == NSControlStateValueOn) {
        [_fxViewController updateEffects:_audioController.availableEffects];
        NSInteger currentIdx = _audioController.currentEffectIndex;
        if (currentIdx < 0) {
            NSInteger stored = [self storedEffectSelectionIndex];
            if (stored >= 0) {
                if ([_audioController selectEffectAtIndex:stored]) {
                    currentIdx = stored;
                }
            }
        }
        // Ensure effect is audibly enabled when turning FX on.
        [_audioController applyEffectEnabled:(currentIdx >= 0)];
        [[NSUserDefaults standardUserDefaults] setBool:(currentIdx >= 0) forKey:kFXLastEffectEnabledKey];
        [_fxViewController selectEffectIndex:currentIdx];
        [_fxViewController applyCurrentSelection];
        [_fxViewController showWithParent:self.window];
        [_controlPanelController setEffectsEnabled:(currentIdx >= 0)];
    } else {
        // Bypass current effect but keep selection state and sliders.
        [_audioController applyEffectEnabled:NO];
        [[NSUserDefaults standardUserDefaults] setBool:NO forKey:kFXLastEffectEnabledKey];
        [_controlPanelController setEffectsEnabled:NO];
    }
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

    unsigned long long frame = iter.currentEvent.frame;
    while ((iter.currentEvent.style & BeatEventStyleBar) != BeatEventStyleBar) {
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

    unsigned long long frame = iter.currentEvent.frame;
    while ((iter.currentEvent.style & BeatEventStyleBar) != BeatEventStyleBar) {
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
    unsigned long long frame = iter.currentEvent.frame;
    while (barCount-- > 0) {
        while ((iter.currentEvent.style & BeatEventStyleBar) != BeatEventStyleBar) {
            frame = [self.beatSample seekToNextBeat:&iter];
        };
        if (barCount > 1 && (iter.currentEvent.style & BeatEventStyleBar) == BeatEventStyleBar) {
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
    unsigned long long frame = iter.currentEvent.frame;

    while (barCount-- > 0) {
        while ((iter.currentEvent.style & BeatEventStyleBar) != BeatEventStyleBar) {
            frame = [self.beatSample seekToPreviousBeat:&iter];
            NSLog(@"repeating beat at %lld", frame);
        };
        if (barCount > 1 && (iter.currentEvent.style & BeatEventStyleBar) == BeatEventStyleBar) {
            frame = [self.beatSample seekToPreviousBeat:&iter];
        }
    };
    NSLog(@"repeating 4 bars at %lld", frame);
    _audioController.currentFrame = frame;
    [self updateRemotePosition];
}

#pragma mark - Full Screen Support: Persisting and Restoring Window's Non-FullScreen Frame

+ (NSArray*)restorableStateKeyPaths
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

#pragma mark - Tracklist Contoller delegate

- (NSURL*)linkedURL
{
    return _meta.location;
}

- (double)secondsFromFrame:(unsigned long long)frame
{
    return [_audioController.sample timeForFrame:frame];
}

- (NSString*)stringFromFrame:(unsigned long long)frame
{
    return [_audioController.sample beautifulTimeWithFrame:frame];
}

- (NSString*)standardStringFromFrame:(unsigned long long)frame
{
    return [_audioController.sample cueTimeWithFrame:frame];
}

- (void)playAtFrame:(unsigned long long)frame
{
    [self seekToFrame:frame];
}

- (void)updatedTracks
{
    [_scrollingWaveViewController reloadTracklist];
    [_totalWaveViewController reloadTracklist];
}

- (TimedMediaMetaData*)currentTrack
{
    return [_tracklist currentTrack];
}

- (void)moveTrackAtFrame:(unsigned long long)oldFrame toFrame:(unsigned long long)newFrame
{
    [_tracklist moveTrackAtFrame:oldFrame frame:newFrame];
    [self updatedTracks];
}

- (BOOL)validateToolbarItem:(nonnull NSToolbarItem*)item
{
    return YES;
}

// FIXME: WHY?
- (void)encodeWithCoder:(nonnull NSCoder*)coder
{}


#pragma mark - Notifications

- (void)activitiesUpdated:(NSNotification*)note
{
    // Should we care?
    if (_importToken == nil) {
        return;
    }

    // Did our token expire?
    if (![[ActivityManager shared] isActive:_importToken]) {
        _importToken = nil;
        _importLabel.hidden = YES;
        _importProgress.hidden = YES;
        return;
    }

    ActivityEntry* entry = [[ActivityManager shared] activityWithToken:_importToken];
    _importProgress.doubleValue = entry.progress;
    [_importProgress setNeedsDisplay:YES];
}

@end
