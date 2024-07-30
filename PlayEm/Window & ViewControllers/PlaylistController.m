//
//  PlaylistController.m
//  PlayEm
//
//  Created by Till Toenshoff on 31.10.22.
//  Copyright © 2022 Till Toenshoff. All rights reserved.
//

#import "PlaylistController.h"
#import "../Defaults.h"

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

- (void)touchedItem:(MediaMetaData*)item
{
    [_history addObject:item];
    
    _preventSelection = YES;
    [_table beginUpdates];
    [_table insertRowsAtIndexes:[NSIndexSet indexSetWithIndex:_history.count - 1] 
                  withAnimation:NSTableViewAnimationSlideRight];
    [_table endUpdates];
    _preventSelection = NO;
    //NSUInteger low = 0;
//    NSUInteger low = _history.count < 2 ? 0 : _history.count - 2;
//    NSUInteger high = _list.count == 0 ? low : low + _list.count - 1;
    //NSUInteger high = 1;
//    [_table reloadDataForRowIndexes:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(low, high)]
//                      columnIndexes:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, 2)]];
    [_table reloadDataForRowIndexes:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, _list.count + _history.count)]
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
    NSLog(@"tableView: viewForTableColumn:%@ row:%ld", [tableColumn description], row);
    NSView* result = [tableView makeViewWithIdentifier:tableColumn.identifier owner:self];
    
    if (result == nil) {
        if ([tableColumn.identifier isEqualToString:@"CoverColumn"]) {
            NSImageView* iv = [[NSImageView alloc] initWithFrame:NSMakeRect(0.0,
                                                                            0.0,
                                                                            24.0,
                                                                            24.0)];
            result = iv;
        } else {
            NSTextField* tf = [[NSTextField alloc] initWithFrame:NSMakeRect(0.0,
                                                                            0.0,
                                                                            tableColumn.width,
                                                                            24.0)];
            tf.editable = NO;
            tf.font = [NSFont systemFontOfSize:11.0];
            tf.drawsBackground = NO;
            tf.bordered = NO;
            tf.alignment = NSTextAlignmentLeft;
            tf.textColor = [[Defaults sharedDefaults] secondaryLabelColor];
            result = tf;
        }
        result.identifier = tableColumn.identifier;
    }

    NSUInteger historyLength = _history.count;

    if ([tableColumn.identifier isEqualToString:@"CoverColumn"]) {
        if (row >= historyLength) {
            assert(_list.count > row-historyLength);
            NSImageView* iv = (NSImageView*)result;
            iv.image = [_list[row-historyLength] imageFromArtwork];
        } else {
            assert(_history.count > row);
            NSImageView* iv = (NSImageView*)result;
            iv.image = [_history[row] imageFromArtwork];
        }
    } else {
        NSTextField* tf = (NSTextField*)result;
        NSString* string = nil;
        if (row >= historyLength) {
            assert(_list.count > row-historyLength);
            string = _list[row-historyLength].title;
            tf.textColor = [[Defaults sharedDefaults] secondaryLabelColor];
        } else {
            assert(_history.count > row);
            string = _history[row].title;
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
        if (string == nil) {
            NSLog(@"done this for row %ld", row);
            string = @"";
        }
        [tf setStringValue:string];
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
