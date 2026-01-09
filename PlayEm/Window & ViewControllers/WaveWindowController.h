//
//  WindowController.h
//  PlayEm
//
//  Created by Till Toenshoff on 29.05.20.
//  Copyright © 2020 Till Toenshoff. All rights reserved.
//

#import <AVKit/AVKit.h>
#import <Cocoa/Cocoa.h>
#import <QuartzCore/QuartzCore.h>

#import "AudioController.h"
#import "BrowserController.h"
#import "ControlPanelController.h"
#import "IdentifyViewController.h"
#import "InfoPanel.h"
#import "PlaylistController.h"
#import "ScopeRenderer.h"
#import "ScopeView.h"
#import "TracklistController.h"
#import "WaveViewController.h"

NS_ASSUME_NONNULL_BEGIN

@class MTKView;

@class MediaMetaData;
@class VisualSample;
@class BeatTrackedSample;
@class KeyTrackedSample;
@class TotalWaveView;
@class InfoPanelController;
@class IdentifyViewController;
@class WaveView;
@class MetalWaveView;
@class AVRoutePickerView;
@class MetaController;

@interface WaveWindowController
    : NSWindowController <NSWindowDelegate, NSToolbarDelegate, NSToolbarItemValidation, BrowserControllerDelegate, PlaylistControllerDelegate,
                          TracklistControllerDelegate, ScopeRendererDelegate, ControlPanelControllerDelegate, InfoPanelControllerDelegate,
                          IdentifyViewControllerDelegate, WaveViewControllerDelegate, NSSplitViewDelegate, NSMenuDelegate, AVRoutePickerViewDelegate>
// SPMediaKeyTapDelegate>

@property (nonatomic, strong) AudioController* audioController;

@property (strong, nonatomic) VisualSample* totalVisual;
@property (strong, nonatomic) VisualSample* visualSample;
@property (strong, nonatomic) BeatTrackedSample* beatSample;
@property (strong, nonatomic) KeyTrackedSample* keySample;

@property (strong, nonatomic) BrowserController* browser;
@property (strong, nonatomic) ScopeView* smallScopeView;
@property (strong, nonatomic) IBOutlet NSView* belowVisuals;
//@property (strong, nonatomic) IBOutlet TotalWaveView* totalView;
//@property (strong, nonatomic) IBOutlet WaveView* waveView;
//@property (strong, nonatomic) IBOutlet MetalWaveView* metalWaveView;
@property (strong, nonatomic) IBOutlet ScopeView* scopeView;
@property (strong, nonatomic) IBOutlet NSVisualEffectView* effectBelowPlaylist;
@property (strong, nonatomic) IBOutlet NSTextField* songsCount;

@property (strong, nonatomic) IBOutlet NSProgressIndicator* progress;
@property (strong, nonatomic) IBOutlet NSProgressIndicator* trackLoadProgress;
@property (strong, nonatomic) IBOutlet NSProgressIndicator* trackRenderProgress;
@property (strong, nonatomic) IBOutlet NSProgressIndicator* trackSeekingProgress;

@property (strong, nonatomic) IBOutlet NSSplitView* horizontalSplitView;
@property (strong, nonatomic) IBOutlet NSSplitView* browserColumnSplitView;
@property (strong, nonatomic) IdentifyViewController* iffy;
@property (strong, nonatomic, nullable) NSMenu* dockMenu;

@property (strong, nonatomic) NSSplitViewController* splitViewController;

- (id)init;
+ (NSURL*)encodeQueryItemsWithUrl:(NSURL*)url frame:(unsigned long long)frame playing:(BOOL)playing;
- (BOOL)loadDocumentFromURL:(NSURL*)url meta:(nullable MediaMetaData*)meta;
- (IBAction)loadITunesLibrary:(id)sender;

- (IBAction)showPlaylist:(id)sender;
- (IBAction)showAbout:(id)sender;
- (IBAction)showIdentifier:(id)sender;
- (IBAction)showActivity:(id)sender;
- (IBAction)startTrackDetection:(id)sender;
- (IBAction)showEffects:(id)sender;


- (IBAction)playNext:(id)sender;
- (IBAction)playPrevious:(id)sender;

- (IBAction)togglePause:(id)sender;

- (IBAction)volumeIncrease:(id)sender;
- (IBAction)volumeDecrease:(id)sender;

- (IBAction)seekToFrame:(unsigned long long)frame;
- (void)setCurrentFrame:(unsigned long long)frame;

- (IBAction)skip1Beat:(id)sender;
- (IBAction)repeat1Beat:(id)sender;
- (IBAction)skip1Bar:(id)sender;
- (IBAction)repeat1Bar:(id)sender;
- (IBAction)skip4Bars:(id)sender;
- (IBAction)repeat4Bars:(id)sender;

@end

NS_ASSUME_NONNULL_END
