//
//  TracklistController.m
//  PlayEm
//
//  Created by Till Toenshoff on 9/27/25.
//  Copyright © 2025 Till Toenshoff. All rights reserved.
//

#import "TracklistController.h"
#import "../Defaults.h"
#import "../NSImage+Resize.h"
#import "TrackList.h"
#import "../Audio/AudioController.h"
#import "../Sample/LazySample.h"
#import "IdentifiedTrack.h"

const CGFloat kTimeHeight = 22.0;
const CGFloat kTotalRowHeight = 52.0 + kTimeHeight;

@interface TracklistController()
@property (nonatomic, weak) NSTableView* table;

@property (strong, nonatomic) dispatch_queue_t imageQueue;

@property (assign, nonatomic) NSUInteger currentTrackIndex;
//- (void)addNext:(MediaMetaData*)item;
//- (void)addLater:(MediaMetaData*)item;

@end

@implementation TracklistController
{
//    BOOL _preventSelection;
}

- (id)initWithTracklistTable:(NSTableView*)tableView
                    delegate:(id<TracklistControllerDelegate>)delegate
{
    self = [super init];
    if (self) {
        _delegate = delegate;
        _table = tableView;
        _table.dataSource = self;
        _table.delegate = self;
        _table.doubleAction = @selector(tracklistDoubleClickedRow:);
        _table.menu = [self menu];

        const NSAutoresizingMaskOptions kViewFullySizeable = NSViewHeightSizable | NSViewWidthSizable;

        _table.backgroundColor = [NSColor clearColor];
        _table.autoresizingMask = kViewFullySizeable;
        _table.headerView = nil;
        _table.rowHeight = kTotalRowHeight;
        _table.allowsMultipleSelection = YES;
        _table.intercellSpacing = NSMakeSize(0.0, 0.0);
        
        dispatch_queue_attr_t attr = dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL, QOS_CLASS_USER_INITIATED, 0);
        _imageQueue = dispatch_queue_create("PlayEm.TracklistImageQueue", attr);

        NSTableColumn* col = [[NSTableColumn alloc] init];
        col.title = @"";
        col.identifier = @"Column";
        col.width = _table.enclosingScrollView.bounds.size.width;
        [_table addTableColumn:col];
    }
    return self;
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
    }
}

- (void)setCurrent:(MediaMetaData*)meta
{
    _current = meta;
    [_table reloadData];
}

- (NSArray<NSNumber*>*)selectedFrames
{
    __block NSMutableArray<NSNumber*>* trackFrames = [NSMutableArray array];;
    [_table.selectedRowIndexes enumerateIndexesWithOptions:NSEnumerationReverse
                                                         usingBlock:^(NSUInteger idx, BOOL *stop) {
        NSArray<NSNumber*>* frames = [_current.trackList.frames sortedArrayUsingSelector:@selector(compare:)];
        [trackFrames addObject:frames[idx]];
    }];
    return trackFrames;
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
    [_delegate reloadTracks];
    
    NSError* error = nil;
    BOOL done = [_current storeTracklistWithError:&error];
    if (!done) {
        NSLog(@"failed to write tracklist: %@", error);
    }
}

- (void)addTrack:(IdentifiedTrack*)track
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

    NSError* error = nil;
    BOOL done = [_current storeTracklistWithError:&error];
    if (!done) {
        NSLog(@"failed to write tracklist: %@", error);
    }
}

- (IBAction)exportTracklist:(id)sender
{
    NSSavePanel* save = [NSSavePanel savePanel];
    save.allowedContentTypes = @[ [UTType typeWithFilenameExtension:@"cue"] ];

    if ([save runModal] == NSModalResponseOK) {
        NSError* error = nil;
        FrameToString encoder = ^(unsigned long long frame) {
            return [_delegate standardStringFromFrame:frame];
        };
        BOOL done = [_current exportTracklistToFile:save.URL frameEncoder:encoder error:&error];
        if (!done) {
            NSLog(@"failed to write tracklist: %@", error);
        }
    }
}

//- (void)addNext:(MediaMetaData*)item
//{
//    //[_list insertObject:item atIndex:0];
//    [_table beginUpdates];
//    [_table insertRowsAtIndexes:[NSIndexSet indexSetWithIndex:[[_list tracks] count]]
//                  withAnimation:NSTableViewAnimationSlideRight];
//    [_table endUpdates];
//}
//
//- (void)addLater:(MediaMetaData*)item
//{
//    [_list addObject:item];
//    [_table beginUpdates];
//    [_table insertRowsAtIndexes:[NSIndexSet indexSetWithIndex:_history.count + _list.count - 1]
//                  withAnimation:NSTableViewAnimationSlideUp];
//    [_table endUpdates];
//}

//- (void)playedMeta:(MediaMetaData*)item
//{
//    if (_history.count && item == _history[_history.count - 1]) {
//    } else {
//        [_history addObject:item];
//        _preventSelection = YES;
//        [_table beginUpdates];
//        [_table insertRowsAtIndexes:[NSIndexSet indexSetWithIndex:_history.count - 1]
//                      withAnimation:NSTableViewAnimationSlideRight];
//        [_table endUpdates];
//        _preventSelection = NO;
//        [_table reloadDataForRowIndexes:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(_history.count - 1, 1)]
//                          columnIndexes:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, 2)]];
//    }
//}

