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

#import <IOKit/pwr_mgt/IOPM.h>

#import "WaveWindowController.h"
#import "AudioController.h"
#import "VisualSample.h"
#import "BeatTrackedSample.h"
#import "LazySample.h"
#import "BrowserController.h"
#import "PlaylistController.h"
#import "LoadState.h"
#import "MediaMetaData.h"
#import "ScopeRenderer.h"
#import "WaveRenderer.h"
#import "TotalWaveView.h"
#import "WaveView.h"
#import "MetalWaveView.h"
#import "UIView+Visibility.h"
#import "InfoPanel.h"
#import "ScrollingTextView.h"
#import "TableHeaderCell.h"
#import "ControlPanelController.h"
#import "IdentifyController.h"
#import "Defaults.h"
#import "BeatLayerDelegate.h"
#import "WaveLayerDelegate.h"
#import "ProfilingPointsOfInterest.h"
#import "NSAlert+BetterError.h"
#import "SPMediaKeyTap.h"

#import "MusicAuthenticationController.h"

static const float kShowHidePanelAnimationDuration = 0.3f;
static const float kPixelPerSecond = 120.0f;
static const NSTimeInterval kBeatEffectRampUp = 0.05f;
static const NSTimeInterval kBeatEffectRampDown = 0.5f;

const CGFloat kDefaultWidth = 1180.0f;
const CGFloat kDefaultHeight = 1050.0f;

const CGFloat kMinWidth = 465.0f;
const CGFloat kMinHeight = 100.0f;      // Constraints on the subviews make this a minimum
                                        // that is never reached.
const CGFloat kMinScopeHeight = 64.0f;  // Smaller would still me ok...
const CGFloat kMinTableHeight = 0.0f;   // Just forget about it.

static const int kSplitPositionCount = 5;

os_log_t pointsOfInterest;

@interface WaveWindowController ()
{
    CGFloat splitPosition[kSplitPositionCount];
    CGFloat splitPositionMemory[kSplitPositionCount];
    CGFloat splitSelectorPositionMemory[kSplitPositionCount];
    
    BeatEventIterator _beatEffectIteratorContext;
    unsigned long long _beatEffectAtFrame;
    unsigned long long _beatEffectRampUpFrames;
    
    BOOL _mediakeyJustJumped;
}

@property (assign, nonatomic) CGFloat windowBarHeight;
@property (assign, nonatomic) CGRect smallBelowVisualsFrame;
@property (assign, nonatomic) CGFloat smallSplitter1Position;
@property (assign, nonatomic) CGFloat smallSplitter2Position;

@property (strong, nonatomic) ScopeRenderer* renderer;
@property (strong, nonatomic) WaveRenderer* waveRenderer;
@property (assign, nonatomic) CGRect preFullscreenFrame;
@property (strong, nonatomic) LazySample* lazySample;
@property (assign, nonatomic) BOOL inTransition;
@property (strong, nonatomic) PlaylistController* playlist;
@property (strong, nonatomic) MediaMetaData* meta;

@property (strong, nonatomic) ControlPanelController* controlPanelController;
@property (strong, nonatomic) MusicAuthenticationController* authenticator;

@property (strong, nonatomic) NSPopover* popOver;
//@property (strong, nonatomic) NSPopover* infoPopOver;

@property (strong, nonatomic) NSWindowController* infoWindowController;

@property (strong, nonatomic) BeatLayerDelegate* beatLayerDelegate;
@property (strong, nonatomic) WaveLayerDelegate* waveLayerDelegate;
@property (strong, nonatomic) WaveLayerDelegate* totalWaveLayerDelegate;

@property (strong, nonatomic) SPMediaKeyTap* keyTap;

// _displayLink;

//@property (strong, nonatomic) CADisplayLink* displayLink;

//@property (strong, nonatomic) dispatch_queue_t waveQueue;
//@property (strong, nonatomic) dispatch_queue_t scopeQueue;

- (void)stop;

@end


@implementation WaveWindowController
{
    CVDisplayLinkRef _displayLink;
    IOPMAssertionID _noSleepAssertionID;
}

// Vertical sync callback.
//
// Note: So far this doesnt work properly on ProVision displays -
// as a result we see stuttering CoreAnimation playback. This likely
// is because the signalled callback frequency remains at a fixed 60hz.
static CVReturn renderCallback(CVDisplayLinkRef displayLink,
                               const CVTimeStamp* inNow,
                               const CVTimeStamp* inOutputTime,
                               CVOptionFlags flagsIn,
                               CVOptionFlags* flagsOut,
                               void* displayLinkContext)
{
    static unsigned int counter = 0;

    os_signpost_interval_begin(pointsOfInterest, POICADisplayLink, "CADisplayLink");

    assert(displayLinkContext);
    WaveWindowController* controller = (__bridge WaveWindowController*)displayLinkContext;

    ++counter;
    
 //   CVTimeStamp delta = *inOutputTime - *inNow;
//
    AVAudioFramePosition frame = controller.audioController.currentFrame;
    
    [controller updateScopeFrame:frame];

    dispatch_async(dispatch_get_main_queue(), ^{
        os_signpost_interval_begin(pointsOfInterest, POISetCurrentFrame, "SetCurrentFrame");
        controller.currentFrame = frame;
        os_signpost_interval_end(pointsOfInterest, POISetCurrentFrame, "SetCurrentFrame");
    });
    os_signpost_interval_end(pointsOfInterest, POICADisplayLink, "CADisplayLink");

    return kCVReturnSuccess;
}

//- (void)renderCallback:(CADisplayLink *)sender
//{
//    static unsigned int counter = 0;
//
//    os_signpost_interval_begin(pointsOfInterest, POICADisplayLink, "CADisplayLink");
//
//    //assert(displayLinkContext);
//    //WaveWindowController* controller = (__bridge WaveWindowController*)displayLinkContext;
//
//    ++counter;
//    
////    CVTimeStamp delta = *inOutputTime - *inNow;
////
//    AVAudioFramePosition frame = self.audioController.currentFrame;
//    
//    //[controller updateWaveFrame:frame];
//    [self updateScopeFrame:frame];
//
//    //dispatch_async(dispatch_get_main_queue(), ^{
//        os_signpost_interval_begin(pointsOfInterest, POISetCurrentFrame, "SetCurrentFrame");
//        self.currentFrame = frame;
//        os_signpost_interval_end(pointsOfInterest, POISetCurrentFrame, "SetCurrentFrame");
//    //});
//    os_signpost_interval_end(pointsOfInterest, POICADisplayLink, "CADisplayLink");
//
//    //return kCVReturnSuccess;
//}

