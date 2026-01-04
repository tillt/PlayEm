//
//  TracklistController.m
//  PlayEm
//
//  Created by Till Toenshoff on 9/27/25.
//  Copyright © 2025 Till Toenshoff. All rights reserved.
//

#import "TracklistController.h"

#import <CoreImage/CoreImage.h>

#import "../Defaults.h"
#import "../NSImage+Resize.h"
#import "TrackList.h"
#import "Audio/AudioController.h"
#import "Sample/LazySample.h"
#import "TimedMediaMetaData.h"
#import "MediaMetaData.h"
#import "ImageController.h"
#import "ActivityManager.h"

const CGFloat kTimeHeight = 22.0;
const CGFloat kTotalRowHeight = 52.0 + kTimeHeight;

NSString * const kTracklistControllerChangedActiveTrackNotification = @"TracklistControllerChangedActiveTrackNotification";
static const NSAutoresizingMaskOptions kViewFullySizeable = NSViewHeightSizable | NSViewWidthSizable;

@interface TracklistController()
@property (nonatomic, strong) NSTableView* table;
@property (assign, nonatomic) NSUInteger currentTrackIndex;
@property (strong, nonatomic) NSButton* detectButton;
@property (strong, nonatomic) NSTextField* detectLabel;
@property (strong, nonatomic) NSProgressIndicator* detectProgress;
@end

// FIXME: This should be a viewcontroller.
@implementation TracklistController
{
}

- (id)init
{
    self = [super init];
    if (self) {
        _currentTrackIndex = 0;
    }
    return self;
}


- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(activitiesUpdated:)
                                                 name:ActivityManagerDidUpdateNotification
                                               object:nil];
}


- (void)loadView
{
    NSLog(@"-[TrackListController loadView]");
    self.view = [[NSView alloc] initWithFrame:NSZeroRect];
    self.view.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    
    NSScrollView* sv = [[NSScrollView alloc] initWithFrame:self.view.bounds];
    sv.hasVerticalScroller = YES;
    sv.autoresizingMask = kViewFullySizeable;
    sv.drawsBackground = NO;
    
    [self.view addSubview:sv];
    
    // Tracklist
    _table = [[NSTableView alloc] initWithFrame:sv.bounds];
    _table.dataSource = self;
    _table.delegate = self;
    _table.doubleAction = @selector(tracklistDoubleClickedRow:);
    _table.menu = [self menu];
    _table.backgroundColor = [NSColor clearColor];
    _table.autoresizingMask = kViewFullySizeable;
    _table.headerView = nil;
    _table.rowHeight = kTotalRowHeight;
    _table.allowsMultipleSelection = YES;
    _table.intercellSpacing = NSMakeSize(0.0, 0.0);
    
    NSTableColumn* col = [[NSTableColumn alloc] init];
    col.title = @"";
    col.identifier = @"Column";
    col.width = _table.enclosingScrollView.bounds.size.width;
    [_table addTableColumn:col];
    
    sv.documentView = _table;
    
    _detectButton = [NSButton buttonWithTitle:@"Detect Tracklist" target:nil action:@selector(startTrackDetection:)];
    [self.view addSubview:_detectButton];
    
    _detectLabel = [NSTextField textFieldWithString:@"Tracklist Detection in Progress"];
    _detectLabel.editable = NO;
    _detectLabel.font = [[Defaults sharedDefaults] smallFont];
    _detectLabel.drawsBackground = NO;
    _detectLabel.textColor = [NSColor secondaryLabelColor];
    _detectLabel.bordered = NO;
    _detectLabel.cell.truncatesLastVisibleLine = YES;
    _detectLabel.cell.lineBreakMode = NSLineBreakByTruncatingTail;
    _detectLabel.alignment = NSTextAlignmentCenter;
    [self.view addSubview:_detectLabel];

    _detectProgress = [[NSProgressIndicator alloc] initWithFrame:NSZeroRect];
    _detectProgress.indeterminate = NO;
    _detectProgress.minValue = 0.0;
    _detectProgress.maxValue = 1.0;
    _detectProgress.style = NSProgressIndicatorStyleBar;
    _detectProgress.controlSize = NSControlSizeMini;
    _detectProgress.autoresizingMask =  NSViewWidthSizable;

    // Create color:
    CIColor *color = [[CIColor alloc] initWithColor:[NSColor whiteColor]];

    // Create filter:
    CIFilter *colorFilter = [CIFilter filterWithName:@"CIColorMonochrome"
                                 withInputParameters:@{@"inputColor": color}];

    // Assign to bar:
    _detectProgress.contentFilters = @[colorFilter];

    [self.view addSubview:_detectProgress];
}

