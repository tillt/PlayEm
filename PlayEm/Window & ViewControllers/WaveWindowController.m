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

#import "WaveWindowController.h"
#import "AudioController.h"
#import "VisualSample.h"
#import "LazySample.h"
#import "BrowserController.h"
#import "PlaylistController.h"
#import "LoadState.h"
#import "MediaMetaData.h"
#import "ScopeRenderer.h"
#import "TotalWaveView.h"
#import "UIView+Visibility.h"
#import "InfoPanel.h"
#import "ScrollingTextView.h"
#import "TableHeaderCell.h"
#import "ControlPanelController.h"
#import "IdentifyController.h"
#import "Defaults.h"

static const float kShowHidePanelAnimationDuration = 0.3f;
static const float kEnoughSecondsDecoded = 3.0f;


@interface WaveWindowController ()
{
    CGFloat splitPosition[2];
    CGFloat splitPositionMemory[2];
    CGFloat splitSelectorPositionMemory[5];
}

@property (assign, nonatomic) CGFloat windowBarHeight;
@property (assign, nonatomic) CGRect smallBelowVisualsFrame;
@property (assign, nonatomic) CGFloat smallSplitter1Position;
@property (assign, nonatomic) CGFloat smallSplitter2Position;


@property (strong, nonatomic) NSTimer* timer;
@property (strong, nonatomic) ScopeRenderer* renderer;
@property (assign, nonatomic) CGRect preFullscreenFrame;
@property (strong, nonatomic) LazySample* sample;
@property (assign, nonatomic) BOOL inTransition;
@property (strong, nonatomic) PlaylistController* playlist;
@property (strong, nonatomic) MediaMetaData* meta;

@property (strong, nonatomic) ControlPanelController* controlPanelController;

@property (strong, nonatomic) NSPopover* popOver;
@property (strong, nonatomic) NSPopover* infoPopOver;

- (void)stop;

@end


@implementation WaveWindowController
{
    CVDisplayLinkRef _displayLink;
}

// Vertical sync callback.
static CVReturn renderCallback(CVDisplayLinkRef displayLink,
                               const CVTimeStamp* inNow,
                               const CVTimeStamp* inOutputTime,
                               CVOptionFlags flagsIn,
                               CVOptionFlags* flagsOut,
                               void* displayLinkContext)
{
    static unsigned int counter = 0;

    assert(displayLinkContext);
    WaveWindowController* controller = (__bridge WaveWindowController*)displayLinkContext;

    ++counter;

    // Update the controller with the current playback position to trigger screen updates.
    dispatch_async(dispatch_get_main_queue(), ^{
        controller.currentFrame = controller.audioController.currentFrame;
//        if ((counter % 2) == 0) {
//            [controller updateSlowScreenStuff];
//        }
    });
    
    return kCVReturnSuccess;
}

- (id)init
{
    self = [super initWithWindowNibName:@""];
    if (self) {
    }
    return self;
}

- (void)dealloc
{
    if (_displayLink) {
        CVDisplayLinkRelease(_displayLink);
    }
}

- (void)setSample:(LazySample*)sample
{
    if (_sample == sample) {
        return;
    }
    [_sample abortDecode];
    _sample = sample;
    NSLog(@"sample assigned");
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
        enable = (_sample != nil) & _audioController.playing;
    }
    return enable;
}

- (NSToolbarItem *)toolbar:(NSToolbar *)toolbar itemForItemIdentifier:(NSToolbarItemIdentifier)itemIdentifier willBeInsertedIntoToolbar:(BOOL)flag
{
    //let isBordered = true
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

- (void)loadWindow
{
    NSLog(@"loadWindow...");
    self.window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 1180, 1050)
                                              styleMask: NSWindowStyleMaskTitled
                   | NSWindowStyleMaskClosable
                   | NSWindowStyleMaskUnifiedTitleAndToolbar
                   | NSWindowStyleMaskMiniaturizable
                   | NSWindowStyleMaskResizable
                                                backing:NSBackingStoreBuffered defer:YES];

    self.window.titlebarSeparatorStyle = NSTitlebarSeparatorStyleLine;
    self.window.titlebarAppearsTransparent = YES;
    self.window.titleVisibility = NO;
    self.window.movableByWindowBackground = YES;

    NSToolbar* toolBar = [[NSToolbar alloc] init];
    toolBar.displayMode = NSToolbarDisplayModeIconOnly;
    toolBar.allowsUserCustomization = NO;
    toolBar.autosavesConfiguration = NO;
    toolBar.delegate = self;
    self.window.toolbar = toolBar;

    _infoPanel = [InfoPanelController new];

    _controlPanelController = [ControlPanelController new];
    _controlPanelController.layoutAttribute = NSLayoutAttributeLeft;
    [self.window addTitlebarAccessoryViewController:_controlPanelController];

    _splitViewController = [NSSplitViewController new];

    [self.window center];
    
    [self loadViews];
}