- (void)playNext:(id)sender
{
    // Do we have something in our playlist?
    MediaMetaData* meta = [_playlist nextItem];
    if (meta == nil) {
        // Then maybe we can just get the next song from the songs browser list.
        //- (IBAction)playNext:(id)sender
        // Find the topmost selected song and use that one to play next.
        [self stop];
        return;
    }

    [self loadDocumentFromURL:[WaveWindowController encodeQueryItemsWithUrl:meta.location frame:0LL playing:YES] meta:meta];
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

- (void)mediaKeyTap:(SPMediaKeyTap*)keyTap receivedMediaKeyEvent:(NSEvent*)event
{
    assert([event type] == NSEventTypeSystemDefined && [event subtype] == SPSystemDefinedEventMediaKeys);

    int keyCode = (([event data1] & 0xFFFF0000) >> 16);
    int keyFlags = ([event data1] & 0x0000FFFF);
    int keyState = (((keyFlags & 0xFF00) >> 8)) == 0xA;
    int keyRepeat = (keyFlags & 0x1);

    if (keyCode == NX_KEYTYPE_PLAY && keyState == 0) {
        [self playPause:self];
    }

    if ((keyCode == NX_KEYTYPE_FAST || keyCode == NX_KEYTYPE_NEXT) && !_mediakeyJustJumped) {
        if (keyState == 0 && keyRepeat == 0) {
            [self playNext:self];
        } else if (keyRepeat == 1) {
            _mediakeyJustJumped = YES;
            [self performSelector:@selector(resetMediaKeyJump)
                           withObject: NULL
                           afterDelay:0.25];
        }
    }

    if ((keyCode == NX_KEYTYPE_REWIND || keyCode == NX_KEYTYPE_PREVIOUS) && !_mediakeyJustJumped) {
        if (keyState == 0 && keyRepeat == 0) {
            [self playPrevious:self];
        } else if (keyRepeat == 1) {
            _mediakeyJustJumped = YES;
            [self performSelector:@selector(resetMediaKeyJump)
                       withObject: NULL
                       afterDelay:0.25];
        }
    }
}

- (void)resetMediaKeyJump
{
    _mediakeyJustJumped = NO;
}

- (id)init
{
    self = [super initWithWindowNibName:@""];
    if (self) {
        pointsOfInterest = os_log_create("com.toenshoff.playem", OS_LOG_CATEGORY_POINTS_OF_INTEREST);
        _noSleepAssertionID = 0;
    }
    return self;
}

- (void)updateScopeFrame:(AVAudioFramePosition)frame
{
    _renderer.currentFrame = frame;
    [_scopeView draw];
}

- (void)dealloc
{
    if (_displayLink) {
        CVDisplayLinkRelease(_displayLink);
    }
}

- (void)setLazySample:(LazySample*)sample
{
    if (_lazySample == sample) {
        return;
    }
    _lazySample = sample;
    NSLog(@"sample %@ assigned", sample.description);
}

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
    _beatEffectRampUpFrames = 0;
    _beatEffectAtFrame = [_beatSample frameForFirstBar:&_beatEffectIteratorContext];
}

- (BOOL)beatEffectNext
{
    _beatEffectAtFrame = [_beatSample frameForNextBar:&_beatEffectIteratorContext];
    return _beatEffectAtFrame > 0;
}

- (void)beatEffectRun
{
    [self setBPM:[_beatSample currentTempo:&_beatEffectIteratorContext]];

    [_browser beatEffect];
    
    // Thats a weird mid-point but hey...
    CGSize mid = CGSizeMake((_controlPanelController.beatIndicator.layer.bounds.size.width - 1) / 2,
                            _controlPanelController.beatIndicator.layer.bounds.size.height - 2);
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
        [context setDuration:kBeatEffectRampUp];
        self->_controlPanelController.beatIndicator.animator.alphaValue = 1.0;
        CATransform3D tr = CATransform3DIdentity;
        tr = CATransform3DTranslate(tr, mid.width, mid.height, 0);
        tr = CATransform3DScale(tr, 3.0, 3.0, 1);
        tr = CATransform3DTranslate(tr, -mid.width, -mid.height, 0);
        self->_controlPanelController.beatIndicator.animator.layer.transform = tr;
    } completionHandler:^{
        [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
            [context setDuration:kBeatEffectRampDown];
            [context setTimingFunction:[CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut]];
            self->_controlPanelController.beatIndicator.animator.alphaValue = 0.0;
            CATransform3D tr = CATransform3DIdentity;
            tr = CATransform3DTranslate(tr, mid.width, mid.height, 0);
            tr = CATransform3DScale(tr, 1.0, 1.0, 1);
            tr = CATransform3DTranslate(tr, -mid.width, -mid.height, 0);
            self->_controlPanelController.beatIndicator.animator.layer.transform = tr;
        }];
    }];
}

#pragma mark Toolbar delegate

static const NSString* kPlaylistToolbarIdentifier = @"Playlist";
static const NSString* kIdentifyToolbarIdentifier = @"Identify";
//static const NSString* kIdentifyToolbarIdentifier = @"Info";

- (NSArray*)toolbarDefaultItemIdentifiers:(NSToolbar*)toolbar
{
    return @[ NSToolbarFlexibleSpaceItemIdentifier, kIdentifyToolbarIdentifier, NSToolbarSpaceItemIdentifier, kPlaylistToolbarIdentifier ];
}

- (NSArray*)toolbarAllowedItemIdentifiers:(NSToolbar*)toolbar
{
    return @[ NSToolbarFlexibleSpaceItemIdentifier, kIdentifyToolbarIdentifier, NSToolbarSpaceItemIdentifier, kPlaylistToolbarIdentifier ];
}

-(BOOL)validateToolbarItem:(NSToolbarItem*)toolbarItem
{
    BOOL enable = YES;
    if ([[toolbarItem itemIdentifier] isEqual:kIdentifyToolbarIdentifier]) {
        enable = (_lazySample != nil) & _audioController.playing;
    }
    return enable;
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

    self.window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, kDefaultWidth, kDefaultHeight)
                                              styleMask:style
                                                backing:NSBackingStoreBuffered defer:YES];

    self.window.minSize = NSMakeSize(kMinWidth, kMinHeight);
    self.window.titlebarSeparatorStyle = NSTitlebarSeparatorStyleLine;
    self.window.titlebarAppearsTransparent = YES;
    self.window.titleVisibility = NO;
    self.window.movableByWindowBackground = YES;
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
    
    self.keyTap = [[SPMediaKeyTap alloc] initWithDelegate:self];
    if([SPMediaKeyTap usesGlobalMediaKeyTap]) {
        [_keyTap startWatchingMediaKeys];
        NSLog(@"Watching for mediakeys");
    } else {
        NSLog(@"Media key monitoring disabled");
    }

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

    _controlPanelController = [ControlPanelController new];
    _controlPanelController.layoutAttribute = NSLayoutAttributeLeft;
    [self.window addTitlebarAccessoryViewController:_controlPanelController];

    _splitViewController = [NSSplitViewController new];

    [self loadViews];

    _beatLayerDelegate.waveView = _waveView;
    self.totalWaveLayerDelegate.color = _waveView.color;
    self.waveLayerDelegate.color = _waveView.color;

    //    self.authenticator = [MusicAuthenticationController new];