- (void)viewDidLayout
{
    [super viewDidLayout];
    
    NSRect buttonRect = NSMakeRect(floor((self.view.bounds.size.width - _detectButton.frame.size.width) / 2.0),
                                   floor((self.view.bounds.size.height - _detectButton.frame.size.height) / 2.0),
                                   _detectButton.frame.size.width,
                                   _detectButton.frame.size.height);
    _detectButton.frame = buttonRect;
    
    NSRect labelRect = NSMakeRect(0.0, buttonRect.origin.y, self.view.bounds.size.width, buttonRect.size.height);
    _detectLabel.frame = labelRect;
    
    CGFloat padding = 50.0;
    NSRect progressRect = NSMakeRect(labelRect.origin.x + padding,
                                     labelRect.origin.y - (_detectProgress.frame.size.height - 4.0),
                                     labelRect.size.width - (2 * padding),
                                     _detectProgress.frame.size.height);
    _detectProgress.frame = progressRect;
}

- (void)viewWillAppear
{
    [super viewWillAppear];

    [self reflectState];
}

- (void)reflectState
{
    BOOL idle = _detectionToken == nil;
    BOOL lackingTracks = _current.trackList.tracks.count == 0;
    _detectButton.hidden = !(lackingTracks & idle);
    _detectLabel.hidden = idle;
    _detectProgress.hidden = idle;
}

- (void)setDetectionToken:(ActivityToken *)detectionToken
{
    _detectProgress.doubleValue = 0.0;
    _detectionToken = detectionToken;
    [self reflectState];
}

- (NSInteger)numberOfRowsInTableView:(NSTableView*)tableView
{
    return _current.trackList.frames.count;
}

- (void)setCurrentFrame:(unsigned long long)frame
{
    static size_t cache = UINT_MAX;

    TrackListIterator* iter = nil;
    size_t lastIndex = UINT_MAX;

    unsigned long long nextTrackFrame = [_current.trackList firstTrackFrame:&iter];
    //unsigned long long lastTrackFrame = 0LL;

    while (nextTrackFrame != ULONG_LONG_MAX) {
        if (frame < nextTrackFrame) {
            break;
        }
        lastIndex = iter.index - 1;
        nextTrackFrame = [_current.trackList nextTrackFrame:iter];
    };
    
    if (cache != lastIndex) {
        cache = lastIndex;
        _currentTrackIndex = lastIndex;
        NSLog(@"active track: %ld", _currentTrackIndex );
        [_table reloadData];
        [_table scrollRowToVisible:_currentTrackIndex];
        
        [[NSNotificationCenter defaultCenter] postNotificationName:kTracklistControllerChangedActiveTrackNotification
                                                            object:[self currentTrack]];
    }
}

- (TimedMediaMetaData* _Nullable)currentTrack
{
    if (_currentTrackIndex == UINT_MAX) {
        return nil;
    }
    NSArray<NSNumber*>* frames = [_current.trackList.frames sortedArrayUsingSelector:@selector(compare:)];
    assert(_currentTrackIndex < frames.count);
    unsigned long long frame = [frames[_currentTrackIndex] unsignedLongLongValue];
    return [_current.trackList trackAtFrame:frame];
}

- (void)setCurrent:(MediaMetaData*)meta
{
    _current = meta;
    [_table reloadData];
}

- (NSArray<NSNumber*>*)selectedFrames
{
    NSArray<NSNumber*>* frames = [_current.trackList.frames sortedArrayUsingSelector:@selector(compare:)];
    __block NSMutableArray<NSNumber*>* trackFrames = [NSMutableArray array];;
    [_table.selectedRowIndexes enumerateIndexesWithOptions:NSEnumerationReverse
                                                         usingBlock:^(NSUInteger idx, BOOL *stop) {
        [trackFrames addObject:frames[idx]];
    }];

    if (trackFrames.count == 0 && self.table.clickedRow >= 0) {
        [trackFrames addObject:frames[self.table.clickedRow]];
    }
    return trackFrames;
}

- (void)clearTracklist
{
    [_current.trackList clear];
    [_table reloadData];
    [_delegate updatedTracks];
}