- (NSMenu*)menu
{
    NSMenu* menu = [NSMenu new];
    
    NSMenuItem* item = [[NSMenuItem alloc] initWithTitle:@"Remove from Tracklist"
                                                  action:@selector(removeFromTracklist:)
                                           keyEquivalent:@""];
    item.target = self;
    [menu addItem:item];

    [menu addItem:[NSMenuItem separatorItem]];

    item = [menu addItemWithTitle:@"Show Info"
                           action:@selector(showInfoForSelectedSongs:)
                    keyEquivalent:@""];
    item.target = self;
    [menu addItem:[NSMenuItem separatorItem]];

    item = [menu addItemWithTitle:@"Show in Finder"
                           action:@selector(showInFinder:)
                    keyEquivalent:@""];
    item.target = self;


// TODO: allow disabling depending on the number of songs selected. Note to myself, this here is the wrong place!
//    size_t numberOfSongsSelected = ;
//    showInFinder.enabled = numberOfSongsSelected > 1;
  
    return menu;
}

- (void)updatedTracklist
{
    [_table reloadData];
}

- (NSView*)tableView:(NSTableView*)tableView viewForTableColumn:(NSTableColumn*)tableColumn row:(NSInteger)row
{
    const int kTitleViewTag = 1;
    const int kArtistViewTag = 2;
    const int kTimeViewTag = 3;
    const int kImageViewTag = 4;

    const CGFloat kRowInset = 8.0;
    const CGFloat kRowHeight = tableView.rowHeight - (kRowInset + kTimeHeight);
    const CGFloat kHalfRowHeight = round(kRowHeight / 2.0);

    NSView* result = [tableView makeViewWithIdentifier:tableColumn.identifier owner:self];
    
    if (result == nil) {
        NSView* view = [[NSView alloc] initWithFrame:NSMakeRect(0.0,
                                                                0.0,
                                                                tableColumn.width,
                                                                kRowHeight)];

        
//        NSVisualEffectView* fxView = [[NSVisualEffectView alloc] initWithFrame:NSMakeRect(0.0,
//                                                                                          kRowHeight + 2.0 + (kRowInset / 2.0),
//                                                                                          tableColumn.width,
//                                                                                          kHalfRowHeight - 8.0)];
//        fxView.autoresizingMask = NSViewHeightSizable | NSViewMinXMargin;
//        fxView.material = NSVisualEffectMaterialHUDWindow;
//        fxView.blendingMode = NSVisualEffectBlendingModeWithinWindow;
        
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
        tf.textColor = [[Defaults sharedDefaults] secondaryLabelColor];
        tf.tag = kArtistViewTag;
        [view addSubview:tf];

        result = view;
        result.identifier = tableColumn.identifier;
    }

    NSColor* titleColor = row == _currentTrackIndex ? [[Defaults sharedDefaults] lightFakeBeamColor] : [[Defaults sharedDefaults] secondaryLabelColor];;

    NSArray<NSNumber*>* frames = [_current.trackList.frames sortedArrayUsingSelector:@selector(compare:)];
    unsigned long long frame = [frames[row] unsignedLongLongValue];
    IdentifiedTrack* track = [_current.trackList trackAtFrame:frame];

    NSImageView* iv = [result viewWithTag:kImageViewTag];
    
    if (track.artwork != nil) {
        iv.image = [NSImage resizedImage:track.artwork
                                    size:iv.frame.size];
    } else {
        iv.image = [NSImage resizedImage:[NSImage imageNamed:@"UnknownSong"]
                                    size:iv.frame.size];
        if (track.imageURL != nil) {
            // We can try to resolve the artwork image from the URL.
            [self resolveImageForURL:track.imageURL callback:^(NSImage* image){
                track.artwork = image;
                iv.image = image;
            }];
        }
    }
    
    NSString* title = nil;
    NSTextField* tf = [result viewWithTag:kTitleViewTag];
    tf.textColor = titleColor;
    title = track.title;
    if (title == nil) {
        title = @"";
    }
    [tf setStringValue:title];

    NSString* artist = nil;
    tf = [result viewWithTag:kArtistViewTag];
    artist = track.artist;
    if (artist == nil) {
        artist = @"";
    }
    [tf setStringValue:artist];

    NSString* time = nil;
    tf = [result viewWithTag:kTimeViewTag];
    tf.textColor = titleColor;
    time = [_delegate stringFromFrame:frame];
    if (time == nil) {
        time = @"";
    } else {
//        time = [NSString stringWithFormat:@"start: %@", time];
    }
    [tf setStringValue:time];

    return result;
}

- (void)resolveImageForURL:(NSURL*)url callback:(void (^)(NSImage*))callback
{
    dispatch_async(_imageQueue, ^{
        NSImage* image = [[NSImage alloc] initWithContentsOfURL:url];
        dispatch_async(dispatch_get_main_queue(), ^{
            callback(image);
        });
    });
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

@end