- (void)loadViews
{
    NSSize size = self.window.contentView.frame.size;
    
    const CGFloat totalWaveViewHeight = 46.0;
    const CGFloat scrollingWaveViewHeight = 158.0;
    const CGFloat scopeViewHeight = 353.0;
    //const CGFloat infoFxViewWidth = 465.0;
    const CGFloat playlistFxViewWidth = 280.0;
    const CGFloat statusLineHeight = 14.0;
    const CGFloat songsTableViewHeight = 307.0;
    const CGFloat selectorTableViewWidth = floor(size.width / 4);
    const CGFloat selectorTableViewHeight = 200.0;
   
    const CGFloat selectorTableViewHalfWidth = floor(selectorTableViewWidth / 2.0);
    
    const CGFloat selectorColumnInset = 17.0;
    
    const CGFloat trackColumnWidth = 64.0;
    const CGFloat titleColumnWidth = 200.0f;
    const CGFloat timeColumnWidth = 200.0f;
    const CGFloat artistColumnWidth = 200.0f;
    const CGFloat albumColumnWidth = 200.0f;
    const CGFloat genreColumnWidth = 150.0f;
    const CGFloat addedColumnWidth = 150.0f;
    
    const CGFloat progressIndicatorWidth = 32.0;
    const CGFloat progressIndicatorHeight = 32.0;
    
    const CGFloat totalHeight =
    totalWaveViewHeight +
    scrollingWaveViewHeight +
    scopeViewHeight +
    selectorTableViewHeight +
    songsTableViewHeight;
    
    CGFloat y = 0.0;
    
    const NSAutoresizingMaskOptions kViewFullySizeable = NSViewHeightSizable | NSViewWidthSizable;
    
    NSMenu* menu = [NSMenu new];
    
    NSMenuItem* item = [[NSMenuItem alloc] initWithTitle:@"Play Next" action:@selector(playNext:) keyEquivalent:@"n"];
    [item setKeyEquivalentModifierMask:NSEventModifierFlagCommand];
    [menu addItem:item];
    item = [[NSMenuItem alloc] initWithTitle:@"Play Later" action:@selector(playLater:) keyEquivalent:@"l"];
    [item setKeyEquivalentModifierMask:NSEventModifierFlagCommand];
    [menu addItem:item];
    [menu addItem:[NSMenuItem separatorItem]];
    [menu addItemWithTitle:@"Show Info" action:@selector(showInfoshowInfo:) keyEquivalent:@""];
    [menu addItem:[NSMenuItem separatorItem]];
    [menu addItemWithTitle:@"Show in Finder" action:@selector(showInFinder:) keyEquivalent:@""];
    
    // Status Line.
    _songsCount = [[NSTextField alloc] initWithFrame:NSMakeRect(0.0,
                                                                0.0,
                                                                size.width,
                                                                statusLineHeight)];
    _songsCount.font = [NSFont systemFontOfSize:11.0];
    _songsCount.textColor = [NSColor tertiaryLabelColor];
    _songsCount.bordered = NO;
    _songsCount.alignment = NSTextAlignmentCenter;
    _songsCount.autoresizingMask = NSViewWidthSizable;
    
    [self.window.contentView addSubview:_songsCount];
    y += statusLineHeight;
    
    _split = [[NSSplitView alloc] initWithFrame:NSMakeRect(0.0,
                                                           y,
                                                           size.width,
                                                           totalHeight)];
    _split.autoresizingMask = kViewFullySizeable;
    _split.dividerStyle = NSSplitViewDividerStyleThin;
    _split.autosaveName = @"VerticalSplitter";
    _split.delegate = self;
    _split.identifier = @"VerticalSplitter";

    // Below Visuals.
    CGFloat height = totalWaveViewHeight + scrollingWaveViewHeight + scopeViewHeight;
    
    _belowVisuals = [[NSView alloc] initWithFrame:NSMakeRect(0.0,
                                                             y,
                                                             size.width,
                                                             height )];
    _belowVisuals.autoresizingMask = kViewFullySizeable;
    
    self.window.contentView.wantsLayer = YES;
    self.window.contentView.layer.backgroundColor = [[[Defaults sharedDefaults] backColor] CGColor];
    
    //
    _totalView = [[TotalWaveView alloc] initWithFrame:NSMakeRect(0.0,
                                                                 0.0,
                                                                 size.width,
                                                                 totalWaveViewHeight)];
    _totalView.layerDelegate = self;
    _totalView.autoresizingMask = NSViewWidthSizable | NSViewMaxYMargin;
    [_belowVisuals addSubview:_totalView];
    
    TiledScrollView* tiledSV = [[TiledScrollView alloc] initWithFrame:NSMakeRect(0.0,
                                                                                 totalWaveViewHeight,
                                                                                 size.width,
                                                                                 scrollingWaveViewHeight)];
    tiledSV.autoresizingMask = NSViewWidthSizable | NSViewMaxYMargin;
    tiledSV.drawsBackground = NO;
    tiledSV.verticalScrollElasticity = NSScrollElasticityNone;

    _waveView = [[WaveView alloc] initWithFrame:tiledSV.bounds];
    _waveView.layerDelegate = self;
    tiledSV.documentView = _waveView;
    
    [_belowVisuals addSubview:tiledSV];

    NSBox* line = [[NSBox alloc] initWithFrame:NSMakeRect(0.0, totalWaveViewHeight, size.width, 1.0)];
//    line.borderColor = [NSColor blackColor];
    line.boxType = NSBoxSeparator;
    line.autoresizingMask = NSViewWidthSizable;
    [_belowVisuals addSubview:line];

    [self putScopeViewWithFrame:NSMakeRect(0.0,
                                           totalWaveViewHeight + scrollingWaveViewHeight,
                                           size.width,
                                           scopeViewHeight)
                         onView:_belowVisuals];
    _smallScopeView = _scopeView;

    line = [[NSBox alloc] initWithFrame:NSMakeRect(0.0, scrollingWaveViewHeight + totalWaveViewHeight - 1, size.width, 1.0)];
//    line.borderColor = [NSColor blackColor];
    line.boxType = NSBoxSeparator;
    line.autoresizingMask = NSViewWidthSizable;
    [_belowVisuals addSubview:line];
    
    _effectBelowPlaylist = [[NSVisualEffectView alloc] initWithFrame:NSMakeRect(size.width,
                                                                                 0.0,
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
    
    [_belowVisuals addSubview:_effectBelowPlaylist];
    
    [_split addArrangedSubview:_belowVisuals];
    
    ///
    /// Genre, Artist, Album, BPM, Key Tables.
    ///
    _splitSelectors = [[NSSplitView alloc] initWithFrame:NSMakeRect(0.0,
                                                                                0.0,
                                                                                size.width,
                                                                                selectorTableViewHeight)];
    _splitSelectors.autosaveName = @"HorizontalSplitters";
    _splitSelectors.vertical = YES;
    _splitSelectors.delegate = self;
    _splitSelectors.identifier = @"HorizontalSplitters";
    _splitSelectors.dividerStyle = NSSplitViewDividerStyleThin;
    
    sv = [[NSScrollView alloc] initWithFrame:NSMakeRect(0.0,
                                                                      0.0,
                                                                      selectorTableViewWidth,
                                                                      selectorTableViewHeight)];
    sv.hasVerticalScroller = YES;
    sv.autoresizingMask = kViewFullySizeable;
    sv.drawsBackground = NO;
    _genreTable = [[NSTableView alloc] initWithFrame:NSZeroRect];
    _genreTable.style = NSTableViewStyleAutomatic;
    _genreTable.backgroundColor = [NSColor clearColor];
    _genreTable.tag = VIEWTAG_GENRE;
    
    col = [[NSTableColumn alloc] init];
    col.title = @"Genre";
    col.identifier = @"Genre";
    col.width = selectorTableViewWidth - selectorColumnInset;
    [_genreTable addTableColumn:col];
    sv.documentView = _genreTable;
    //[self.window.contentView addSubview:sv];
    [_splitSelectors addArrangedSubview:sv];
    
    sv = [[NSScrollView alloc] initWithFrame:NSMakeRect(0.0,
                                                        0.0,
                                                        selectorTableViewWidth,
                                                        selectorTableViewHeight)];
    sv.drawsBackground = NO;
    sv.hasVerticalScroller = YES;
    sv.autoresizingMask = kViewFullySizeable;
    _artistsTable = [[NSTableView alloc] initWithFrame:NSZeroRect];
    _artistsTable.tag = VIEWTAG_ARTISTS;
    _artistsTable.backgroundColor = [NSColor clearColor];
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
    _albumsTable.backgroundColor = [NSColor clearColor];
    col = [[NSTableColumn alloc] init];
    col.title = @"Albums";
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
    _bpmTable = [[NSTableView alloc] initWithFrame:sv.bounds];
    _bpmTable.backgroundColor = [NSColor clearColor];
    
    col = [[NSTableColumn alloc] init];
    col.title = @"BPM";
    col.width = selectorTableViewHalfWidth - selectorColumnInset;
    [_bpmTable addTableColumn:col];
    sv.documentView = _bpmTable;
    //[self.window.contentView addSubview:sv];
    [_splitSelectors addArrangedSubview:sv];
    
    sv = [[NSScrollView alloc] initWithFrame:NSMakeRect(0.0,
                                                        0.0,
                                                        selectorTableViewHalfWidth,
                                                        selectorTableViewHeight)];
    sv.hasVerticalScroller = YES;
    sv.autoresizingMask = kViewFullySizeable;
    sv.drawsBackground = NO;
    _keyTable = [[NSTableView alloc] initWithFrame:NSZeroRect];
    _keyTable.backgroundColor = [NSColor clearColor];
    col = [[NSTableColumn alloc] init];
    col.title = @"Key";
    col.width = selectorTableViewHalfWidth - selectorColumnInset;
    [_keyTable addTableColumn:col];
    sv.documentView = _keyTable;
    [_splitSelectors addArrangedSubview:sv];
    
    //[self.window.contentView addSubview:splitSelectors];
    [_split addArrangedSubview:_splitSelectors];
    
    ///
    /// Songs Table.
    ///
    sv = [[NSScrollView alloc] initWithFrame:NSMakeRect(0.0,
                                                        0.0,
                                                        size.width,
                                                        songsTableViewHeight)];
    sv.hasVerticalScroller = YES;
    sv.drawsBackground = NO;
    sv.autoresizingMask = kViewFullySizeable;
    _songsTable = [[NSTableView alloc] initWithFrame:NSZeroRect];
    _songsTable.backgroundColor = [NSColor clearColor];
    _songsTable.tag = VIEWTAG_FILTERED;
    _songsTable.menu = menu;
    
    col = [[NSTableColumn alloc] initWithIdentifier:@"TrackCell"];
    col.title = @"Track";
    col.width = trackColumnWidth - selectorColumnInset;
    col.sortDescriptorPrototype = [[NSSortDescriptor alloc] initWithKey:@"trackNumber" ascending:YES selector:@selector(compare:)];
    [_songsTable addTableColumn:col];
    
    col = [[NSTableColumn alloc] initWithIdentifier:@"TitleCell"];
    col.title = @"Title";
    col.width = titleColumnWidth - selectorColumnInset;
    col.sortDescriptorPrototype = [[NSSortDescriptor alloc] initWithKey:@"title" ascending:YES selector:@selector(compare:)];
    [_songsTable addTableColumn:col];
    
    col = [[NSTableColumn alloc] initWithIdentifier:@"TimeCell"];
    col.title = @"Time";
    col.width = timeColumnWidth - selectorColumnInset;
    col.sortDescriptorPrototype = [[NSSortDescriptor alloc] initWithKey:@"totalTime" ascending:YES selector:@selector(compare:)];
    [_songsTable addTableColumn:col];
    
    col = [[NSTableColumn alloc] initWithIdentifier:@"ArtistCell"];
    col.title = @"Artist";
    col.width = artistColumnWidth - selectorColumnInset;
    col.sortDescriptorPrototype = [[NSSortDescriptor alloc] initWithKey:@"artist.name" ascending:YES selector:@selector(compare:)];
    [_songsTable addTableColumn:col];
    
    col = [[NSTableColumn alloc] initWithIdentifier:@"AlbumCell"];
    col.title = @"Album";
    col.width = albumColumnWidth - selectorColumnInset;
    col.sortDescriptorPrototype = [[NSSortDescriptor alloc] initWithKey:@"album.title" ascending:YES selector:@selector(compare:)];
    [_songsTable addTableColumn:col];
    
    col = [[NSTableColumn alloc] initWithIdentifier:@"GenreCell"];
    col.title = @"Genre";
    col.width = genreColumnWidth - selectorColumnInset;
    col.sortDescriptorPrototype = [[NSSortDescriptor alloc] initWithKey:@"genre" ascending:YES selector:@selector(compare:)];
    [_songsTable addTableColumn:col];
    
    col = [[NSTableColumn alloc] initWithIdentifier:@"AddedCell"];
    col.title = @"Added";
    col.width = addedColumnWidth - selectorColumnInset;
    col.sortDescriptorPrototype = [[NSSortDescriptor alloc] initWithKey:@"addedDate" ascending:YES selector:@selector(compare:)];
    [_songsTable addTableColumn:col];
    
    sv.documentView = _songsTable;
    [_split addArrangedSubview:sv];

    [self.window.contentView addSubview:_split];
    
    _progress = [[NSProgressIndicator alloc] initWithFrame:NSMakeRect((size.width - progressIndicatorWidth) / 2.0,
                                                                      (size.height - progressIndicatorHeight) / 4.0,
                                                                      progressIndicatorWidth,
                                                                      progressIndicatorHeight)];
    _progress.style = NSProgressIndicatorStyleSpinning;
    _progress.displayedWhenStopped = NO;
    _progress.autoresizingMask =  NSViewNotSizable | NSViewMinXMargin | NSViewMaxXMargin| NSViewMinYMargin | NSViewMaxYMargin;
    
    [self.window.contentView addSubview:_progress];
    
    _trackRenderProgress = [[NSProgressIndicator alloc] initWithFrame:NSMakeRect((size.width - progressIndicatorWidth) / 2.0,
                                                                                 (size.height - progressIndicatorHeight) / 2.0,
                                                                                 progressIndicatorWidth,
                                                                                 progressIndicatorHeight)];
    _trackRenderProgress.style = NSProgressIndicatorStyleSpinning;
    _trackRenderProgress.displayedWhenStopped = NO;
    _trackRenderProgress.autoresizingMask = NSViewNotSizable | NSViewMinXMargin | NSViewMaxXMargin| NSViewMinYMargin | NSViewMaxYMargin;
    
    [self.window.contentView addSubview:_trackRenderProgress];

    _trackLoadProgress = [[NSProgressIndicator alloc] initWithFrame:NSMakeRect((size.width - progressIndicatorWidth) / 2.0,
                                                                               (size.height - progressIndicatorHeight) / 2.0,
                                                                               progressIndicatorWidth,
                                                                               progressIndicatorHeight)];
    _trackLoadProgress.style = NSProgressIndicatorStyleSpinning;
    _trackLoadProgress.displayedWhenStopped = NO;
    _trackLoadProgress.autoresizingMask =  NSViewNotSizable | NSViewMinXMargin | NSViewMaxXMargin| NSViewMinYMargin | NSViewMaxYMargin;
    
    [self.window.contentView addSubview:_trackLoadProgress];
}

//- (NSNibName)windowNibName
//{
//    return @"WaveWindow";
//}

- (void)windowDidLoad
{
    [super windowDidLoad];
    
    _browser = [[BrowserController alloc] initWithGenresTable:_genreTable
                                                 artistsTable:_artistsTable
                                                  albumsTable:_albumsTable
                                                   songsTable:_songsTable
                                                     delegate:self];

    // Replace the header cell in all of the main tables on this view.
    NSArray<NSTableView*>* fixupTables = @[ _songsTable,
                                            _genreTable,
                                            _artistsTable,
                                            _albumsTable,
                                            _bpmTable,
                                            _keyTable ];

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

    _sample = nil;
    
    _inTransition = NO;
   
    _waveView.color = [[Defaults sharedDefaults] regularBeamColor];
    
//    _effectBelowInfo.material = NSVisualEffectMaterialMenu;
//    _effectBelowInfo.blendingMode = NSVisualEffectBlendingModeWithinWindow;
//    _effectBelowInfo.alphaValue = 0.0f;

    _effectBelowPlaylist.material = NSVisualEffectMaterialMenu;
    _effectBelowPlaylist.blendingMode = NSVisualEffectBlendingModeWithinWindow;
    _effectBelowPlaylist.alphaValue = 0.0f;


//    _playPause.wantsLayer = YES;
//    _playPause.layer.cornerRadius = 5;
//    _playPause.layer.masksToBounds = YES;
//
    _smallBelowVisualsFrame = _belowVisuals.frame;

    _scopeView.device = MTLCreateSystemDefaultDevice();
    if(!_scopeView.device) {
        NSLog(@"Metal is not supported on this device");
    } else {
        _renderer = [[ScopeRenderer alloc] initWithMetalKitView:_scopeView
                                                          color:[[Defaults sharedDefaults] lightBeamColor]
                                                          fftColor:[[Defaults sharedDefaults] fftColor]
                                                     background:[[Defaults sharedDefaults] backColor]
                                                       delegate:self];
        _renderer.level = self.controlPanelController.level;

        [_renderer mtkView:_scopeView drawableSizeWillChange:_scopeView.bounds.size];
        _scopeView.delegate = _renderer;
        _scopeView.layer.opaque = false;
    }

    [self loadProgress:self.progress state:LoadStateStopped value:0.0];
    [self loadProgress:self.trackLoadProgress state:LoadStateStopped value:0.0];
    [self loadProgress:self.trackRenderProgress state:LoadStateStopped value:0.0];

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

    //self.trackLoadProgress.controlTint = NSBlueControlTint;
    //self.trackRenderProgress.controlTint = NSBlueControlTint;

    CGRect rect = CGRectMake(0.0, 0.0, self.window.frame.size.width, self.window.frame.size.height);
    CGRect contentRect = [self.window contentRectForFrameRect:rect];
    _windowBarHeight = self.window.frame.size.height - contentRect.size.height;

    [self.window registerForDraggedTypes:[NSArray arrayWithObjects: NSPasteboardTypeFileURL, NSPasteboardTypeSound, nil]];
    self.window.delegate = self;

    //self.window.contentViewController = _browser;

    _playlist = [[PlaylistController alloc] initWithPlaylistTable:_playlistTable delegate:self];
    
    CGDirectDisplayID   displayID = CGMainDisplayID();
    CVReturn            error = kCVReturnSuccess;
    error = CVDisplayLinkCreateWithCGDisplay(displayID, &_displayLink);
    if (error)
    {
        NSLog(@"DisplayLink created with error:%d", error);
        _displayLink = NULL;
    } else {
        CVDisplayLinkSetOutputCallback(_displayLink, renderCallback, (__bridge void *)self);
    }

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(ScrollViewStartsLiveScrolling:) name:@"NSScrollViewWillStartLiveScrollNotification" object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(ScrollViewEndsLiveScrolling:) name:@"NSScrollViewDidEndLiveScrollNotification" object:nil];
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
    // We might still be decoding a sample, stop that!
    [_sample abortDecode];
    // Finish playback, if anything was ongoing.
    [self stop];
}

- (void)windowDidEndLiveResize:(NSNotification *)notification
{
    [self putScopeViewWithFrame:NSMakeRect(_scopeView.frame.origin.x, _scopeView.frame.origin.y, _scopeView.frame.size.width, _scopeView.frame.size.height) onView:_belowVisuals];
    [_totalVisual setPixelPerSecond:_totalView.bounds.size.width / _sample.duration];
    [_totalView resize];
    [_totalView refresh];

}

- (void)windowDidResize:(NSNotification *)notification
{
    NSLog(@"windowDidResize to width %f", _scopeView.bounds.size.width);
    [_renderer mtkView:_scopeView drawableSizeWillChange:_scopeView.bounds.size];
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
/*        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        [window setStyleMask:([window styleMask] | NSWindowStyleMaskFullScreen)];
        //[window.contentView addSubview:self.belowVisuals];
        self.belowVisuals.frame = NSMakeRect(0.0f, 0.0f, window.screen.frame.size.width, window.screen.frame.size.height);
        //[self putScopeViewWithFrame:NSMakeRect(0.0f, 0.0f, window.screen.frame.size.width, window.screen.frame.size.height) onView:window.contentView];
        [CATransaction commit];
        */
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
    _bpmTable.enclosingScrollView.animator.hidden = toFullscreen ? YES : NO;
    _keyTable.enclosingScrollView.animator.hidden = toFullscreen ? YES : NO;

   if (toFullscreen) {
       memcpy(splitPositionMemory, splitPosition, sizeof(CGFloat) * 3);

//        // Restore the old positions.
//        [_splitSelectors setPosition:splitSelectorPositionMemory[0] ofDividerAtIndex:0];
//        [_splitSelectors setPosition:splitSelectorPositionMemory[1] ofDividerAtIndex:1];
//        [_splitSelectors setPosition:splitSelectorPositionMemory[2] ofDividerAtIndex:2];
//        [_splitSelectors setPosition:splitSelectorPositionMemory[3] ofDividerAtIndex:3];
//        [_splitSelectors setPosition:splitSelectorPositionMemory[4] ofDividerAtIndex:4];
    }

    [_splitSelectors adjustSubviews];

    _splitSelectors.animator.hidden = toFullscreen ? YES : NO;

    _songsTable.enclosingScrollView.animator.hidden = toFullscreen ? YES : NO;

    if (!toFullscreen) {
        // We quickly stash the position memory for making sure the first position set
        // can trash the stored positions immediately.
        CGFloat positions[3];
        memcpy(positions, splitPositionMemory, sizeof(CGFloat) * 3);
        [_split setPosition:splitPositionMemory[0] ofDividerAtIndex:0];
        [_split setPosition:splitPositionMemory[1] ofDividerAtIndex:1];
    }
    [_split adjustSubviews];
    NSLog(@"relayout to fullscreen %X\n", toFullscreen);
}

// Yeah right - what a shitty name for a function that does so much more!
- (void)putScopeViewWithFrame:(NSRect)frame onView:(NSView*)parent
{
    assert(frame.size.width * frame.size.height);

    ScopeView* sv = [[ScopeView alloc] initWithFrame:frame device:MTLCreateSystemDefaultDevice()];
    //sv.colorPixelFormat = MTLPixelFormatBGRA10_XR_sRGB;
    sv.colorPixelFormat = MTLPixelFormatBGRA8Unorm;
    sv.depthStencilPixelFormat = MTLPixelFormatInvalid;
    sv.drawableSize = frame.size;

    sv.autoresizingMask = NSViewHeightSizable | NSViewWidthSizable | NSViewMaxYMargin;
   
    sv.autoResizeDrawable = NO;

    self.renderer = [[ScopeRenderer alloc] initWithMetalKitView:sv
                                                          color:[[Defaults sharedDefaults] lightBeamColor]
                                                       fftColor:[[Defaults sharedDefaults] fftColor]
                                                     background:[[Defaults sharedDefaults] backColor]
                                                       delegate:self];
    _renderer.level = self.controlPanelController.level;
    sv.delegate = _renderer;
    sv.paused = NO;

    [parent addSubview:sv];

    [_scopeView removeFromSuperview];
    _scopeView = sv;

    if (_audioController && _visualSample) {
        [_renderer play:_audioController visual:_visualSample scope:sv];
    }

    //[parent addSubview:_controlPanel positioned:NSWindowAbove relativeTo:nil];
//    [parent addSubview:_effectBelowInfo positioned:NSWindowAbove relativeTo:nil];
    [parent addSubview:_effectBelowPlaylist positioned:NSWindowAbove relativeTo:nil];
}

- (void)setPlaybackActive:(BOOL)active
{
    _controlPanelController.playPause.state = active ? NSControlStateValueOn : NSControlStateValueOff;
}

- (void)showInfo:(id)sender
{
    [_infoPanel view];
    
    _infoPopOver = [[NSPopover alloc] init];
    _infoPopOver.contentViewController = _infoPanel;
    _infoPopOver.contentSize = _infoPanel.view.bounds.size;
    _infoPopOver.animates = YES;
    _infoPopOver.behavior = NSPopoverBehaviorTransient;

    NSRect entryRect = NSMakeRect(105.0,
                                  self.window.contentView.frame.size.height - 3.0,
                                  2.0,
                                  2.0);
   
    [_infoPopOver showRelativeToRect:entryRect
                              ofView:self.window.contentView
                       preferredEdge:NSMinYEdge];
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
//            _controlPanel.animator.frame = NSMakeRect(_controlPanel.frame.origin.x,
//                                                      _controlPanel.frame.origin.y,
//                                                      maxX - _controlPanel.frame.origin.x,
//                                                      _controlPanel.frame.size.height);
        } else {
            _effectBelowPlaylist.animator.frame = NSMakeRect(self.window.contentView.frame.origin.x + self.window.contentView.frame.size.width,
                                                             _effectBelowPlaylist.frame.origin.y,
                                                             _effectBelowPlaylist.frame.size.width,
                                                             _effectBelowPlaylist.frame.size.height);
//            _controlPanel.animator.frame = NSMakeRect(_controlPanel.frame.origin.x,
//                                                      _controlPanel.frame.origin.y,
//                                                      maxX - _controlPanel.frame.origin.x,
//                                                      _controlPanel.frame.size.height);
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

//
//- (void)showControlPanel:(id)sender
//{
//    CGFloat maxX = _effectBelowPlaylist.frame.origin.x;
//    CGFloat minX = _effectBelowInfo.frame.origin.x + _effectBelowInfo.frame.size.width;
//
//    BOOL isShow = _controlPanel.alphaValue == 0.0f;
//    
//    if (isShow) {
//        _controlPanel.alphaValue = 1.0f;
//    }
//    
//    [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
//        [context setDuration:kShowHidePanelAnimationDuration];
//        if (isShow) {
//            _controlPanel.animator.frame = NSMakeRect(minX,
//                                                      _belowVisuals.frame.origin.y + _belowVisuals.frame.size.height - _controlPanel.frame.size.height,
//                                                      maxX - minX,
//                                                      _controlPanel.frame.size.height);
//        } else {
//            _controlPanel.animator.frame = NSMakeRect(minX,
//                                                      _belowVisuals.frame.origin.y + _belowVisuals.frame.size.height,
//                                                      maxX - minX,
//                                                      _controlPanel.frame.size.height);
//        }
//    } completionHandler:^{
//        if (!isShow) {
//            self.controlPanel.alphaValue = 0.0f;
//        }
//    }];
//
//    //_controlPanel.animator.hidden = !_controlPanel.hidden;
//}

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

- (void)toggleFullScreen:(id)sender
{
    bool isFullscreen = NSEqualSizes(self.scopeView.frame.size, [[NSScreen mainScreen] frame].size);
    [self relayoutAnimated:!isFullscreen];
}

- (NSString*)beautifulTimeWithFrame:(unsigned long long)frame
{
    NSTimeInterval time = frame / _sample.rate;
    unsigned int hours = floor(time / 3600);
    unsigned int minutes = (unsigned int)floor(time) % 3600 / 60;
    unsigned int seconds = (unsigned int)floor(time) % 3600 % 60;
    if (hours > 0) {
        return [NSString stringWithFormat:@"%d:%02d:%02d", hours, minutes, seconds];
    }
    return [NSString stringWithFormat:@"%d:%02d", minutes, seconds];
}

- (void)setCurrentFrame:(unsigned long long)frame
{
    _controlPanelController.duration.stringValue = [self beautifulTimeWithFrame:_sample.frames - frame];
    _controlPanelController.time.stringValue = [self beautifulTimeWithFrame:frame];

    _waveView.currentFrame = frame;
    _totalView.currentFrame = frame;
}

- (IBAction)loadITunesLibrary:(id)sender
{
    [_browser loadITunesLibrary];
}

#pragma mark Splitter delegate

- (void)splitViewWillResizeSubviews:(NSNotification *)notification
{
    NSSplitView* sv = notification.object;
    NSNumber* indexNumber = notification.userInfo[@"NSSplitViewDividerIndex"];

    if (sv == _split) {
        if (indexNumber != nil) {
            switch(indexNumber.intValue) {
                case 0:
                    NSLog(@"splitViewWillResizeSubview 0 to height %f", _scopeView.bounds.size.height);
                    [_renderer mtkView:_scopeView drawableSizeWillChange:_scopeView.bounds.size];
                    break;
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
                splitSelectorPositionMemory[3] = _bpmTable.enclosingScrollView.bounds.size.width;
                break;
        }
    } else if (sv == _split) {
        switch(indexNumber.intValue) {
            case 0:
                NSLog(@"splitViewDidResizeSubview 0 to height %f", _belowVisuals.bounds.size.height);
                [self putScopeViewWithFrame:NSMakeRect(_scopeView.frame.origin.x,
                                                       _scopeView.frame.origin.y,
                                                       _scopeView.frame.size.width,
                                                       _scopeView.frame.size.height) onView:_belowVisuals];
                break;
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
            NSError* error = nil;
            [self loadDocumentFromURL:url meta:nil error:&error];
        }
    } else {
        return;
    }
}

- (BOOL)loadDocumentFromURL:(NSURL*)url meta:(MediaMetaData*)meta error:(NSError**)error
{
    NSError* asyncError = nil;
    
    // Get metadata if none were given.
    MediaMetaData* asyncMeta = meta;
    if (asyncMeta == nil) {
        NSLog(@"need to fetch some metadata...");
        asyncMeta = [MediaMetaData mediaMetaDataWithURL:url error:&asyncError];
    }

    if (_audioController == nil) {
        NSLog(@"About to init the audiocontroller...");
        _audioController = [AudioController new];
        _audioController.delegate = self;
        NSLog(@"...audiocontroller init done");
    }

    if (![url checkResourceIsReachableAndReturnError:&asyncError]) {
        NSLog(@"Failed to reach \"%@\": %@\n", url.path, asyncError);
        NSAlert* alert = [NSAlert alertWithError:asyncError];
        [alert runModal];
        return NO;
    }

    LazySample* sample = [[LazySample alloc] initWithPath:url.path error:&asyncError];
    if (sample == nil) {
        NSLog(@"Failed to load \"%@\": %@\n", url.path, asyncError);
        NSAlert* alert = [NSAlert alertWithError:asyncError];
        [alert runModal];
        return NO;
    }
    
    // We keep a reference around so that the `sample` setter will cause the possibly
    // ongoing decode of a previous sample to get aborted.
    NSLog(@"assigning sample");
    self.sample = sample;
 
    // Now gather the total amount of frames in that file as needed for decoding as well as
    // screen initializing. This may be a rather expensive operation on large files with
    // variable bitrate. We do this asynchronously to not hog the mainthread.
    [self loadTrackState:LoadStateInit value:0.0];

//    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INTERACTIVE, 0), ^{
//        NSLog(@"now NOT gathering frame count from another thread...");
//        // Once we requested this for the first time, further invocations are instant.
//        //unsigned long long frames = self.sample.frames;
//        //NSLog(@"logging frames from another thread: %lld", frames);
//
//        dispatch_async(dispatch_get_main_queue(), ^{
            [self loadTrackState:LoadStateStopped value:0.0];

            [self.playlist setCurrent:asyncMeta];

            //NSLog(@"sample: %@", self.sample);

            NSLog(@"triggering decoder...");
            [sample decodeAsync];

            self.visualSample = [[VisualSample alloc] initWithSample:sample
                                                      pixelPerSecond:100.0f
                                                           tileWidth:kDirectWaveViewTileWidth];

            self.totalVisual = [[VisualSample alloc] initWithSample:sample
                                                     pixelPerSecond:self.totalView.bounds.size.width / sample.duration
                                                          tileWidth:kTotalWaveViewTileWidth];

            self.audioController.sample = sample;
            self.waveView.frames = sample.frames;
            self.totalView.frames = sample.frames;

            self.waveView.frame = CGRectMake(0.0,
                                                   0.0,
                                                   self.visualSample.width,
                                                   self.waveView.bounds.size.height);
            [self.totalView refresh];
            
            [[NSDocumentController sharedDocumentController] noteNewRecentDocumentURL:url];
            
            [self setMeta:asyncMeta];
            
            [self.audioController playWhenReady];
//        });
//    });

    return YES;
}

- (void)setMeta:(MediaMetaData*)meta
{
    if (meta == _meta) {
        return;
    }
    _meta = meta;

    // Update meta data in the info box.
    if (_infoPanel) {
        _infoPanel.meta = meta;
    }
    
    // Update meta data in playback box.
    //_coverViewShadow.image = meta.artwork;
    _controlPanelController.coverButton.image = meta.artwork;
    //_coverButton.
    _controlPanelController.titleView.text = meta.title.length > 0 ? meta.title : @"unknown";
    _controlPanelController.albumArtistView.text = (meta.album.length > 0 && meta.artist.length > 0) ?
      [NSString stringWithFormat:@"%@ — %@", meta.artist, meta.album] :
        (meta.album.length > 0 ? meta.album : (meta.artist.length > 0 ?
                                               meta.artist : @"unknown") );

    
    //NSMutableParagraphStyle* style = [[NSParagraphStyle defaultParagraphStyle] mutableCopy];
    //style.lineBreakMode = NSLineBreakByTruncatingTail;
   
    //NSDictionary* attributes = [NSDictionary dictionaryWithObject:style forKey:NSParagraphStyleAttributeName];

    //NSString* title = @"The quick brown fox jumps over the lazy dog. The quick brown fox jumps over the lazy dog.";
    //NSMutableAttributedString *attrstr = [[NSMutableAttributedString alloc] initWithString:title attributes:attributes];
    //[[_title textStorage] appendAttributedString:attrstr];
    
    [self.window.contentView addTrackingRect:_scopeView.frame
                                       owner:self
                                    userData:nil
                                assumeInside:YES];
    
    //[_renderer play:_audioController visual:_visualSample scope:_scopeView];
    NSLog(@"Renderer unpaused\n");
}

//- (IBAction)showInfo:(id)sender
//{
//    [_infoPanel makeKeyAndOrderFront:nil];
//    [_infoPanel setLevel:NSStatusWindowLevel];
//}

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
            NSError* error = nil;
            if ([self loadDocumentFromURL:url meta:nil error:&error]) {
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
        _audioController.currentFrame = seekTo;
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
        _audioController.currentFrame = seekTo;
        if (![_audioController playing]) {
            NSLog(@"not playing, he claims...");
            [_audioController playPause];
        }
    }
//    location = [_scopeView convertPoint:locationInWindow fromView:nil];
//    if (NSPointInRect(location, _scopeView.bounds)) {
//        NSLog(@"mouse down in scope view %f:%f\n", location.x, location.y);
//        [self showControlPanel:self];
//    }
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
        _audioController.currentFrame = seekTo;
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
        _audioController.currentFrame = seekTo;
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

- (void)browseSelectedUrl:(NSURL*)url meta:(MediaMetaData*)meta
{
    [self loadDocumentFromURL:url meta:meta error:nil];
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

#pragma mark Audio delegate

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
}

- (void)audioControllerPlaybackPaused
{
    NSLog(@"audioControllerPlaybackPaused");
    // Make state obvious to user.
    [self setPlaybackActive:NO];
    [_playlist setPlaying:NO];
}

- (void)audioControllerPlaybackPlaying
{
    NSLog(@"audioControllerPlaybackPlaying");
    // Make state obvious to user.
    [self setPlaybackActive:YES];
    [_playlist setPlaying:YES];
}

- (void)audioControllerPlaybackEnded
{
    NSLog(@"audioControllerPlaybackEnded");
    // Make state obvious to user.
    [self setPlaybackActive:NO];
    [_playlist setPlaying:NO];

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

    NSError* error = nil;
    [self loadDocumentFromURL:item.location meta:item error:&error];
}

- (void)stop
{
    // Remove our hook to the vsync.
    CVDisplayLinkStop(_displayLink);
    // Stop the scope rendering.
    [_renderer stop:_scopeView];
}

#pragma mark Control Panel delegate

- (void)volumeChange:(id)sender
{
    _audioController.outputVolume = _controlPanelController.volumeSlider.doubleValue;
}

- (void)playPause:(id)sender
{
    [_audioController playPause];
}

#pragma mark Layer delegate

- (void)drawLayer:(CALayer *)layer inContext:(CGContextRef)context
{
    if (_visualSample == nil || layer.frame.origin.x < 0) {
        return;
    }

    /*
      We try to fetch visual data first;
       - when that fails, we draw a box and trigger a task preparing visual data
       - when that works, we draw it
     */
//    CGContextSetAllowsAntialiasing(context, YES);
//    CGContextSetShouldAntialias(context, YES);

    CGContextSetLineCap(context, kCGLineCapRound);
    unsigned long int start = layer.frame.origin.x;
    unsigned long int width = layer.bounds.size.width+1;

    NSData* buffer = nil;
    NSNumber* number = [layer valueForKey:@"isTotalView"];

    VisualSample* v = number != nil ? _totalVisual : _visualSample;
    buffer = [v visualsFromOrigin:start];

    if (buffer != nil) {
        CGContextSetFillColorWithColor(context, [[NSColor clearColor] CGColor]);
        CGContextFillRect(context, CGRectMake(0.0, 0.0, width, layer.bounds.size.height));

        VisualPair* data = (VisualPair*)buffer.bytes;

        CGContextSetLineWidth(context, 3.0);
        CGContextSetStrokeColorWithColor(context, [[_waveView.color colorWithAlphaComponent:0.22f] CGColor]);
        
        CGFloat mid = floor(layer.bounds.size.height / 2.0);

        for (unsigned int sampleIndex = 0; sampleIndex < width; sampleIndex++) {
            CGFloat top = (mid + ((data[sampleIndex].negativeAverage * layer.bounds.size.height) / 2.0)) - 2.0;
            CGFloat bottom = (mid + ((data[sampleIndex].positiveAverage * layer.bounds.size.height) / 2.0)) + 2.0;

            CGContextMoveToPoint(context, sampleIndex, top);
            CGContextAddLineToPoint(context, sampleIndex, bottom);
            CGContextStrokePath(context);
        }

        CGContextSetLineWidth(context, 1.5);
        CGContextSetStrokeColorWithColor(context, _waveView.color.CGColor);
        
        for (unsigned int sampleIndex = 0; sampleIndex < width; sampleIndex++) {
            CGFloat top = (mid + ((data[sampleIndex].negativeAverage * layer.bounds.size.height) / 2.0)) - 1.0;
            CGFloat bottom = (mid + ((data[sampleIndex].positiveAverage * layer.bounds.size.height) / 2.0)) + 1.0;

            CGContextMoveToPoint(context, sampleIndex, top);
            CGContextAddLineToPoint(context, sampleIndex, bottom);
            CGContextStrokePath(context);
        }
    } else {
        CGContextSetFillColorWithColor(context, _waveView.color.CGColor);
        CGContextFillRect(context, CGRectMake(0.0, 0.0, width, layer.bounds.size.height));

        if (start >= v.width) {
            return;
        }
        
        // Once data is prepared, trigger a redraw - invoking this function again.
        
        CGFloat offset = number != nil ? 0 : _waveView.enclosingScrollView.documentVisibleRect.origin.x;
        CGFloat totalWidth = number != nil ? _totalView.frame.size.width : _waveView.enclosingScrollView.documentVisibleRect.size.width;
        [v prepareVisualsFromOrigin:start width:width window:offset total:totalWidth callback:^(void){
            [layer setNeedsDisplay];
        }];
    }
}

- (void)progressSeekTo:(unsigned long long)frame
{
    _audioController.currentFrame = frame;
}

#pragma mark -
#pragma mark Full Screen Support: Persisting and Restoring Window's Non-FullScreen Frame

+ (NSArray *)restorableStateKeyPaths
{
    return [[super restorableStateKeyPaths] arrayByAddingObject:@"frameForNonFullScreenMode"];
}

@end