- (void)removeFromTracklist:(id)sender
{
    NSArray* framesToRemove = [self selectedFrames];
    for (NSNumber* number in framesToRemove) {
        unsigned long long frame = [number unsignedLongLongValue];
        [_current.trackList removeTrackAtFrame:frame];
    }
    // TODO: Add logic to spare us a reload.
    [_table reloadData];
    [_delegate updatedTracks];
    
    _current.frameToSeconds = ^(unsigned long long frame) {
        return [self->_delegate secondsFromFrame:frame];
    };
    
    NSError* error = nil;
    BOOL done = [_current storeTracklistWithError:&error];
    if (!done) {
        NSLog(@"failed to write tracklist: %@", error);
    }
    _detectButton.hidden =  _current.trackList.tracks.count > 0;
}

- (void)musicURLClickedWithTrack:(id)sender
{
    NSMenuItem* item = sender;
    TimedMediaMetaData* track = item.representedObject;
    NSURL* musicURL = track.meta.appleLocation;
    if (musicURL == nil) {
        NSLog(@"no URL to show");
        return;
    }
    // For making sure this wont open Music.app we fetch the
    // default app for URLs.
    // With that we explicitly call the browser for opening the
    // URL. That way we get things displayed even in cases where
    // Music.app does not show iCloud.Music.
    NSURL* appURL = [[NSWorkspace sharedWorkspace] URLForApplicationToOpenURL:musicURL];
    NSWorkspaceOpenConfiguration* configuration = [NSWorkspaceOpenConfiguration new];
    [[NSWorkspace sharedWorkspace] openURLs:[NSArray arrayWithObject:musicURL]
                       withApplicationAtURL:appURL
                              configuration:configuration
                          completionHandler:^(NSRunningApplication* app, NSError* error){
    }];
}

- (void)musicURLClicked:(id)sender
{
    NSArray* framesToRemove = [self selectedFrames];
    assert(framesToRemove.count > 0);
    TimedMediaMetaData* track = [_current.trackList trackAtFrameNumber:framesToRemove[0]];
    
    NSURL* musicURL = track.meta.appleLocation;
    if (musicURL == nil) {
        NSLog(@"no URL to show");
        return;
    }
    // For making sure this wont open Music.app we fetch the
    // default app for URLs.
    // With that we explicitly call the browser for opening the
    // URL. That way we get things displayed even in cases where
    // Music.app does not show iCloud.Music.
    NSURL* appURL = [[NSWorkspace sharedWorkspace] URLForApplicationToOpenURL:musicURL];
    NSWorkspaceOpenConfiguration* configuration = [NSWorkspaceOpenConfiguration new];
    [[NSWorkspace sharedWorkspace] openURLs:[NSArray arrayWithObject:musicURL]
                       withApplicationAtURL:appURL
                              configuration:configuration
                          completionHandler:^(NSRunningApplication* app, NSError* error){
    }];
}

- (void)moveTrackAtFrame:(unsigned long long)oldFrame frame:(unsigned long long)newFrame
{
    TimedMediaMetaData* track = [_current.trackList trackAtFrame:oldFrame];
    assert(track);
    NSArray<NSNumber*>* frames = [[_current.trackList frames] sortedArrayUsingSelector:@selector(compare:)];
    NSUInteger index = [frames indexOfObject:[NSNumber numberWithLongLong:oldFrame]];

    assert(index != NSNotFound);
    // Remove track.
    [_current.trackList removeTrackAtFrame:oldFrame];
    // Patch track.
    track.frame = [NSNumber numberWithLongLong:newFrame];
    [_current.trackList addTrack:track];

    [_table beginUpdates];
    [_table reloadDataForRowIndexes:[NSIndexSet indexSetWithIndex:index]
                      columnIndexes:[NSIndexSet indexSetWithIndex:0]];
    [_table endUpdates];

    [_table scrollRowToVisible:index];

    _current.frameToSeconds = ^(unsigned long long frame) {
        return [self->_delegate secondsFromFrame:frame];
    };
    
    NSError* error = nil;
    BOOL done = [_current storeTracklistWithError:&error];
    if (!done) {
        NSLog(@"failed to write tracklist: %@", error);
    }
}

- (void)addTracks:(NSArray<TimedMediaMetaData*>*)tracks
{
    //NSLog(@"adding tracks: %@", tracks);
    for (TimedMediaMetaData* track in tracks) {
        [_current.trackList addTrack:track];
    }
   
    [_table reloadData];
    
    _current.frameToSeconds = ^(unsigned long long frame) {
        return [self->_delegate secondsFromFrame:frame];
    };

    NSError* error = nil;
    BOOL done = [_current storeTracklistWithError:&error];
    if (!done) {
        NSLog(@"failed to write tracklist: %@", error);
    }
    _detectButton.hidden =  _current.trackList.tracks.count > 0;

}

