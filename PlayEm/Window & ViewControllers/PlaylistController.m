//
//  PlaylistController.m
//  PlayEm
//
//  Created by Till Toenshoff on 31.10.22.
//  Copyright © 2022 Till Toenshoff. All rights reserved.
//

#import "PlaylistController.h"
#import "../Defaults.h"
#import "../NSImage+Resize.h"

@interface PlaylistController()
@property (nonatomic, strong) NSMutableArray<MediaMetaData*>* list;
@property (nonatomic, strong) NSMutableArray<MediaMetaData*>* history;
@property (nonatomic, weak) NSTableView* table;

- (void)addNext:(MediaMetaData*)item;
- (void)addLater:(MediaMetaData*)item;

@end

@implementation PlaylistController
{
    BOOL _preventSelection;
}

- (id)initWithPlaylistTable:(NSTableView*)table 
                 delegate:(id<PlaylistControllerDelegate>)delegate
{
    self = [super init];
    if (self) {
        _delegate = delegate;
        _list = [NSMutableArray array];
        _history = [NSMutableArray array];
        _table = table;
        _table.dataSource = self;
        _table.delegate = self;
        _preventSelection = NO;
    }
    return self;
}

- (NSInteger)numberOfRowsInTableView:(NSTableView*)tableView
{
    return _history.count + _list.count;
}

- (void)addNext:(MediaMetaData*)item
{
    [_list insertObject:item atIndex:0];
    [_table beginUpdates];
    [_table insertRowsAtIndexes:[NSIndexSet indexSetWithIndex:_history.count]
                  withAnimation:NSTableViewAnimationSlideRight];
    [_table endUpdates];
}

- (void)addLater:(MediaMetaData*)item
{
    [_list addObject:item];
    [_table beginUpdates];
    [_table insertRowsAtIndexes:[NSIndexSet indexSetWithIndex:_history.count + _list.count - 1] 
                  withAnimation:NSTableViewAnimationSlideUp];
    [_table endUpdates];
}

- (void)playedMeta:(MediaMetaData*)item
{
    [_history addObject:item];
    
    _preventSelection = YES;
    [_table beginUpdates];
    [_table insertRowsAtIndexes:[NSIndexSet indexSetWithIndex:_history.count - 1] 
                  withAnimation:NSTableViewAnimationSlideRight];
    [_table endUpdates];
    _preventSelection = NO;
    [_table reloadDataForRowIndexes:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(_history.count - 1, 1)]
                      columnIndexes:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, 2)]];
}

- (MediaMetaData* _Nullable)nextItem
{
    MediaMetaData* item = [_list firstObject];
    if (item != nil) {
        [_list removeObjectAtIndex:0];
        [_table beginUpdates];
        [_table removeRowsAtIndexes:[NSIndexSet indexSetWithIndex:_history.count] 
                      withAnimation:NSTableViewAnimationSlideDown];
        [_table endUpdates];
    }
    return item;
}

- (MediaMetaData* _Nullable)itemAtIndex:(NSUInteger)index
{
    assert(index < _list.count);
    MediaMetaData* item = nil;
    for (int i=0;i <= index;i++) {
        item = [_list firstObject];
        [_history addObject:item];
    }
    [_list removeObjectsInRange:NSMakeRange(0, index)];
    return item;
}

- (void)setPlaying:(BOOL)playing
{
    if (playing == _playing) {
        return;
    }
    _playing = playing;
    
    [_table reloadDataForRowIndexes:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, _list.count + _history.count)]
                      columnIndexes:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, 2)]];
}

