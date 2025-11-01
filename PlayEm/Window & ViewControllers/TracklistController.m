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

@interface TracklistController()
@property (nonatomic, weak) NSTableView* table;

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
        _table.menu = [self menu];

        const NSAutoresizingMaskOptions kViewFullySizeable = NSViewHeightSizable | NSViewWidthSizable;

        _table.backgroundColor = [NSColor clearColor];
        _table.autoresizingMask = kViewFullySizeable;
        _table.headerView = nil;
        _table.rowHeight = 68.0;
        _table.allowsMultipleSelection = YES;
        _table.intercellSpacing = NSMakeSize(0.0, 0.0);
     
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
    return _current.frames.count;
}

- (void)setCurrent:(TrackList*)list
{
    _current = list;
    [_table reloadData];
}
    
- (void)addTrack:(IdentifiedTrack*)track atFrame:(unsigned long long)frame
{
    NSLog(@"frame: %lld adding track: %@", frame, track);
    if ([_current trackAtFrame:frame] == track) {
        return;
    }
    [_current setTrack:track atFrame:frame];
    
    NSArray<NSNumber*>* frames = [[_current frames] sortedArrayUsingSelector:@selector(compare:)];
    NSUInteger index = [frames indexOfObject:@(frame)];

    assert(index != NSNotFound);

    [_table beginUpdates];
    [_table insertRowsAtIndexes:[NSIndexSet indexSetWithIndex:index]
                  withAnimation:NSTableViewAnimationSlideRight];
    [_table endUpdates];

    [_table scrollRowToVisible:index];
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

- (NSView*)tableView:(NSTableView*)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row
{
    const int kTitleViewTag = 1;
    const int kArtistViewTag = 2;
    const int kTimeViewTag = 3;
    const int kImageViewTag = 4;

    const CGFloat kRowInset = 8.0;
    const CGFloat kTimeHeight = 16.0;
    const CGFloat kRowHeight = tableView.rowHeight - (kRowInset + kTimeHeight);
    const CGFloat kHalfRowHeight = round(kRowHeight / 2.0);

    NSView* result = [tableView makeViewWithIdentifier:tableColumn.identifier owner:self];
    
    if (result == nil) {
        NSView* view = [[NSView alloc] initWithFrame:NSMakeRect(0.0,
                                                                0.0,
                                                                tableColumn.width,
                                                                kRowHeight)];

        
        NSVisualEffectView* fxView = [[NSVisualEffectView alloc] initWithFrame:NSMakeRect(0.0,
                                                                                          kRowHeight + 2.0 + (kRowInset / 2.0),
                                                                                          tableColumn.width,
                                                                                          kHalfRowHeight - 8.0)];
        fxView.autoresizingMask = NSViewHeightSizable | NSViewMinXMargin;
        fxView.material = NSVisualEffectMaterialHUDWindow;
        fxView.blendingMode = NSVisualEffectBlendingModeWithinWindow;

        NSTextField* tf = [[NSTextField alloc] initWithFrame:NSMakeRect((kRowInset / 2.0),
                                                                        2.0,
                                                                        tableColumn.width,
                                                                        kTimeHeight)];
        tf.editable = NO;
        tf.font = [[Defaults sharedDefaults] smallFont];
        tf.drawsBackground = NO;
        tf.bordered = NO;
        tf.cell.truncatesLastVisibleLine = YES;
        tf.cell.lineBreakMode = NSLineBreakByTruncatingTail;
        tf.alignment = NSTextAlignmentLeft;
        tf.textColor = [[Defaults sharedDefaults] secondaryLabelColor];
        tf.tag = kTimeViewTag;
        [fxView addSubview:tf];
        [view addSubview:fxView];
        
        NSImageView* iv = [[NSImageView alloc] initWithFrame:NSMakeRect(0.0,
                                                                        round(kRowInset / 2.0),
                                                                        kRowHeight,
                                                                        kRowHeight)];

        iv.wantsLayer = YES;
        iv.layer.contentsScale = [[NSScreen mainScreen] backingScaleFactor];
        iv.layer.cornerRadius = 3.0f;
        iv.layer.masksToBounds = YES;
        iv.tag = kImageViewTag;
        [view addSubview:iv];
        
        CGFloat x = kRowHeight + kRowInset;

        tf = [[NSTextField alloc] initWithFrame:NSMakeRect( x,
                                                            kHalfRowHeight,
                                                            tableColumn.width - x,
                                                            kHalfRowHeight)];
        tf.editable = NO;
        tf.font = [[Defaults sharedDefaults] largeFont];
        tf.drawsBackground = NO;
        tf.bordered = NO;
        tf.cell.truncatesLastVisibleLine = YES;
        tf.cell.lineBreakMode = NSLineBreakByTruncatingTail;
        tf.alignment = NSTextAlignmentLeft;
        tf.textColor = [[Defaults sharedDefaults] lightFakeBeamColor];
        tf.tag = kTitleViewTag;
        [view addSubview:tf];

        tf = [[NSTextField alloc] initWithFrame:NSMakeRect(x,
                                                           kHalfRowHeight - kTimeHeight,
                                                           tableColumn.width - x,
                                                           kHalfRowHeight - (kRowInset / 2.0))];
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

    NSArray<NSNumber*>* frames = [_current.frames sortedArrayUsingSelector:@selector(compare:)];
    unsigned long long frame = [frames[row] unsignedLongLongValue];
    IdentifiedTrack* track = [_current trackAtFrame:frame];

    NSImageView* iv = [result viewWithTag:kImageViewTag];
    iv.image = [NSImage resizedImage:track.artwork
                                size:iv.frame.size];
    
    NSString* title = nil;
    NSTextField* tf = [result viewWithTag:kTitleViewTag];
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
    time = [_delegate stringFromFrame:frame];
    if (time == nil) {
        time = @"";
    }
    [tf setStringValue:time];

    return result;
}

-(void)tableViewSelectionDidChange:(NSNotification*)notification
{
}

- (BOOL)tableView:(NSTableView*)tableView shouldSelectRow:(NSInteger)row
{
    return YES;
}

@end