- (void)addTrack:(TimedMediaMetaData*)track
{
    NSLog(@"adding track: %@", track);
    if ([_current.trackList trackAtFrame:[track.frame unsignedLongLongValue]] == track) {
        return;
    }
    [_current.trackList addTrack:track];
    
    NSArray<NSNumber*>* frames = [[_current.trackList frames] sortedArrayUsingSelector:@selector(compare:)];
    NSUInteger index = [frames indexOfObject:track.frame];

    assert(index != NSNotFound);

    [_table beginUpdates];
    [_table insertRowsAtIndexes:[NSIndexSet indexSetWithIndex:index]
                  withAnimation:NSTableViewAnimationSlideRight];
    [_table endUpdates];

    [_table scrollRowToVisible:index];
    
    _current.frameToSeconds = ^(unsigned long long frame) {
        return [self->_delegate secondsFromFrame:frame];
    };

    NSError* error = nil;
    BOOL done = [_current storeTracklistWithError:&error];
    if (!done) {
        NSLog(@"failed to write tracklist: %@", error);
    }
    _detectButton.hidden =  _current.trackList.tracks.count > 0;
}

- (IBAction)exportTracklist:(id)sender
{
    NSSavePanel* save = [NSSavePanel savePanel];
    save.allowedContentTypes = @[ [UTType typeWithFilenameExtension:@"cue"] ];

    if ([save runModal] == NSModalResponseOK) {
        NSError* error = nil;
        FrameToString encoder = ^(unsigned long long frame) {
            return [self->_delegate standardStringFromFrame:frame];
        };
        BOOL done = [_current exportTracklistToFile:save.URL frameEncoder:encoder error:&error];
        if (!done) {
            NSLog(@"failed to write tracklist: %@", error);
        }
    }
}

- (IBAction)copyTracklist:(id)sender
{
    FrameToString encoder = ^(unsigned long long frame) {
        return [self->_delegate stringFromFrame:frame];
    };
    NSString* tracklist = [_current readableTracklistWithFrameEncoder:encoder];
    [[NSPasteboard generalPasteboard] clearContents];
    [[NSPasteboard generalPasteboard] setString:tracklist forType:NSPasteboardTypeString];
}

- (NSMenu*)menu
{
    NSMenu* menu = [NSMenu new];
    
    NSMenuItem* item = [menu addItemWithTitle:@"Remove from Tracklist"
                                       action:@selector(removeFromTracklist:)
                                keyEquivalent:@""];

    [menu addItem:[NSMenuItem separatorItem]];

    item = [menu addItemWithTitle:@"Open in Apple Music"
                           action:@selector(musicURLClicked:)
                    keyEquivalent:@""];

    [menu addItem:[NSMenuItem separatorItem]];

    item = [[NSMenuItem alloc] initWithTitle:@"Export Tracklist..."
                                      action:@selector(exportTracklist:)
                               keyEquivalent:@""];
    [item setKeyEquivalentModifierMask:NSEventModifierFlagCommand];
    item.target = self;
    [menu addItem:item];

    [menu addItem:[NSMenuItem separatorItem]];

    item = [[NSMenuItem alloc] initWithTitle:@"Copy Tracklist to Clipboard"
                                      action:@selector(copyTracklist:)
                               keyEquivalent:@""];
    [item setKeyEquivalentModifierMask:NSEventModifierFlagCommand];
    item.target = self;
    [menu addItem:item];

    //[menu addItem:item];

//
//    item = [menu addItemWithTitle:@"Show in Finder"
//                           action:@selector(showInFinder:)
//                    keyEquivalent:@""];
//    item.target = self;
//

// TODO: allow disabling depending on the number of songs selected. Note to myself, this here is the wrong place!
//    size_t numberOfSongsSelected = ;
//    showInFinder.enabled = numberOfSongsSelected > 1;
  
    return menu;
}