- (NSView*)tableView:(NSTableView*)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row
{
    const int kTitleViewTag = 1;
    const int kArtistViewTag = 2;
    
    const CGFloat kRowHeight = tableView.rowHeight;
    const CGFloat kHalfRowHeight = round(tableView.rowHeight / 2.0);
    const CGFloat kTitleFontSize = kHalfRowHeight - 4.0;
    const CGFloat kArtistFontSize = kTitleFontSize - 4.0;

    NSLog(@"tableView: viewForTableColumn:%@ row:%ld", [tableColumn description], row);
    NSView* result = [tableView makeViewWithIdentifier:tableColumn.identifier owner:self];
    
    if (result == nil) {
        if ([tableColumn.identifier isEqualToString:@"CoverColumn"]) {
            NSImageView* iv = [[NSImageView alloc] initWithFrame:NSMakeRect(0.0,
                                                                            0.0,
                                                                            kRowHeight,
                                                                            kRowHeight)];
            result = iv;
        } else {
            NSView* view = [[NSView alloc] initWithFrame:NSMakeRect(0.0,
                                                                    0.0,
                                                                    tableColumn.width,
                                                                    kRowHeight)];

            NSTextField* tf = [[NSTextField alloc] initWithFrame:NSMakeRect(0.0,
                                                                            kHalfRowHeight,
                                                                            tableColumn.width,
                                                                            kHalfRowHeight)];
            tf.editable = NO;
            tf.font = [NSFont systemFontOfSize:kTitleFontSize];
            tf.drawsBackground = NO;
            tf.bordered = NO;
            tf.alignment = NSTextAlignmentLeft;
            tf.textColor = [[Defaults sharedDefaults] secondaryLabelColor];
            tf.tag = kTitleViewTag;
            [view addSubview:tf];

            tf = [[NSTextField alloc] initWithFrame:NSMakeRect(0.0,
                                                               0.0,
                                                               tableColumn.width,
                                                               kHalfRowHeight - 2.0)];
            tf.editable = NO;
            tf.font = [NSFont systemFontOfSize:kArtistFontSize];
            tf.drawsBackground = NO;
            tf.bordered = NO;
            tf.alignment = NSTextAlignmentLeft;
            tf.textColor = [[Defaults sharedDefaults] secondaryLabelColor];
            tf.tag = kArtistViewTag;
            [view addSubview:tf];

            result = view;
        }
        result.identifier = tableColumn.identifier;
    }

    NSUInteger historyLength = _history.count;

    if ([tableColumn.identifier isEqualToString:@"CoverColumn"]) {
        if (row >= historyLength) {
            assert(_list.count > row-historyLength);
            NSImageView* iv = (NSImageView*)result;
            iv.image = [NSImage resizedImage:[_list[row-historyLength] imageFromArtwork]
                                        size:iv.frame.size];
        } else {
            assert(_history.count > row);
            NSImageView* iv = (NSImageView*)result;
            iv.image = [NSImage resizedImage:[_history[row] imageFromArtwork]
                                        size:iv.frame.size];
        }
    } else {
        NSString* title = nil;
        NSString* artist = nil;
        
        NSTextField* tf = [result viewWithTag:kTitleViewTag];
        NSTextField* af = [result viewWithTag:kArtistViewTag];

        if (row >= historyLength) {
            assert(_list.count > row-historyLength);
            title = _list[row-historyLength].title;
            artist = _list[row-historyLength].artist;
            tf.textColor = [[Defaults sharedDefaults] secondaryLabelColor];
        } else {
            assert(_history.count > row);
            title = _history[row].title;
            artist = _history[row].artist;
            NSColor* color = nil;
            if (row == historyLength-1) {
                if (_playing) {
                    color = [[Defaults sharedDefaults] lightBeamColor];
                } else {
                    color = [[Defaults sharedDefaults] secondaryLabelColor];
                }
            } else {
                color = [[Defaults sharedDefaults] tertiaryLabelColor];
            }
            tf.textColor = color;
        }
        if (title == nil) {
            title = @"";
        }
        if (artist == nil) {
            artist = @"";
        }
        [tf setStringValue:title];
        [af setStringValue:artist];
    }
    return result;
}

-(void)tableViewSelectionDidChange:(NSNotification*)notification
{
    NSTableView* tableView = [notification object];
    NSInteger row = [tableView selectedRow];
    if (row < 0) {
        return;
    }
    
    MediaMetaData* meta = nil;

    assert(row < _history.count + _list.count);
    if (row < _history.count) {
        // We selected from the history
        meta = _history[row];
        [_history removeObjectAtIndex:row];
    } else {
        NSInteger index = row - _history.count;
        // We selected from the queue.
        meta = _list[index];
        [_list removeObjectAtIndex:index];
    }
    
    _preventSelection = YES;

    [_table beginUpdates];
    [_table removeRowsAtIndexes:[NSIndexSet indexSetWithIndex:row] 
                  withAnimation:NSTableViewAnimationSlideDown];
    [_table endUpdates];

    _preventSelection = NO;

    [self.delegate browseSelectedUrl:meta.location meta:meta];
}

- (BOOL)tableView:(NSTableView*)tableView shouldSelectRow:(NSInteger)row
{
    return !_preventSelection;
}

@end
