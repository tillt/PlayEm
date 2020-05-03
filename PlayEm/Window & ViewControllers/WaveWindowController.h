//
//  WindowController.h
//  PlayEm
//
//  Created by Till Toenshoff on 29.05.20.
//  Copyright © 2020 Till Toenshoff. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import <QuartzCore/QuartzCore.h>

#import "AudioController.h"
#import "BrowserController.h"
#import "PlaylistController.h"
#import "TiledScrollView.h"
#import "ScopeRenderer.h"
#import "ScopeView.h"
#import "ControlPanelController.h"

NS_ASSUME_NONNULL_BEGIN

@class MTKView;

@class MediaMetaData;
@class VisualSample;
@class TotalWaveView;
@class ScrollingTextView;
@class InfoPanelController;
@class IdentifyController;

@interface WaveWindowController : NSWindowController <NSWindowDelegate,
                                                      NSToolbarDelegate,
                                                      NSToolbarItemValidation,
                                                      AudioControllerDelegate,
                                                      BrowserControllerDelegate,
                                                      PlaylistControllerDelegate,
                                                      ScopeRendererDelegate,
                                                      ControlPanelControllerDelegate,
                                                      NSSplitViewDelegate,
                                                      CALayerDelegate,
                                                      NSMenuDelegate>
  
@property (nonatomic, strong) AudioController* audioController;

@property (strong, nonatomic) VisualSample* totalVisual;
@property (strong, nonatomic) VisualSample* visualSample;


@property (strong, nonatomic) BrowserController* browser;

@property (strong, nonatomic) InfoPanelController* infoPanel;


@property (strong, nonatomic) ScopeView* smallScopeView;
@property (strong, nonatomic) IBOutlet NSView* belowVisuals;
@property (strong, nonatomic) IBOutlet TotalWaveView* totalView;
@property (strong, nonatomic) IBOutlet WaveView* waveView;
@property (strong, nonatomic) IBOutlet ScopeView* scopeView;
@property (strong, nonatomic) IBOutlet NSVisualEffectView* effectBelowPlaylist;
@property (strong, nonatomic) IBOutlet NSTextField* songsCount;

@property (strong, nonatomic) IBOutlet NSTableView* songsTable;
@property (strong, nonatomic) IBOutlet NSTableView* genreTable;
@property (strong, nonatomic) IBOutlet NSTableView* artistsTable;
@property (strong, nonatomic) IBOutlet NSTableView* albumsTable;
@property (strong, nonatomic) IBOutlet NSTableView* bpmTable;
@property (strong, nonatomic) IBOutlet NSTableView* keyTable;

@property (strong, nonatomic) IBOutlet NSProgressIndicator* progress;
@property (strong, nonatomic) IBOutlet NSProgressIndicator* trackLoadProgress;
@property (strong, nonatomic) IBOutlet NSProgressIndicator* trackRenderProgress;

@property (strong, nonatomic) IBOutlet NSSplitView* split;
@property (strong, nonatomic) IBOutlet NSSplitView* splitSelectors;
@property (strong, nonatomic) IBOutlet NSTableView* playlistTable;
@property (strong, nonatomic) IdentifyController* iffy;

@property (strong, nonatomic) NSSplitViewController* splitViewController;


- (id)init;
- (void)setCurrentFrame:(unsigned long long)frame;
- (BOOL)loadDocumentFromURL:(NSURL*)url meta:(nullable MediaMetaData*)meta error:(NSError**)error;
- (IBAction)toggleFullScreen:(id)sender;
- (IBAction)loadITunesLibrary:(id)sender;
- (IBAction)showInfo:(id)sender;
- (IBAction)showPlaylist:(id)sender;

@end

NS_ASSUME_NONNULL_END
