//
//  WindowController.h
//  PlayEm
//
//  Created by Till Toenshoff on 29.05.20.
//  Copyright © 2020 Till Toenshoff. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import <QuartzCore/QuartzCore.h>
#import <AVKit/AVKit.h>

#import "AudioController.h"
#import "BrowserController.h"
#import "PlaylistController.h"
#import "TiledScrollView.h"
#import "ScopeRenderer.h"
#import "ScopeView.h"
#import "ControlPanelController.h"
#import "InfoPanel.h"
//#import "SPMediaKeyTap.h"

NS_ASSUME_NONNULL_BEGIN

@class MTKView;

@class MediaMetaData;
@class VisualSample;
@class BeatTrackedSample;
@class KeyTrackedSample;
@class TotalWaveView;
@class ScrollingTextView;
@class InfoPanelController;
@class IdentifyController;
@class WaveView;
@class MetalWaveView;
@class AVRoutePickerView;

@interface WaveWindowController : NSWindowController <NSWindowDelegate,
                                                      NSToolbarDelegate,
                                                      NSToolbarItemValidation,
                                                      BrowserControllerDelegate,
                                                      PlaylistControllerDelegate,
                                                      ScopeRendererDelegate,
                                                      ControlPanelControllerDelegate,
                                                      InfoPanelControllerDelegate,
                                                      NSSplitViewDelegate,
                                                      NSMenuDelegate,
                                                      AVRoutePickerViewDelegate>
//SPMediaKeyTapDelegate>

@property (nonatomic, strong) AudioController* audioController;

@property (strong, nonatomic) VisualSample* totalVisual;
@property (strong, nonatomic) VisualSample* visualSample;
@property (strong, nonatomic) BeatTrackedSample* beatSample;
@property (strong, nonatomic) KeyTrackedSample* keySample;

@property (strong, nonatomic) BrowserController* browser;
@property (strong, nonatomic) ScopeView* smallScopeView;
@property (strong, nonatomic) IBOutlet NSView* belowVisuals;
@property (strong, nonatomic) IBOutlet TotalWaveView* totalView;
@property (strong, nonatomic) IBOutlet WaveView* waveView;
//@property (strong, nonatomic) IBOutlet MetalWaveView* metalWaveView;
@property (strong, nonatomic) IBOutlet ScopeView* scopeView;
@property (strong, nonatomic) IBOutlet NSVisualEffectView* effectBelowPlaylist;
@property (strong, nonatomic) IBOutlet NSTextField* songsCount;

@property (strong, nonatomic) IBOutlet NSTableView* songsTable;
@property (strong, nonatomic) IBOutlet NSTableView* genreTable;
@property (strong, nonatomic) IBOutlet NSTableView* artistsTable;
@property (strong, nonatomic) IBOutlet NSTableView* albumsTable;
@property (strong, nonatomic) IBOutlet NSTableView* temposTable;
@property (strong, nonatomic) IBOutlet NSTableView* keysTable;

@property (strong, nonatomic) IBOutlet NSProgressIndicator* progress;
@property (strong, nonatomic) IBOutlet NSProgressIndicator* trackLoadProgress;
@property (strong, nonatomic) IBOutlet NSProgressIndicator* trackRenderProgress;
@property (strong, nonatomic) IBOutlet NSProgressIndicator* trackSeekingProgress;

@property (strong, nonatomic) IBOutlet NSSplitView* split;
@property (strong, nonatomic) IBOutlet NSSplitView* splitSelectors;
@property (strong, nonatomic) IBOutlet NSTableView* playlistTable;
@property (strong, nonatomic) IdentifyController* iffy;
@property (strong, nonatomic, nullable) NSMenu* dockMenu;


@property (strong, nonatomic) NSSplitViewController* splitViewController;

- (id)init;
+ (NSURL*)encodeQueryItemsWithUrl:(NSURL*)url frame:(unsigned long long)frame playing:(BOOL)playing;
- (void)setCurrentFrame:(unsigned long long)frame;
- (BOOL)loadDocumentFromURL:(NSURL*)url meta:(nullable MediaMetaData*)meta;
- (IBAction)loadITunesLibrary:(id)sender;
- (IBAction)showInfoForCurrentSong:(id)sender;
- (IBAction)showInfoForSelectedSongs:(id)sender;
- (IBAction)showPlaylist:(id)sender;
- (IBAction)playNext:(id)sender;
- (IBAction)playPrevious:(id)sender;
- (IBAction)togglePause:(id)sender;
- (IBAction)volumeIncrease:(id)sender;
- (IBAction)volumeDecrease:(id)sender;
- (IBAction)seekToFrame:(unsigned long long)frame;

@end

NS_ASSUME_NONNULL_END