//    [self.authenticator requestAppleMusicDeveloperTokenWithCompletion:^(NSString* token){
//        NSLog(@"token: %@", token);
//    }];
}

- (void)loadViews
{
    const CGFloat totalHeight = self.window.contentView.bounds.size.height;
    
    const CGFloat totalWaveViewHeight = 46.0;
    const CGFloat scrollingWaveViewHeight = 158.0;

    const CGFloat playlistFxViewWidth = 280.0;
    const CGFloat statusLineHeight = 14.0;
    const CGFloat songsTableViewHeight = floor(totalHeight / 4.0);
    const CGFloat selectorTableViewWidth = floor(self.window.contentView.bounds.size.width / 4);
    const CGFloat selectorTableViewHeight = floor(totalHeight / 5.0);
   
    const CGFloat selectorTableViewHalfWidth = floor(selectorTableViewWidth / 2.0);
    
    const CGFloat selectorColumnInset = 17.0;
    
    const CGFloat trackColumnWidth = 54.0;
    const CGFloat titleColumnWidth = 280.0f;
    const CGFloat timeColumnWidth = 80.0f;
    const CGFloat artistColumnWidth = 200.0f;
    const CGFloat albumColumnWidth = 200.0f;
    const CGFloat genreColumnWidth = 130.0f;
    const CGFloat addedColumnWidth = 80.0f;
    const CGFloat tempoColumnWidth = 80.0f;
    const CGFloat keyColumnWidth = 60.0f;

    const CGFloat progressIndicatorWidth = 32.0;
    const CGFloat progressIndicatorHeight = 32.0;

    CGFloat scopeViewHeight = self.window.contentView.bounds.size.height - (songsTableViewHeight + selectorTableViewHeight + totalWaveViewHeight + scrollingWaveViewHeight);
    if (scopeViewHeight <= kMinScopeHeight) {
        scopeViewHeight = kMinScopeHeight;
    }
    const NSAutoresizingMaskOptions kViewFullySizeable = NSViewHeightSizable | NSViewWidthSizable;
    
    NSMenu* menu = [NSMenu new];
    
    NSMenuItem* item = [[NSMenuItem alloc] initWithTitle:@"Play Next" action:@selector(playNext:) keyEquivalent:@"n"];
    [item setKeyEquivalentModifierMask:NSEventModifierFlagCommand];
    [menu addItem:item];
    item = [[NSMenuItem alloc] initWithTitle:@"Play Later" action:@selector(playLater:) keyEquivalent:@"l"];
    [item setKeyEquivalentModifierMask:NSEventModifierFlagCommand];
    [menu addItem:item];
    [menu addItem:[NSMenuItem separatorItem]];
    [menu addItemWithTitle:@"Show Info" action:@selector(showInfoForSelectedSongs:) keyEquivalent:@""];
    [menu addItem:[NSMenuItem separatorItem]];
    [menu addItemWithTitle:@"Show in Finder" action:@selector(showInFinder:) keyEquivalent:@""];
    
    // Status Line.
    _songsCount = [[NSTextField alloc] initWithFrame:NSMakeRect(self.window.contentView.bounds.origin.x,
                                                                self.window.contentView.bounds.origin.y,
                                                                self.window.contentView.bounds.size.width,
                                                                statusLineHeight)];
    _songsCount.font = [NSFont systemFontOfSize:11.0];
    _songsCount.textColor = [NSColor tertiaryLabelColor];
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
    
    TiledScrollView* tiledSV = [[TiledScrollView alloc] initWithFrame:NSMakeRect(_belowVisuals.bounds.origin.x,
                                                                                 _belowVisuals.bounds.origin.y + totalWaveViewHeight,
                                                                                 _belowVisuals.bounds.size.width,
                                                                                 scrollingWaveViewHeight)];
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

    NSTableColumn* col = [[NSTableColumn alloc] init];
    col.title = @"";
    col.identifier = @"CoverColumn";
    col.width = 26.0;
    [_playlistTable addTableColumn:col];

    col = [[NSTableColumn alloc] init];
    col.title = @"";
    col.identifier = @"TitleColumn";
    col.width = _effectBelowPlaylist.bounds.size.width - 26.0;
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
    _genreTable.autosaveTableColumns = YES;
    _genreTable.backgroundColor = [NSColor clearColor];
    _genreTable.style = NSTableViewStylePlain;
    
    
    col = [[NSTableColumn alloc] init];
    col.title = @"Genre";
    col.identifier = @"Genre";
    col.width = selectorTableViewWidth - selectorColumnInset;
    [_genreTable addTableColumn:col];
    sv.documentView = _genreTable;
    //[self.window.contentView addSubview:sv];
    [_splitSelectors addArrangedSubview:sv];
    
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
    _artistsTable.autosaveTableColumns = YES;
    _artistsTable.backgroundColor = [NSColor clearColor];
    _artistsTable.style = NSTableViewStylePlain;

    col = [[NSTableColumn alloc] init];
    col.title = @"Artist";
    col.width = selectorTableViewWidth - selectorColumnInset;
    [_artistsTable addTableColumn:col];
    sv.documentView = _artistsTable;
    //[self.window.contentView addSubview:sv];
    [_splitSelectors addArrangedSubview:sv];
    
    sv = [[NSScrollView alloc] initWithFrame:NSMakeRect(0.0,
                                                        0.0,
                                                        selectorTableViewWidth,
                                                        selectorTableViewHeight)];
    sv.hasVerticalScroller = YES;
    sv.autoresizingMask = kViewFullySizeable;
    sv.drawsBackground = NO;
    _albumsTable = [[NSTableView alloc] initWithFrame:sv.bounds];
    _albumsTable.tag = VIEWTAG_ALBUMS;
    _albumsTable.autosaveTableColumns = YES;
    _albumsTable.backgroundColor = [NSColor clearColor];
    _albumsTable.style = NSTableViewStylePlain;
    col = [[NSTableColumn alloc] init];
    col.title = @"Album";
    col.width = selectorTableViewWidth - selectorColumnInset;
    [_albumsTable addTableColumn:col];
    sv.documentView = _albumsTable;
    //[self.window.contentView addSubview:sv];
    [_splitSelectors addArrangedSubview:sv];
    
    sv = [[NSScrollView alloc] initWithFrame:NSMakeRect(0.0,
                                                        0.0,
                                                        selectorTableViewHalfWidth,
                                                        selectorTableViewHeight)];
    sv.hasVerticalScroller = YES;
    sv.autoresizingMask = kViewFullySizeable;
    sv.drawsBackground = NO;
    _temposTable = [[NSTableView alloc] initWithFrame:sv.bounds];
    _temposTable.tag = VIEWTAG_TEMPO;
    _temposTable.backgroundColor = [NSColor clearColor];
    _temposTable.style = NSTableViewStylePlain;
    _temposTable.autosaveTableColumns = YES;

    col = [[NSTableColumn alloc] init];
    col.title = @"BPM";
    col.width = selectorTableViewHalfWidth - selectorColumnInset;
    [_temposTable addTableColumn:col];
    sv.documentView = _temposTable;
    //[self.window.contentView addSubview:sv];
    [_splitSelectors addArrangedSubview:sv];
    
    sv = [[NSScrollView alloc] initWithFrame:NSMakeRect(0.0,
                                                        0.0,
                                                        selectorTableViewHalfWidth,
                                                        selectorTableViewHeight)];
    sv.hasVerticalScroller = YES;
    sv.autoresizingMask = kViewFullySizeable;
    sv.drawsBackground = NO;
    _keysTable = [[NSTableView alloc] initWithFrame:NSZeroRect];
    _keysTable.tag = VIEWTAG_KEY;
    _keysTable.backgroundColor = [NSColor clearColor];
    _keysTable.style = NSTableViewStylePlain;
    _keysTable.autosaveTableColumns = YES;
    col = [[NSTableColumn alloc] init];
    col.title = @"Key";
    col.width = selectorTableViewHalfWidth - selectorColumnInset;
    [_keysTable addTableColumn:col];
    sv.documentView = _keysTable;
    [_splitSelectors addArrangedSubview:sv];
    
    //[self.window.contentView addSubview:splitSelectors];
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
    _songsTable.backgroundColor = [NSColor clearColor];
    _songsTable.tag = VIEWTAG_FILTERED;
    _songsTable.menu = menu;
    _songsTable.autosaveTableColumns = YES;
    _songsTable.allowsMultipleSelection = YES;
    _songsTable.style = NSTableViewStylePlain;
    [_songsTable selectionHighlightStyle];

    col = [[NSTableColumn alloc] initWithIdentifier:@"TrackCell"];
    col.title = @"Track";
    col.width = trackColumnWidth - selectorColumnInset;
    col.sortDescriptorPrototype = [[NSSortDescriptor alloc] initWithKey:@"track" ascending:YES selector:@selector(compare:)];
    [_songsTable addTableColumn:col];
    
    col = [[NSTableColumn alloc] initWithIdentifier:@"TitleCell"];
    col.title = @"Title";
    col.width = titleColumnWidth - selectorColumnInset;
    col.sortDescriptorPrototype = [[NSSortDescriptor alloc] initWithKey:@"title" ascending:YES selector:@selector(compare:)];
    [_songsTable addTableColumn:col];
    
    col = [[NSTableColumn alloc] initWithIdentifier:@"TimeCell"];
    col.title = @"Time";
    col.width = timeColumnWidth - selectorColumnInset;
    col.sortDescriptorPrototype = [[NSSortDescriptor alloc] initWithKey:@"duration" ascending:YES selector:@selector(compare:)];
    [_songsTable addTableColumn:col];
    
    col = [[NSTableColumn alloc] initWithIdentifier:@"ArtistCell"];
    col.title = @"Artist";
    col.width = artistColumnWidth - selectorColumnInset;
    col.sortDescriptorPrototype = [[NSSortDescriptor alloc] initWithKey:@"artist" ascending:YES selector:@selector(compare:)];
    [_songsTable addTableColumn:col];
    
    col = [[NSTableColumn alloc] initWithIdentifier:@"AlbumCell"];
    col.title = @"Album";
    col.width = albumColumnWidth - selectorColumnInset;
    col.sortDescriptorPrototype = [[NSSortDescriptor alloc] initWithKey:@"album" ascending:YES selector:@selector(compare:)];
    [_songsTable addTableColumn:col];
    
    col = [[NSTableColumn alloc] initWithIdentifier:@"GenreCell"];
    col.title = @"Genre";
    col.width = genreColumnWidth - selectorColumnInset;
    col.sortDescriptorPrototype = [[NSSortDescriptor alloc] initWithKey:@"genre" ascending:YES selector:@selector(compare:)];
    [_songsTable addTableColumn:col];
    
    col = [[NSTableColumn alloc] initWithIdentifier:@"AddedCell"];
    col.title = @"Added";
    col.width = addedColumnWidth - selectorColumnInset;
    col.sortDescriptorPrototype = [[NSSortDescriptor alloc] initWithKey:@"added" ascending:YES selector:@selector(compare:)];
    [_songsTable addTableColumn:col];

    col = [[NSTableColumn alloc] initWithIdentifier:@"TempoCell"];
    col.title = @"Tempo";
    col.width = tempoColumnWidth - selectorColumnInset;
    col.sortDescriptorPrototype = [[NSSortDescriptor alloc] initWithKey:@"tempo" ascending:YES selector:@selector(compare:)];
    [_songsTable addTableColumn:col];

    col = [[NSTableColumn alloc] initWithIdentifier:@"KeyCell"];
    col.title = @"Key";
    col.width = keyColumnWidth - selectorColumnInset;
    col.sortDescriptorPrototype = [[NSSortDescriptor alloc] initWithKey:@"key" ascending:YES selector:@selector(compare:)];
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
    _songsTable.autosaveName = @"SongsTable";
    
    _browser = [[BrowserController alloc] initWithGenresTable:_genreTable
                                                 artistsTable:_artistsTable
                                                  albumsTable:_albumsTable
                                                  temposTable:_temposTable
                                                   songsTable:_songsTable
                                                    keysTable:_keysTable
                                                     delegate:self];
    
    // Replace the header cell in all of the main tables on this view.
    NSArray<NSTableView*>* fixupTables = @[ _songsTable,
                                            _genreTable,
                                            _artistsTable,
                                            _albumsTable,
                                            _temposTable,
                                            _keysTable ];
    
    for (NSTableView *table in fixupTables) {
        //table.style = NSTableViewStyleSourceList;
        //table.style = NSTableViewStylePlain;
        //table.headerView = [[NSTableHeaderView alloc] init];
        for (NSTableColumn *column in [table tableColumns]) {
            TableHeaderCell* cell = [[TableHeaderCell alloc] initTextCell:[[column headerCell] stringValue]];
            [column setHeaderCell:cell];
        }
        table.delegate = _browser;
        table.dataSource = _browser;
        table.headerView.wantsLayer = YES;
    }
    
    _lazySample = nil;
    
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
    
    _playlist = [[PlaylistController alloc] initWithPlaylistTable:_playlistTable delegate:self];
    
    [self.renderer loadMetalWithView:self.scopeView];

    [self setupDisplayLink];
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(ScrollViewStartsLiveScrolling:) name:@"NSScrollViewWillStartLiveScrollNotification" object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(ScrollViewEndsLiveScrolling:) name:@"NSScrollViewDidEndLiveScrollNotification" object:nil];
    
    NSNumber* fullscreenValue = [userDefaults objectForKey:@"fullscreen"];
    if ([fullscreenValue boolValue]) {
        [self.window toggleFullScreen:self];
    }
}