//- (NSArray<MediaMetaData*>*)selectedSongMetas
//{
//    __block NSMutableArray<MediaMetaData*>* metas = [NSMutableArray array];;
//    [self.songsTable.selectedRowIndexes enumerateIndexesWithOptions:NSEnumerationReverse
//                                                         usingBlock:^(NSUInteger idx, BOOL *stop) {
//        MediaMetaData* meta = self.filteredItems[idx];
//        [metas addObject:meta];
//    }];
//    return metas;
//}
//
//- (void)showInfoForSelectedSongs:(id)sender
//{
//    NSMutableArray* metas = [NSMutableArray array];
//    if (_table.clickedRow >= 0) {
//        [metas addObject:self.filteredItems[_table.clickedRow]];
//        NSLog(@"item: %@", self.filteredItems[_table.clickedRow]);
//    } else {
//        [metas addObjectsFromArray:[self selectedSongMetas]];
//    }
//    [self.delegate showInfoForMetas:metas];
//}

- (void)updatedTracklist
{
    [_table reloadData];
}

- (nullable NSView*)tableView:(NSTableView*)tableView viewForTableColumn:(nullable NSTableColumn*)tableColumn row:(NSInteger)row
{
    const int kTitleViewTag = 1;
    const int kArtistViewTag = 2;
    const int kTimeViewTag = 3;
    const int kImageViewTag = 4;

    const CGFloat kRowInset = 8.0;
    const CGFloat kRowHeight = tableView.rowHeight - (kRowInset + kTimeHeight);

    NSView* result = [tableView makeViewWithIdentifier:tableColumn.identifier owner:self];
    
    if (result == nil) {
        NSView* view = [[NSView alloc] initWithFrame:NSMakeRect(0.0,
                                                                0.0,
                                                                tableColumn.width,
                                                                kRowHeight)];
        const CGFloat kArtistHeight = 16.0;
        const CGFloat kTitleHeight = 22.0;

        // Time
        NSTextField* tf = [[NSTextField alloc] initWithFrame:NSMakeRect(0,
                                                                        tableView.rowHeight  - (kRowInset + kTimeHeight - 4.0),
                                                                        tableColumn.width,
                                                                        kTimeHeight)];
        tf.editable = NO;
        tf.font = kTimeHeight > 16.0 ? [[Defaults sharedDefaults] normalFont] : [[Defaults sharedDefaults] smallFont];
        tf.drawsBackground = NO;
        tf.bordered = NO;
        tf.cell.truncatesLastVisibleLine = YES;
        tf.cell.lineBreakMode = NSLineBreakByTruncatingTail;
        tf.alignment = NSTextAlignmentLeft;
        tf.tag = kTimeViewTag;
        //[fxView addSubview:tf];
        [view addSubview:tf];

        // Cover
        CGFloat coverWidth = kRowHeight;
        NSImageView* iv = [[NSImageView alloc] initWithFrame:NSMakeRect(0.0,
                                                                        8.0,
                                                                        coverWidth,
                                                                        kRowHeight)];

        iv.wantsLayer = YES;
        iv.layer.contentsScale = [[NSScreen mainScreen] backingScaleFactor];
        iv.layer.cornerRadius = 3.0f;
        iv.layer.masksToBounds = YES;
        iv.tag = kImageViewTag;
        [view addSubview:iv];
        
        CGFloat x = coverWidth + kRowInset;
        CGFloat labelWidth = tableColumn.width - (x + (4 * kRowInset));
        
        // Title
        tf = [[NSTextField alloc] initWithFrame:NSMakeRect( x,
                                                            (tableView.rowHeight - (kTimeHeight + kTitleHeight + kRowInset - 4.0)),
                                                            labelWidth,
                                                            kTitleHeight)];
        tf.editable = NO;
        tf.font = [[Defaults sharedDefaults] largeFont];
        tf.drawsBackground = NO;
        tf.bordered = NO;
        tf.cell.truncatesLastVisibleLine = YES;
        tf.cell.lineBreakMode = NSLineBreakByTruncatingTail;
        tf.alignment = NSTextAlignmentLeft;
        tf.tag = kTitleViewTag;
        [view addSubview:tf];

        // Artist
        tf = [[NSTextField alloc] initWithFrame:NSMakeRect(x,
                                                           (tableView.rowHeight - (kTimeHeight + kTitleHeight + kRowInset + kArtistHeight - 6.0)),
                                                           labelWidth,
                                                           kArtistHeight)];
        tf.editable = NO;
        tf.font = [[Defaults sharedDefaults] normalFont];
        tf.drawsBackground = NO;
        tf.cell.truncatesLastVisibleLine = YES;
        tf.cell.lineBreakMode = NSLineBreakByTruncatingTail;
        tf.bordered = NO;
        tf.alignment = NSTextAlignmentLeft;
        tf.tag = kArtistViewTag;
        [view addSubview:tf];

        result = view;
        result.identifier = tableColumn.identifier;
    }

    NSColor* titleColor = row == _currentTrackIndex ? [[Defaults sharedDefaults] lightFakeBeamColor] : [[Defaults sharedDefaults] secondaryLabelColor];;
    NSColor* artistColor = row == _currentTrackIndex ? [[Defaults sharedDefaults] regularFakeBeamColor] : [[Defaults sharedDefaults] secondaryLabelColor];
 
    NSArray<NSNumber*>* frames = [_current.trackList.frames sortedArrayUsingSelector:@selector(compare:)];
    unsigned long long frame = [frames[row] unsignedLongLongValue];
    TimedMediaMetaData* track = [_current.trackList trackAtFrame:frame];

    NSImageView* iv = [result viewWithTag:kImageViewTag];
    
    // Placeholder initially - we may need to resolve the data (unlikely for a tracklist,
    // very likely for a playlist).
    iv.image = [NSImage resizedImageWithData:[MediaMetaData defaultArtworkData]
                                        size:iv.frame.size];

    __weak NSView *weakView = result;
    __weak NSTableView *weakTable = tableView;
    
    void (^applyImage)(NSData*) = ^(NSData*data) {
        [[ImageController shared] imageForData:data
                                           key:track.meta.artworkHash
                                          size:iv.frame.size.width
                                    completion:^(NSImage *image) {
            if (image == nil || weakView == nil || weakTable == nil) {
                return;
            }
            if ([weakTable rowForView:weakView] == row) {
                NSImageView *iv = [weakView viewWithTag:kImageViewTag];
                iv.image = image;
            }
        }];
    };

    if (track.meta.artwork != nil) {
        applyImage(track.meta.artwork);
    } else {
        if (track.meta.artworkLocation != nil) {
            assert(NO);
            [[ImageController shared] resolveDataForURL:track.meta.artworkLocation callback:^(NSData* data){
                track.meta.artwork = data;
                applyImage(track.meta.artwork);
            }];
        }
    }
    
    NSTextField* tf = [result viewWithTag:kTitleViewTag];
    tf.textColor = titleColor;
    NSString* title = track.meta.title;
    if (title == nil) {
        title = @"";
    }
    [tf setStringValue:title];

    tf = [result viewWithTag:kArtistViewTag];
    tf.textColor = artistColor;
    NSString* artist = track.meta.artist;
    if (artist == nil) {
        artist = @"";
    }
    [tf setStringValue:artist];

    tf = [result viewWithTag:kTimeViewTag];
    tf.textColor = titleColor;
    NSString* time = [_delegate stringFromFrame:frame];
    if (time == nil) {
        time = @"";
    }

    NSString* confidence = nil;
    if (track.confidence == nil) {
        confidence = @"unknown";
    } else {
        NSNumberFormatter *decimalStyleFormatter = [[NSNumberFormatter alloc] init];
        [decimalStyleFormatter setMaximumFractionDigits:2];
        confidence = [decimalStyleFormatter stringFromNumber:track.confidence];
    }
    
    NSString* output = [NSString stringWithFormat:@"%@, confidence %@", time, confidence];
    [tf setStringValue:output];

    return result;
}

-(void)tableViewSelectionDidChange:(NSNotification*)notification
{
}

- (void)tracklistDoubleClickedRow:(id)sender
{
    NSInteger row = _table.clickedRow;
    if (row < 0) {
        return;
    }
    NSArray<NSNumber*>* frames = [_current.trackList.frames sortedArrayUsingSelector:@selector(compare:)];
    unsigned long long frame = [frames[row] unsignedLongLongValue];
    NSLog(@"asking our delegate to play the active song at frame %lld", frame);
    [self.delegate playAtFrame:frame];
}

- (BOOL)tableView:(NSTableView*)tableView shouldSelectRow:(NSInteger)row
{
    return YES;
}


#pragma mark - Notifications

- (void)activitiesUpdated:(NSNotification*)note
{
    // Should we care?
    if(_detectionToken == nil) {
        return;
    }
    
    // Did our token expire?
    if (![[ActivityManager shared] isActive:_detectionToken]) {
        self.detectionToken = nil;
        return;
    }
    
    ActivityEntry* entry = [[ActivityManager shared] activityWithToken:_detectionToken];
    _detectProgress.doubleValue = entry.progress;
    [_detectProgress setNeedsDisplay:YES];
}

@end
