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
        _table.doubleAction = @selector(tableViewDoubleClickedRow:);
        _table.menu = [self menu];
        _preventSelection = NO;
    }
    return self;
}

- (void)writeToDefaults
{
    NSUserDefaults* userDefaults = [NSUserDefaults standardUserDefaults];
    NSMutableArray* bookmarks = [NSMutableArray array];

    for (MediaMetaData* item in _list) {
        NSError* error = nil;
        NSData* bookmark = [item.location bookmarkDataWithOptions:NSURLBookmarkCreationWithSecurityScope
                           includingResourceValuesForKeys:nil
                                            relativeToURL:nil // Make it app-scoped
                                                    error:&error];
        NSLog(@"writing URL for item: %@", item);
        if (error) {
            NSLog(@"Error creating bookmark for URL (%@): %@", item.location, error);
            continue;
        }
        [bookmarks addObject:bookmark];
    }
    [userDefaults setObject:bookmarks forKey:@"playlist"];
}

- (void)readFromDefaults
{
    NSUserDefaults* userDefaults = [NSUserDefaults standardUserDefaults];
    NSArray* bookmarks = [userDefaults objectForKey:@"playlist"];

    for (NSData* item in bookmarks) {
        NSError* error = nil;
        NSURL* url = [NSURL URLByResolvingBookmarkData:item
                                               options:NSURLBookmarkResolutionWithSecurityScope
                                         relativeToURL:nil
                                   bookmarkDataIsStale:nil
                                                 error:&error];
        if (error) {
            NSLog(@"Error reading bookmark: %@", error);
            continue;
        }
        NSLog(@"reading URL for item: %@", url);
        MediaMetaData* meta = [MediaMetaData mediaMetaDataWithURL:url error:&error];
        if (error) {
            NSLog(@"Error reading url: %@", error);
            continue;
        }
        [_list addObject:meta];
    }
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
    if (_history.count && item == _history[_history.count - 1]) {
    } else {
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
    
    [_table scrollRowToVisible:_history.count - 1];
}

- (NSArray<MediaMetaData*>*)selectedSongMetas
{
    __block NSMutableArray<MediaMetaData*>* metas = [NSMutableArray array];;
    [_table.selectedRowIndexes enumerateIndexesWithOptions:NSEnumerationReverse
                                                         usingBlock:^(NSUInteger idx, BOOL *stop) {
        MediaMetaData* meta = nil;
        if (idx < _history.count) {
            meta = _history[idx];
        } else {
            meta = _list[idx - _history.count];
        }
        [metas addObject:meta];
    }];
    return metas;
}

- (void)removeFromPlaylist:(id)sender
{
    NSArray* metasToRemove = [self selectedSongMetas];
    NSMutableArray* newList = [NSMutableArray array];
    for (MediaMetaData* item in _list) {
        if (![metasToRemove containsObject:item]) {
            [newList addObject:item];
        }
    }
    _list = newList;
    [_table reloadData];
}

- (NSMenu*)menu
{
    NSMenu* menu = [NSMenu new];
    
    NSMenuItem* item = [[NSMenuItem alloc] initWithTitle:@"Remove from Playlist"
                                                  action:@selector(removeFromPlaylist:)
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
    
    const CGFloat kRowInset = 8.0;
    const CGFloat kRowHeight = tableView.rowHeight - kRowInset;
    const CGFloat kHalfRowHeight = round(kRowHeight / 2.0);

    NSView* result = [tableView makeViewWithIdentifier:tableColumn.identifier owner:self];
    
    if (result == nil) {
        if ([tableColumn.identifier isEqualToString:@"CoverColumn"]) {
            NSView* back = [[NSView alloc] initWithFrame:NSMakeRect(0.0,
                                                                    0.0,
                                                                    tableView.rowHeight,
                                                                    tableView.rowHeight)];
            NSImageView* iv = [[NSImageView alloc] initWithFrame:NSMakeRect(0.0,
                                                                            round(kRowInset / 2.0),
                                                                            kRowHeight,
                                                                            kRowHeight)];

            iv.wantsLayer = YES;
            iv.layer.contentsScale = [[NSScreen mainScreen] backingScaleFactor];
            iv.layer.cornerRadius = 3.0f;
            iv.layer.masksToBounds = YES;

            [back addSubview:iv];
            result = back;
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
            tf.font = [[Defaults sharedDefaults] largeFont];
            tf.drawsBackground = NO;
            tf.bordered = NO;
            tf.alignment = NSTextAlignmentLeft;
            tf.textColor = [[Defaults sharedDefaults] secondaryLabelColor];
            tf.tag = kTitleViewTag;
            [view addSubview:tf];

            tf = [[NSTextField alloc] initWithFrame:NSMakeRect(0.0,
                                                               4.0,
                                                               tableColumn.width,
                                                               kHalfRowHeight - 2.0)];
            tf.editable = NO;
            tf.font = [[Defaults sharedDefaults] normalFont];
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
        NSImageView* iv = (NSImageView*)result.subviews[0];
        if (row >= historyLength) {
            //assert(_list.count > row-historyLength);
            iv.image = [NSImage resizedImage:[_list[row-historyLength] imageFromArtwork]
                                        size:iv.frame.size];
        } else {
            assert(_history.count > row);
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
                    color = [[Defaults sharedDefaults] lightFakeBeamColor];
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

- (void)tableViewDoubleClickedRow:(id)sender
{
    NSInteger row = _table.clickedRow;
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

-(void)tableViewSelectionDidChange:(NSNotification*)notification
{
}

- (BOOL)tableView:(NSTableView*)tableView shouldSelectRow:(NSInteger)row
{
    return !_preventSelection;
}

@end