- (void)setupDisplayLink
{
    //    dispatch_queue_attr_t attr = dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL, QOS_CLASS_USER_INTERACTIVE, 0);
    //
    //    _scopeQueue = dispatch_queue_create("PlayEm.ScopeQueue", attr);
    //    _waveQueue = dispatch_queue_create("PlayEm.WaveQueue", attr);
    
    //CGDirectDisplayID   displayID = CGMainDisplayID();
    NSLog(@"setting up display link..");
    CVReturn            error = kCVReturnSuccess;
    error = CVDisplayLinkCreateWithActiveCGDisplays(&_displayLink);
    if (error) {
        NSLog(@"DisplayLink created with error:%d", error);
        _displayLink = NULL;
    } else {
        CVDisplayLinkSetOutputCallback(_displayLink,
                                       renderCallback,
                                       (__bridge void *)self);
    }
    
//    NSScreen* screen = [NSScreen mainScreen];
//    
//    self.displayLink = [screen displayLinkWithTarget:self selector:@selector(renderCallback:)];
//    [self.displayLink addToRunLoop:[NSRunLoop currentRunLoop]
//                           forMode:NSRunLoopCommonModes];
}

- (id)supplementalTargetForAction:(SEL)action sender:(id)sender
{
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

    NSNumber* currentFrameValue = [NSNumber numberWithUnsignedLongLong:currentFrame];
    
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
    [_lazySample abortWithCallback:^{
        [self stop];
    }];
    //[BeatTrackedSample abort];
    // Finish playback, if anything was ongoing.
}

- (void)windowDidEndLiveResize:(NSNotification *)notification
{
    // The scope view takes are of itself by reacting to `viewDidEndLiveResize`.
//    [_waveView ];
    
    [_totalVisual setPixelPerSecond:_totalView.bounds.size.width / _lazySample.duration];
    [_totalView resize];
    [_totalView refresh];
}

- (void)windowDidResize:(NSNotification *)notification
{
    NSLog(@"windowDidResize with `ContentView` to height %f", self.window.contentView.bounds.size.height);
    NSLog(@"windowDidResize with `BelowVisuals` to height %f", _belowVisuals.bounds.size.height);

    NSSize newSize = NSMakeSize(_belowVisuals.bounds.size.width,
                                _belowVisuals.bounds.size.height - (_totalView.bounds.size.height + _waveView.bounds.size.height));
    NSLog(@"windowDidResize with `ScopeView` to height %f", newSize.height);
    [_renderer mtkView:_scopeView drawableSizeWillChange:newSize];
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

    if (toFullscreen) {
        memcpy(splitPositionMemory, splitPosition, sizeof(CGFloat) * kSplitPositionCount);
        // Restore the old positions.
        [_splitSelectors setPosition:splitSelectorPositionMemory[0] ofDividerAtIndex:0];
        [_splitSelectors setPosition:splitSelectorPositionMemory[1] ofDividerAtIndex:1];
        [_splitSelectors setPosition:splitSelectorPositionMemory[2] ofDividerAtIndex:2];
        [_splitSelectors setPosition:splitSelectorPositionMemory[3] ofDividerAtIndex:3];
        [_splitSelectors setPosition:splitSelectorPositionMemory[4] ofDividerAtIndex:4];
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
//
//- (ScopeView*)scopeViewWithFrame:(NSRect)frame onView:(NSView*)parent
//{
//    assert(frame.size.width * frame.size.height);
//    ScopeView* sv = [[ScopeView alloc] initWithFrame:frame
//                                              device:MTLCreateSystemDefaultDevice()];
//    assert(sv);
//    sv.paused = YES;
//    sv.layer.opaque = YES;
//
//    assert(parent);
//    [parent addSubview:sv];
//    
//    [parent addConstraint:[NSLayoutConstraint constraintWithItem:sv
//                                                       attribute:NSLayoutAttributeHeight
//                                                       relatedBy:NSLayoutRelationGreaterThanOrEqual
//                                                          toItem:nil
//                                                       attribute:NSLayoutAttributeNotAnAttribute
//                                                      multiplier:1.0
//                                                        constant:kMinScopeHeight]];
//
//    [_scopeView removeFromSuperview];
//    _scopeView = sv;
//    
//    assert(_effectBelowPlaylist);
//    [parent addSubview:_effectBelowPlaylist positioned:NSWindowAbove relativeTo:nil];
//
//    _renderer = [[ScopeRenderer alloc] initWithMetalKitView:sv
//                                                      color:[[Defaults sharedDefaults] lightBeamColor]
//                                                   fftColor:[[Defaults sharedDefaults] fftColor]
//                                                 background:[[Defaults sharedDefaults] backColor]
//                                                   delegate:self];
//    _renderer.level = self.controlPanelController.level;
//    sv.delegate = _renderer;
//
//    [_renderer mtkView:sv drawableSizeWillChange:sv.bounds.size];
//
//    if (_audioController && _visualSample) {
//        [_renderer play:_audioController visual:_visualSample scope:sv];
//    }
//
//    return sv;
//}

//// Yeah right - what a shitty name for a function that does so much more!
//- (void)putMetalWaveViewWithFrame:(NSRect)frame onView:(NSView*)parent
//{
//    assert(frame.size.width * frame.size.height);
//    MetalWaveView* mwv = [[MetalWaveView alloc] initWithFrame:frame
//                                              device:MTLCreateSystemDefaultDevice()];
//    assert(mwv);
//    //sv.colorPixelFormat = MTLPixelFormatBGRA10_XR_sRGB;
//    mwv.colorPixelFormat = MTLPixelFormatBGRA8Unorm;
//    mwv.depthStencilPixelFormat = MTLPixelFormatInvalid;
//    mwv.drawableSize = frame.size;
//
//    mwv.autoresizingMask = NSViewHeightSizable | NSViewWidthSizable | NSViewMaxYMargin;
//   
//    mwv.autoResizeDrawable = NO;
//
//    self.waveRenderer = [[WaveRenderer alloc] initWithView:mwv
//                                                      color:[[Defaults sharedDefaults] lightBeamColor]
//                                                 background:[[Defaults sharedDefaults] backColor]
//                                                   delegate:self];
//    _renderer.level = self.controlPanelController.level;
//    mwv.delegate = _waveRenderer;
//
//    assert(parent);
//    [parent addSubview:mwv];
//
////    [_metalWaveView removeFromSuperview];
////    _metalWaveView = mwv;
//}

- (void)setPlaybackActive:(BOOL)active
{
    _controlPanelController.playPause.state = active ? NSControlStateValueOn : NSControlStateValueOff;
}

- (void)showInfo:(BOOL)processCurrentSong
{
    if (_infoWindowController == nil) {
        InfoPanelController* info = [[InfoPanelController alloc] initWithDelegate:self];
        self.infoWindowController = [NSWindowController new];
        NSWindow* window = [NSWindow windowWithContentViewController:info];
        window.titleVisibility = NSWindowTitleHidden;
        window.movableByWindowBackground = YES;
        window.titlebarAppearsTransparent = YES;
        [window standardWindowButton:NSWindowZoomButton].hidden = YES;
        [window standardWindowButton:NSWindowCloseButton].hidden = YES;
        [window standardWindowButton:NSWindowMiniaturizeButton].hidden = YES;
        _infoWindowController.window = window;
    }

    ((InfoPanelController*)_infoWindowController.contentViewController).processCurrentSong = processCurrentSong;
    [[NSApplication sharedApplication] runModalForWindow:_infoWindowController.window];
}

- (void)showInfoForCurrentSong:(id)sender
{
    [self showInfo:YES];
}

- (void)showInfoForSelectedSongs:(id)sender
{
    [self showInfo:NO];
}

- (void)showPlaylist:(id)sender
{
    BOOL isShow = _effectBelowPlaylist.alphaValue == 0.0f;
    
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

- (void)showIdentifier:(id)sender
{
    if (_iffy == nil) {
        _iffy = [[IdentifyController alloc] initWithAudioController:_audioController];
    }
    [_iffy view];
    
    _popOver = [[NSPopover alloc] init];
    _popOver.contentViewController = _iffy;
    _popOver.contentSize = _iffy.view.bounds.size;
    _popOver.animates = YES;
    _popOver.behavior = NSPopoverBehaviorTransient;
    _popOver.delegate = _iffy;

    NSRect entryRect = NSMakeRect(self.window.contentView.frame.size.width - 90.0,
                                  self.window.contentView.frame.size.height - 3.0,
                                  2.0,
                                  2.0);
    
    [_popOver showRelativeToRect:entryRect
                          ofView:self.window.contentView
                   preferredEdge:NSMinYEdge];
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
    _controlPanelController.bpm.stringValue = [NSString stringWithFormat:@"%3.0f BPM", floorf(bpm)];
}

- (void)setCurrentFrame:(unsigned long long)frame
{
    if (_waveView.currentFrame == frame) {
        return;
    }
    os_signpost_interval_begin(pointsOfInterest, POIStringStuff, "StringStuff");
    _controlPanelController.duration.stringValue = [_lazySample beautifulTimeWithFrame:_lazySample.frames - frame];
    _controlPanelController.time.stringValue = [_lazySample beautifulTimeWithFrame:frame];
    os_signpost_interval_end(pointsOfInterest, POIStringStuff, "StringStuff");

    os_signpost_interval_begin(pointsOfInterest, POIWaveViewSetCurrentFrame, "WaveViewSetCurrentFrame");
    _waveView.currentFrame = frame;
    os_signpost_interval_end(pointsOfInterest, POIWaveViewSetCurrentFrame, "WaveViewSetCurrentFrame");

    os_signpost_interval_begin(pointsOfInterest, POITotalViewSetCurrentFrame, "TotalViewSetCurrentFrame");
    _totalView.currentFrame = frame;
    os_signpost_interval_end(pointsOfInterest, POITotalViewSetCurrentFrame, "TotalViewSetCurrentFrame");

    os_signpost_interval_begin(pointsOfInterest, POIBeatStuff, "BeatStuff");
    if (_beatSample.ready) {
        if (_beatEffectAtFrame > 0 && frame + _beatEffectRampUpFrames > _beatEffectAtFrame) {
            [self beatEffectRun];
            while (frame + _beatEffectRampUpFrames > _beatEffectAtFrame) {
                if (![self beatEffectNext]) {
                    NSLog(@"end of beats reached");
                    [self beatEffectStart];
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

#pragma mark Splitter delegate

//- (void)splitView:(NSSplitView *)splitView resizeSubviewsWithOldSize:(NSSize)oldSize
//{
//    if (splitView == _split) {
//        //renderer mtkView:_scopeView drawableSizeWillChange:_scopeView.bounds.size];
//        NSLog(@"old size %@", NSStringFromSize(oldSize));
//        NSLog(@"new size %@", NSStringFromSize(_scopeView.bounds.size));
//    }
//}

- (void)splitViewWillResizeSubviews:(NSNotification *)notification
{
    NSSplitView* sv = notification.object;
    NSNumber* indexNumber = notification.userInfo[@"NSSplitViewDividerIndex"];

    if (sv == _split) {
        if (indexNumber != nil) {
            switch(indexNumber.intValue) {
                case 0: {
                    //NSSize newSize = NSMakeSize(_split.bounds.size.width, _split.bounds.size.height - (_totalView.bounds.size.height + _waveView.bounds.size.height));
//                    NSSize newSize = NSMakeSize(_belowVisuals.bounds.size.width, _belowVisuals.bounds.size.height - (_totalView.bounds.size.height + _waveView.bounds.size.height));
//                    NSLog(@"splitViewWillResizeSubview 0 `ScopeView` to height %f", newSize.height);
//                    if (newSize.height > 0.0) {
//                        [_renderer mtkView:_scopeView drawableSizeWillChange:newSize];
//                    }
//                    NSSize newSize = NSMakeSize(_belowVisuals.bounds.size.width, _belowVisuals.bounds.size.height - (_totalView.bounds.size.height + _waveView.bounds.size.height));
//                    NSLog(@"windowDidResize with `ScopeView` to height %f", newSize.height);
//                    [_renderer mtkView:_scopeView drawableSizeWillChange:newSize];

                    break;
                }
                case 1:
                    NSLog(@"splitViewWillResizeSubview 1 to height %f", _splitSelectors.bounds.size.height);
                    break;
                case 2:
                    NSLog(@"splitViewWillResizeSubview 2 to height %f", _songsTable.enclosingScrollView.bounds.size.height);
                    break;
            }
        }
    }
}

/*
- (CGFloat)splitView:(NSSplitView *)splitView constrainMinCoordinate:(CGFloat)proposedMinimumPosition ofSubviewAt:(NSInteger)dividerIndex
{
    CGFloat ret = 0.0f;
    if (splitView == _split) {
        if (dividerIndex == 0) {
            //_totalView.translatesAutoresizingMaskIntoConstraints
            ret = _totalView.bounds.size.height + _waveView.bounds.size.height + kMinScopeViewHeigth;
        }
    }
    return ret;
}
 */

- (BOOL)splitView:(NSSplitView *)splitView canCollapseSubview:(NSView *)subview
{
    return YES;
}

- (void)splitViewDidResizeSubviews:(NSNotification *)notification
{
    /*
     A notification that is posted to the default notification center by NSSplitView when a split view has just resized its subviews either as a result of its own resizing or during the dragging of one of its dividers by the user. Starting in Mac OS 10.5, if the notification is being sent because the user is dragging a divider, the notification's user info dictionary contains an entry whose key is @"NSSplitViewDividerIndex" and whose value is an NSInteger-wrapping NSNumber that is the index of the divider being dragged. Starting in Mac OS 12.0, the notification will contain the user info dictionary during resize and layout events as well.
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
        }
    } else if (sv == _split) {
        switch(indexNumber.intValue) {
            case 0: {
                NSSize newSize = NSMakeSize(_belowVisuals.bounds.size.width, _belowVisuals.bounds.size.height - (_totalView.bounds.size.height + _waveView.bounds.size.height));
                [_renderer mtkView:_scopeView drawableSizeWillChange:newSize];
                break;
            }
        }
        splitPosition[0] = _belowVisuals.bounds.size.height;
        splitPosition[1] = _belowVisuals.bounds.size.height + _splitSelectors.bounds.size.height;
    }
}


#pragma mark Document lifecycle

- (IBAction)openDocument:(id)sender
{
    NSOpenPanel* openDlg = [NSOpenPanel openPanel];
    [openDlg setCanChooseFiles:YES];
    [openDlg setCanChooseDirectories:YES];

    if ([openDlg runModal] == NSModalResponseOK) {
        for(NSURL* url in [openDlg URLs]) {
            [self loadDocumentFromURL:[WaveWindowController encodeQueryItemsWithUrl:url frame:0LL playing:YES] meta:nil];
        }
    } else {
        return;
    }
}

- (BOOL)loadDocumentFromURL:(NSURL*)url meta:(MediaMetaData*)meta
{
    NSError* error = nil;
    if (_audioController == nil) {
        _audioController = [AudioController new];
        _audioController.delegate = self;
    }
    
    if (url == nil) {
        return NO;
    }
    
    BOOL playing = NO;
    unsigned long long frame = 0LL;

    NSURLComponents* components = [NSURLComponents componentsWithURL:url
                                             resolvingAgainstBaseURL:YES];

    NSPredicate* predicate = [NSPredicate predicateWithFormat:@"name=%@", @"CurrentFrame"];
    NSURLQueryItem* item = [[components.queryItems filteredArrayUsingPredicate:predicate] firstObject];
    frame = [[item value] longLongValue];

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
    [self setMeta:meta];
    if (_lazySample != nil) {
        [_lazySample abortWithCallback:^{
            [self loadLazySample:lazySample nextFrame:frame playing:playing];
        }];
    } else {
        [self loadLazySample:lazySample nextFrame:frame playing:playing];
    }

    return YES;
}

- (void)loadLazySample:(LazySample*)lazySample nextFrame:(unsigned long long)nextFrame playing:(BOOL)playing
{
    // We keep a reference around so that the `sample` setter will cause the possibly
    // ongoing decode of a previous sample to get aborted.
    self.lazySample = lazySample;
        
    [self loadTrackState:LoadStateInit value:0.0];
    [self loadTrackState:LoadStateStopped value:0.0];

    self.visualSample = [[VisualSample alloc] initWithSample:self.lazySample
                                              pixelPerSecond:kPixelPerSecond
                                                   tileWidth:kDirectWaveViewTileWidth];

    _controlPanelController.bpm.stringValue = @"--- BPM";
    
    _waveLayerDelegate.visualSample = self.visualSample;

    _totalVisual = [[VisualSample alloc] initWithSample:self.lazySample
                                         pixelPerSecond:self.totalView.bounds.size.width / _lazySample.duration
                                              tileWidth:kTotalWaveViewTileWidth];

    _totalWaveLayerDelegate.visualSample = self.totalVisual;

    [_lazySample decodeAsyncWithCallback:^(BOOL decodeFinished){
        if (decodeFinished) {
            [self lazySampleDecoded];
       } else {
            NSLog(@"never finished the decoding");
        }
    }];

    _audioController.sample = _lazySample;
    _waveView.frames = _lazySample.frames;
    _waveRenderer.visualSample = self.visualSample;
    _totalView.frames = _lazySample.frames;
    _waveView.frame = CGRectMake(0.0,
                                 0.0,
                                 self.visualSample.width,
                                 self.waveView.bounds.size.height);
    [_totalView refresh];

    [_audioController playWhenReady:(unsigned long long)nextFrame paused:!playing];
}

- (void)lazySampleDecoded
{
    BeatTrackedSample* beatSample = [[BeatTrackedSample alloc] initWithSample:_lazySample framesPerPixel:self.visualSample.framesPerPixel];
    self.beatLayerDelegate.beatSample = beatSample;

    if (_beatSample != nil) {
        NSLog(@"beats tracking may need decode aborting");
        [_beatSample abortWithCallback:^{
            [self loadBeats:beatSample];
        }];
    } else {
        [self loadBeats:beatSample];
    }
}

- (void)loadBeats:(BeatTrackedSample*)beatsSample
{
    self.beatSample = beatsSample;
    [self.beatSample trackBeatsAsyncWithCallback:^(BOOL beatsFinished){
        if (beatsFinished) {
            [self.waveView invalidateTiles];
            [self beatEffectStart];
        } else {
            NSLog(@"never finished the beat tracking");
        }
    }];
}

- (void)setMeta:(MediaMetaData*)meta
{
    _meta = meta;

    [self.playlist setCurrent:meta];
    
    // Update meta data in playback box.
    _controlPanelController.meta = meta;
}

#pragma mark Drag & Drop

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

#pragma mark Keyboard events

- (void)keyDown:(NSEvent *)event
{
    NSString *characters;
    unichar firstCharacter;

    // We would like to use -interpretKeyEvents:, but then *all* key events would get interpreted into selectors,
    // and NSTableView does not implement the proper selectors (like moveUp: for up arrow). Instead it apparently
    // checks key codes manually in -keyDown. So, we do the same.
    // Key codes are taken from /System/Library/Frameworks/AppKit.framework/Resources/StandardKeyBinding.dict.

    characters = [event characters];
    firstCharacter = [characters characterAtIndex:0];

    if (firstCharacter == 0x20) {
        // Play / Pause
        NSLog(@"play / pause");
    } else {
        [super keyDown:event];
    }
}

#pragma mark Mouse events

- (void)mouseDown:(NSEvent*)event
{
    NSPoint locationInWindow = [event locationInWindow];

    NSPoint location = [_waveView convertPoint:locationInWindow fromView:nil];
    if (NSPointInRect(location, _waveView.bounds)) {
        unsigned long long seekTo = (_visualSample.sample.frames * location.x ) / _waveView.frame.size.width;
        NSLog(@"mouse down in wave view %f:%f -- seeking to %lld\n", location.x, location.y, seekTo);
        [self progressSeekTo:seekTo];
        if (![_audioController playing]) {
            NSLog(@"not playing, he claims...");
            [_audioController playPause];
        }
        return;
    }

    location = [_totalView convertPoint:locationInWindow fromView:nil];
    if (NSPointInRect(location, _totalView.bounds)) {
        unsigned long long seekTo = (_totalVisual.sample.frames * location.x ) / _totalView.frame.size.width;
        NSLog(@"mouse down in total wave view %f:%f -- seeking to %lld\n", location.x, location.y, seekTo);
        [self progressSeekTo:seekTo];
        if (![_audioController playing]) {
            NSLog(@"not playing, he claims...");
            [_audioController playPause];
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
        [self progressSeekTo:seekTo];
        if (![_audioController playing]) {
            NSLog(@"not playing, he claims...");
            [_audioController playPause];
        }
        return;
    }
    location = [_totalView convertPoint:locationInWindow fromView:nil];
    if (NSPointInRect(location, _totalView.bounds)) {
        unsigned long long seekTo = (_totalVisual.sample.frames * location.x ) / _totalView.frame.size.width;
        NSLog(@"mouse down in total wave view %f:%f -- seeking to %lld\n", location.x, location.y, seekTo);
        [self progressSeekTo:seekTo];
        if (![_audioController playing]) {
            NSLog(@"not playing, he claims...");
            [_audioController playPause];
        }
    }
}

#pragma mark Browser delegate

- (void)addToPlaylistNext:(MediaMetaData *)meta
{
    [_playlist addNext:meta];
}

- (void)addToPlaylistLater:(MediaMetaData *)meta
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

- (void)audioControllerPlaybackStarted
{
    NSLog(@"audioControllerPlaybackStarted");
    // Establish a link and callback invoked on vsync.
    CVDisplayLinkStart(_displayLink);
    // Start the scope renderer.
    [_renderer play:_audioController visual:_visualSample scope:_scopeView];
    // Make state obvious to user.
    [self setPlaybackActive:YES];
    [_playlist touchedItem:_meta];
    [_playlist setPlaying:YES];

    [self lockScreen];
}

- (void)audioControllerPlaybackPaused
{
    NSLog(@"audioControllerPlaybackPaused");
    // Make state obvious to user.
    [self setPlaybackActive:NO];
    [_playlist setPlaying:NO];

    [self unlockScreen];
}

- (void)audioControllerPlaybackPlaying
{
    NSLog(@"audioControllerPlaybackPlaying");
    // Make state obvious to user.
    [self setPlaybackActive:YES];
    [_playlist setPlaying:YES];

    [self lockScreen];
}

- (void)audioControllerPlaybackEnded
{
    NSLog(@"audioControllerPlaybackEnded");
    // Make state obvious to user.
    [self setPlaybackActive:NO];
    [_playlist setPlaying:NO];

    [self unlockScreen];

    // Stop the scope rendering.
    [_renderer stop:_scopeView];

    // Remove our hook to the vsync.
    CVDisplayLinkStop(_displayLink);

    MediaMetaData* item = nil;
    if (_controlPanelController.loop.state == NSControlStateValueOn) {
        [self playPause:self];
        return;
    }
    
    item = [_playlist nextItem];
    if (item == nil) {
        [self stop];
        return;
    }

    [self loadDocumentFromURL:[WaveWindowController encodeQueryItemsWithUrl:item.location frame:0LL playing:YES] meta:item];
}

- (void)stop
{
}

#pragma mark - Control Panel delegate

- (void)volumeChange:(id)sender
{
    _audioController.outputVolume = _controlPanelController.volumeSlider.doubleValue;
}

- (void)tempoChange:(id)sender
{
    _audioController.tempoShift = _controlPanelController.tempoSlider.doubleValue;
}

- (void)playPause:(id)sender
{
    [_audioController playPause];
}

- (void)progressSeekTo:(unsigned long long)frame
{
    _audioController.currentFrame = frame;
    [self beatEffectStart];
}

#pragma mark - Full Screen Support: Persisting and Restoring Window's Non-FullScreen Frame

+ (NSArray *)restorableStateKeyPaths
{
    return [[super restorableStateKeyPaths] arrayByAddingObject:@"frameForNonFullScreenMode"];
}

#pragma mark - InfoPanelControllerDelegate

- (BOOL)playing
{
    return _audioController.playing;
}

- (MediaMetaData*)currentSongMeta
{
    return _meta;
}

- (NSArray<MediaMetaData*>*)selectedSongMetas
{
    return [_browser selectedSongMetas];
}

- (NSArray<NSString*>*)knownGenres
{
    return [_browser knownGenres];
}

- (void)metaChangedForMeta:(MediaMetaData *)meta updatedMeta:(MediaMetaData *)updatedMeta
{
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
