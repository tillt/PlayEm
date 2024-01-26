//
//  BrowserController.m
//  PlayEm
//
//  Created by Till Toenshoff on 13.09.20.
//  Copyright © 2020 Till Toenshoff. All rights reserved.
//

#import "BrowserController.h"

#import <iTunesLibrary/ITLibrary.h>
#import <iTunesLibrary/ITLibMediaItem.h>
#import <iTunesLibrary/ITLibArtist.h>
#import <iTunesLibrary/ITLibAlbum.h>
#import <iTunesLibrary/ITLibArtwork.h>

#import "MediaMetaData.h"
#import "TableHeaderCell.h"

#import "NSString+BeautifulPast.h"
#import "ITLibMediaItem+TTAdditionsh.h"

@interface BrowserController ()
@property (nonatomic, strong) ITLibrary* library;
@property (nonatomic, strong) NSArray<MediaMetaData*>* cachedLibrary;

@property (nonatomic, weak) NSTableView* genresTable;
@property (nonatomic, weak) NSTableView* artistsTable;
@property (nonatomic, weak) NSTableView* albumsTable;
@property (nonatomic, weak) NSTableView* temposTable;
@property (nonatomic, weak) NSTableView* keysTable;
@property (nonatomic, weak) NSTableView* songsTable;
@property (nonatomic, strong) NSMutableArray<NSString*>* genres;
@property (nonatomic, strong) NSMutableArray<NSString*>* artists;
@property (nonatomic, strong) NSMutableArray<NSString*>* albums;
@property (nonatomic, strong) NSMutableArray<NSString*>* tempos;
@property (nonatomic, strong) NSMutableArray<NSString*>* keys;
@property (nonatomic, strong) NSArray<MediaMetaData*>* filteredItems;
@end



@implementation BrowserController
{
    bool _updatingGenres;
    bool _updatingArtists;
    bool _updatingAlbums;
    bool _updatingTempos;
    bool _updatingKeys;
}

- (id)initWithGenresTable:(NSTableView*)genresTable
             artistsTable:(NSTableView*)artistsTable
              albumsTable:(NSTableView*)albumsTable
              temposTable:(NSTableView*)temposTable
               songsTable:(NSTableView*)songsTable
                 delegate:(id<BrowserControllerDelegate>)delegate
{
    self = [super init];
    if (self) {
        _delegate = delegate;

        _updatingGenres = NO;
        _updatingArtists = NO;
        _updatingAlbums = NO;
        _updatingTempos = NO;
        _updatingKeys = NO;

        _genres = [NSMutableArray array];
        _artists = [NSMutableArray array];
        _albums = [NSMutableArray array];
        _tempos = [NSMutableArray array];
        _keys = [NSMutableArray array];

        _genresTable = genresTable;
        _genresTable.dataSource = self;
        _genresTable.delegate = self;

        _artistsTable = artistsTable;
        _artistsTable.dataSource = self;
        _artistsTable.delegate = self;

        _albumsTable = albumsTable;
        _albumsTable.dataSource = self;
        _albumsTable.delegate = self;

        _temposTable = temposTable;
        _temposTable.dataSource = self;
        _temposTable.delegate = self;

        _songsTable = songsTable;
        _songsTable.dataSource = self;
        _songsTable.delegate = self;

        [self loadITunesLibrary];
    }
    return self;
}

- (void)loadITunesLibrary
{
    NSError *error = nil;
    NSIndexSet* zeroSet = [NSIndexSet indexSetWithIndex:0];

    [_delegate loadLibraryState:LoadStateInit value:0.0];

    _library = [ITLibrary libraryWithAPIVersion:@"1.0" options:ITLibInitOptionLazyLoadData error:&error];
    if (!_library) {
        NSLog(@"Failed accessing iTunes Library: %@", error);
        return;
    }

    NSLog(@"Media folder location: %@", _library.mediaFolderLocation.path);

    _filteredItems = nil;
    _cachedLibrary = nil;
    
    _genres = [NSMutableArray array];
    _artists = [NSMutableArray array];
    _albums = [NSMutableArray array];

    [_genresTable beginUpdates];
    [_genresTable selectRowIndexes:zeroSet byExtendingSelection:NO];
    [_genresTable reloadData];
    [_genresTable endUpdates];

    [_artistsTable beginUpdates];
    [_artistsTable selectRowIndexes:zeroSet byExtendingSelection:NO];
    [_artistsTable reloadData];
    [_artistsTable endUpdates];

    [_albumsTable beginUpdates];
    [_albumsTable selectRowIndexes:zeroSet byExtendingSelection:NO];
    [_albumsTable reloadData];
    [_albumsTable endUpdates];

    [_temposTable beginUpdates];
    [_temposTable selectRowIndexes:zeroSet byExtendingSelection:NO];
    [_temposTable reloadData];
    [_temposTable endUpdates];

    [_keysTable beginUpdates];
    [_keysTable selectRowIndexes:zeroSet byExtendingSelection:NO];
    [_keysTable reloadData];
    [_keysTable endUpdates];

    [_songsTable beginUpdates];
    [_songsTable selectRowIndexes:zeroSet byExtendingSelection:NO];
    [_songsTable reloadData];
    [_songsTable endUpdates];

    //[self registerAsObserverForLibrary:_library];
    
    BrowserController* __weak weakSelf = self;
    
    NSArray<NSSortDescriptor*>* descriptors = [_songsTable sortDescriptors];

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
        //[_delegate loadLibraryState:LoadStateStarted value:0.0];

        NSMutableArray<MediaMetaData*>* cachedLibrary = [NSMutableArray new];
        for (ITLibMediaItem* d in weakSelf.library.allMediaItems) {
            if (d.cloud) {
                continue;
            }
            MediaMetaData* m = [MediaMetaData mediaMetaDataWithITLibMediaItem:d error:nil];
            [cachedLibrary addObject:m];
        }
       
        // Apply sorting.
        weakSelf.filteredItems = [cachedLibrary sortedArrayUsingDescriptors:descriptors];
        weakSelf.cachedLibrary = cachedLibrary;

        [weakSelf columnsFromMediaItems:weakSelf.filteredItems
                                 genres:weakSelf.genres
                                artists:weakSelf.artists
                                 albums:weakSelf.albums
                                 tempos:weakSelf.tempos
                                   keys:weakSelf.keys];

        dispatch_async(dispatch_get_main_queue(), ^{
            //[_delegate loadLibraryState:LoadStateStopped value:0.0];

            [weakSelf.genresTable beginUpdates];
            [weakSelf.genresTable reloadData];
            [weakSelf.genresTable endUpdates];

            [weakSelf.delegate updateSongsCount:weakSelf.filteredItems.count];

            self->_updatingGenres = NO;
            self->_updatingArtists = NO;
            self->_updatingAlbums = NO;
            self->_updatingTempos = NO;
            self->_updatingKeys = NO;
            [weakSelf.genresTable selectRowIndexes:[NSIndexSet indexSetWithIndex:0]
                              byExtendingSelection:NO];

            [weakSelf.albumsTable beginUpdates];
            [weakSelf.albumsTable reloadData];
            [weakSelf.albumsTable endUpdates];

            [weakSelf.artistsTable beginUpdates];
            [weakSelf.artistsTable reloadData];
            [weakSelf.artistsTable endUpdates];

            [weakSelf.temposTable beginUpdates];
            [weakSelf.temposTable reloadData];
            [weakSelf.temposTable endUpdates];
            
            [weakSelf.songsTable beginUpdates];
            [weakSelf.songsTable reloadData];
            [weakSelf.songsTable endUpdates];

            [weakSelf.keysTable beginUpdates];
            [weakSelf.keysTable reloadData];
            [weakSelf.keysTable endUpdates];
        });
    });
}

- (IBAction)playNext:(id)sender
{
    NSInteger row = self.songsTable.clickedRow;
    if (row < 0) {
        // This is in the albums table maybe.
        row = self.albumsTable.clickedRow;
        if (row < 0) {
            return;
        }
        // FIXME: Do something or kill this code!
        // meh - seems non trivial to add a album "play next" properly.
    } else {
        assert(self.songsTable.clickedRow < self.filteredItems.count);
        NSLog(@"item: %@", self.filteredItems[self.songsTable.clickedRow]);
        MediaMetaData* meta = self.filteredItems[self.songsTable.clickedRow];
        [_delegate addToPlaylistNext:meta];
    }
}

- (IBAction)playLater:(id)sender
{
    if (self.songsTable.clickedRow < 0) {
        return;
    }
    assert(self.songsTable.clickedRow < self.filteredItems.count);
    NSLog(@"item: %@", self.filteredItems[self.songsTable.clickedRow]);
    MediaMetaData* meta = self.filteredItems[self.songsTable.clickedRow];
    [_delegate addToPlaylistLater:meta];
}

- (IBAction)showInFinder:(id)sender
{
    if (self.songsTable.clickedRow < 0) {
        return;
    }
    assert(self.songsTable.clickedRow < self.filteredItems.count);
    NSLog(@"item: %@", self.filteredItems[self.songsTable.clickedRow]);
    MediaMetaData* meta = self.filteredItems[self.songsTable.clickedRow];
    NSArray<NSURL*>* fileURLs = [NSArray arrayWithObjects:meta.location, nil];
    [[NSWorkspace sharedWorkspace] activateFileViewerSelectingURLs:fileURLs];
}

/*
static void* LibraryContext = &LibraryContext;

- (void)registerAsObserverForLibrary:(ITLibrary*)library
{
    [library addObserver:self
              forKeyPath:@"allMediaItems"
                 options:(NSKeyValueObservingOptionNew |
                          NSKeyValueObservingOptionOld)
                 context:LibraryContext];
}

- (void)observeValueForKeyPath:(NSString*)keyPath
                      ofObject:(id)object
                        change:(NSDictionary*)change
                       context:(void*)context
{
    if (context == LibraryContext) {
        // Do something
        NSLog(@"we got a changed library!!!!\n");
    } else {
        // Any unrecognized context must belong to super
        [super observeValueForKeyPath:keyPath
                             ofObject:object
                               change:change
                               context:context];
    }
}
 */

- (NSArray*)filterMediaItems:(NSArray<MediaMetaData*>*)items
                       genre:(NSString*)genre
                      artist:(NSString*)artist
                       album:(NSString*)album
                       tempo:(NSString*)tempo
                         key:(NSString*)key
{
    NSLog(@"filtered based on genre:%@ artist:%@ album:%@ tempo:%@ key:%@", genre, artist, album, tempo, key);
    NSMutableArray* filtered = [NSMutableArray array];

    for (MediaMetaData *d in items) {
        if ((genre == nil || (d.genre && d.genre.length && [d.genre isEqualTo:genre])) &&
            (artist == nil || (d.artist && d.artist.length && [d.artist isEqualTo:artist])) &&
            (album == nil || (d.album && d.album.length && [d.album isEqualTo:album])) &&
            (tempo == nil || (d.tempo > 0 && [tempo isEqual:[NSString stringWithFormat:@"%d", (unsigned int)d.tempo]]))) {
            [filtered addObject:d];
        }
    }

    NSLog(@"filtered narrowed from %ld to %ld entries", items.count, filtered.count);

    NSUInteger count = filtered.count;
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.delegate updateSongsCount:count];
    });
    
    return filtered;
}

// Get column lists for the items in the given list.
- (void)columnsFromMediaItems:(NSArray*)items
                       genres:(NSMutableArray*)genres
                      artists:(NSMutableArray*)artists
                       albums:(NSMutableArray*)albums
                       tempos:(NSMutableArray*)tempos
                       keys:(NSMutableArray*)keys
{
    NSMutableDictionary* filteredGenres = [NSMutableDictionary dictionary];
    NSMutableDictionary* filteredArtists = [NSMutableDictionary dictionary];
    NSMutableDictionary* filteredAlbums = [NSMutableDictionary dictionary];
    NSMutableDictionary* filteredTempos = [NSMutableDictionary dictionary];
    NSMutableDictionary* filteredKeys = [NSMutableDictionary dictionary];

    dispatch_async(dispatch_get_main_queue(), ^{
        [self.delegate loadLibraryState:LoadStateStarted];
    });

    size_t itemCount = items.count;
    size_t itemIndex = 0;
    for (MediaMetaData* d in items) {
        if (d.genre && d.genre.length) {
            filteredGenres[d.genre] = d.genre;
        }
        if (d.artist && d.artist.length) {
            filteredArtists[d.artist] = d.artist;
        }
        if (d.album && d.album.length) {
            filteredAlbums[d.album] = d.album;
        }
        if (d.tempo > 0) {
            NSString* t = [NSString stringWithFormat:@"%ld", d.tempo];
            filteredTempos[t] = t;
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.delegate loadLibraryState:LoadStateLoading value:(double)(itemIndex + 1) / (double)itemCount];
        });
        itemIndex++;
    }
    
    if (genres != nil) {
        NSArray* array = [filteredGenres allKeys];
        NSString* label = [NSString stringWithFormat:array.count > 1 ? @"All (%ld Genres)" : @"All (%ld Genre)", array.count];
        [genres setArray:[array sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)]];
        [genres insertObject:label atIndex:0];
    }
    if (artists != nil) {
        NSArray* array = [filteredArtists allKeys];
        NSString* label = [NSString stringWithFormat:array.count > 1 ? @"All (%ld Artists)" : @"All (%ld Artist)", array.count];
        [artists setArray:[[filteredArtists allKeys] sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)]];
        [artists insertObject:label atIndex:0];
    }
    if (albums != nil) {
        NSArray* array = [filteredAlbums allKeys];
        NSString* label = [NSString stringWithFormat:array.count > 1 ? @"All (%ld Albums)" : @"All (%ld Album)", array.count];
        [albums setArray:[[filteredAlbums allKeys] sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)]];
        [albums insertObject:label atIndex:0];
    }
    if (tempos != nil) {
        NSArray* array = [filteredTempos allKeys];
        NSString* label = [NSString stringWithFormat:array.count > 1 ? @"All (%ld Tempos)" : @"All (%ld Tempo)", array.count];
        [tempos setArray:[[filteredTempos allKeys] sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)]];
        [tempos insertObject:label atIndex:0];
    }
    if (keys != nil) {
        NSArray* array = [filteredKeys allKeys];
        NSString* label = [NSString stringWithFormat:array.count > 1 ? @"All (%ld Keys)" : @"All (%ld Key)", array.count];
        [keys setArray:[[filteredKeys allKeys] sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)]];
        [keys insertObject:label atIndex:0];
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.delegate loadLibraryState:LoadStateStopped];
    });
}

- (BOOL)tableView:(NSTableView *)tableView
 shouldTypeSelectForEvent:(NSEvent *)event
  withCurrentSearchString:(NSString *)searchString
{
    NSLog(@"current event: %@", event.debugDescription);
    NSLog(@"current Search String: '%@'", searchString);
    return YES;
}

- (NSTableRowView*)tableView:(NSTableView*)tableView rowViewForRow:(NSInteger)row
{
    return [TableRowView new];
}

-(void)genresTableViewSelectionDidChange:(NSInteger)row
{
    NSString* genre = row > 0 ? _genres[row] : nil;
    NSString* artist = nil;
    NSString* album = nil;
    NSString* tempo = nil;
    NSString* key = nil;
    
    BrowserController* __weak weakSelf = self;

    NSArray<NSSortDescriptor*>* descriptors = [_songsTable sortDescriptors];

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
        weakSelf.filteredItems = [[self filterMediaItems:weakSelf.cachedLibrary
                                                  genre:genre
                                                 artist:artist
                                                  album:album
                                                  tempo:tempo
                                                    key:key] sortedArrayUsingDescriptors:descriptors];
        
        [weakSelf columnsFromMediaItems:weakSelf.filteredItems
                                 genres:nil
                                artists:weakSelf.artists
                                 albums:weakSelf.albums
                                 tempos:weakSelf.tempos
                                   keys:weakSelf.keys];

        dispatch_async(dispatch_get_main_queue(), ^{
            [weakSelf.artistsTable beginUpdates];
            [weakSelf.artistsTable reloadData];
            [weakSelf.artistsTable endUpdates];

            [weakSelf.albumsTable beginUpdates];
            [weakSelf.albumsTable reloadData];
            [weakSelf.albumsTable endUpdates];

            [weakSelf.temposTable beginUpdates];
            [weakSelf.temposTable reloadData];
            [weakSelf.temposTable endUpdates];

            [weakSelf.keysTable beginUpdates];
            [weakSelf.keysTable reloadData];
            [weakSelf.keysTable endUpdates];

            [weakSelf.songsTable beginUpdates];
            [weakSelf.songsTable reloadData];
            [weakSelf.songsTable endUpdates];

            NSIndexSet* zeroSet = [NSIndexSet indexSetWithIndex:0];
            self->_updatingArtists = YES;
            self->_updatingAlbums = YES;
            self->_updatingTempos = YES;
            self->_updatingKeys = YES;
            [weakSelf.artistsTable selectRowIndexes:zeroSet byExtendingSelection:NO];
            [weakSelf.albumsTable selectRowIndexes:zeroSet byExtendingSelection:NO];
            [weakSelf.temposTable selectRowIndexes:zeroSet byExtendingSelection:NO];
            [weakSelf.keysTable selectRowIndexes:zeroSet byExtendingSelection:NO];
            self->_updatingArtists = NO;
            self->_updatingAlbums = NO;
            self->_updatingTempos = NO;
            self->_updatingKeys = NO;
        });
    });
}

-(void)artistsTableSelectionDidChange:(NSInteger)row
{
    if (_updatingArtists) {
        return;
    }

    BrowserController* __weak weakSelf = self;

    NSString* genre = _genresTable.selectedRow > 0 ? _genres[_genresTable.selectedRow] : nil;
    NSString* artist = row > 0 ? _artists[row] : nil;
    NSString* album = nil;
    NSString* tempo = nil;
    NSString* key = nil;

    NSArray<NSSortDescriptor*>* descriptors = [_songsTable sortDescriptors];

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
        weakSelf.filteredItems = [[weakSelf filterMediaItems:weakSelf.cachedLibrary
                                                      genre:genre
                                                     artist:artist
                                                      album:album
                                                      tempo:tempo
                                                        key:key] sortedArrayUsingDescriptors:descriptors];
    
        [weakSelf columnsFromMediaItems:weakSelf.filteredItems
                                 genres:nil
                                artists:nil
                                 albums:weakSelf.albums
                                 tempos:weakSelf.tempos
                                   keys:weakSelf.keys];

        dispatch_async(dispatch_get_main_queue(), ^{
            [weakSelf.albumsTable beginUpdates];
            [weakSelf.albumsTable reloadData];
            [weakSelf.albumsTable endUpdates];

            [weakSelf.temposTable beginUpdates];
            [weakSelf.temposTable reloadData];
            [weakSelf.temposTable endUpdates];

            [weakSelf.keysTable beginUpdates];
            [weakSelf.keysTable reloadData];
            [weakSelf.keysTable endUpdates];

            [weakSelf.songsTable beginUpdates];
            [weakSelf.songsTable reloadData];
            [weakSelf.songsTable endUpdates];

            NSIndexSet* zeroSet = [NSIndexSet indexSetWithIndex:0];
            self->_updatingAlbums = YES;
            self->_updatingTempos = YES;
            self->_updatingKeys = YES;
            [weakSelf.albumsTable selectRowIndexes:zeroSet byExtendingSelection:NO];
            [weakSelf.temposTable selectRowIndexes:zeroSet byExtendingSelection:NO];
            [weakSelf.keysTable selectRowIndexes:zeroSet byExtendingSelection:NO];
            self->_updatingAlbums = NO;
            self->_updatingTempos = NO;
            self->_updatingKeys = NO;
        });
    });
}

-(void)albumsTableSelectionDidChange:(NSInteger)row
{
    if (_updatingAlbums) {
        return;
    }
    NSString* genre = _genresTable.selectedRow > 0 ? _genres[_genresTable.selectedRow] : nil;
    NSString* artist = _artistsTable.selectedRow > 0 ? _artists[_artistsTable.selectedRow] : nil;
    NSString* album = row > 0 ? _albums[row] : nil;
    NSString* tempo = nil;
    NSString* key = nil;

    BrowserController* __weak weakSelf = self;

    NSArray<NSSortDescriptor*>* descriptors = [_songsTable sortDescriptors];

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
        weakSelf.filteredItems = [[weakSelf filterMediaItems:weakSelf.cachedLibrary
                                                       genre:genre
                                                      artist:artist
                                                       album:album
                                                       tempo:tempo
                                                         key:key] sortedArrayUsingDescriptors:descriptors];

        [weakSelf columnsFromMediaItems:weakSelf.filteredItems
                                 genres:nil
                                artists:nil
                                 albums:nil
                                 tempos:weakSelf.tempos
                                   keys:weakSelf.keys];

        dispatch_async(dispatch_get_main_queue(), ^{
            [weakSelf.temposTable beginUpdates];
            [weakSelf.temposTable reloadData];
            [weakSelf.temposTable endUpdates];

            [weakSelf.keysTable beginUpdates];
            [weakSelf.keysTable reloadData];
            [weakSelf.keysTable endUpdates];

            [weakSelf.songsTable beginUpdates];
            [weakSelf.songsTable reloadData];
            [weakSelf.songsTable endUpdates];

            NSIndexSet* zeroSet = [NSIndexSet indexSetWithIndex:0];
            self->_updatingTempos = YES;
            self->_updatingKeys = YES;
            [weakSelf.temposTable selectRowIndexes:zeroSet byExtendingSelection:NO];
            [weakSelf.keysTable selectRowIndexes:zeroSet byExtendingSelection:NO];
            self->_updatingTempos = NO;
            self->_updatingKeys = NO;
        });
    });
}

-(void)keysTableSelectionDidChange:(NSInteger)row
{
    if (_updatingKeys) {
        return;
    }
    NSString* genre = _genresTable.selectedRow > 0 ? _genres[_genresTable.selectedRow] : nil;
    NSString* artist = _artistsTable.selectedRow > 0 ? _artists[_artistsTable.selectedRow] : nil;
    NSString* album = _albumsTable.selectedRow > 0 ? _albums[_albumsTable.selectedRow] : nil;
    NSString* tempo = _temposTable.selectedRow > 0 ? _tempos[row] : nil;
    NSString* key = row > 0 ? _keys[row] : nil;

    BrowserController* __weak weakSelf = self;
    NSArray<NSSortDescriptor*>* descriptors = [_songsTable sortDescriptors];

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
        weakSelf.filteredItems = [[weakSelf filterMediaItems:weakSelf.cachedLibrary
                                                       genre:genre
                                                      artist:artist
                                                       album:album
                                                       tempo:tempo
                                                         key:key] sortedArrayUsingDescriptors:descriptors];

        dispatch_async(dispatch_get_main_queue(), ^{
            [weakSelf.songsTable beginUpdates];
            [weakSelf.songsTable reloadData];
            [weakSelf.songsTable endUpdates];
        });
    });

}

-(void)temposTableSelectionDidChange:(NSInteger)row
{
    if (_updatingTempos) {
        return;
    }
    NSString* genre = _genresTable.selectedRow > 0 ? _genres[_genresTable.selectedRow] : nil;
    NSString* artist = _artistsTable.selectedRow > 0 ? _artists[_artistsTable.selectedRow] : nil;
    NSString* album = _albumsTable.selectedRow > 0 ? _albums[_albumsTable.selectedRow] : nil;
    NSString* tempo = row > 0 ? _tempos[row] : nil;
    NSString* key = nil;

    BrowserController* __weak weakSelf = self;
    NSArray<NSSortDescriptor*>* descriptors = [_songsTable sortDescriptors];

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
        weakSelf.filteredItems = [[weakSelf filterMediaItems:weakSelf.cachedLibrary
                                                       genre:genre
                                                      artist:artist
                                                       album:album
                                                       tempo:tempo
                                                         key:key] sortedArrayUsingDescriptors:descriptors];

        [weakSelf columnsFromMediaItems:weakSelf.filteredItems
                                 genres:nil
                                artists:nil
                                 albums:nil
                                 tempos:nil
                                   keys:weakSelf.keys];

        dispatch_async(dispatch_get_main_queue(), ^{
            [weakSelf.keysTable beginUpdates];
            [weakSelf.keysTable reloadData];
            [weakSelf.keysTable endUpdates];

            [weakSelf.songsTable beginUpdates];
            [weakSelf.songsTable reloadData];
            [weakSelf.songsTable endUpdates];

            NSIndexSet* zeroSet = [NSIndexSet indexSetWithIndex:0];
            
            self->_updatingKeys = YES;
            [weakSelf.keysTable selectRowIndexes:zeroSet byExtendingSelection:NO];
            self->_updatingKeys = NO;

        });
    });
    return;
}

-(void)tableViewSelectionDidChange:(NSNotification *)notification{

    NSTableView* tableView = [notification object];
    NSInteger row = [tableView selectedRow];

    switch(tableView.tag) {
        case VIEWTAG_GENRE:
            [self genresTableViewSelectionDidChange:row];
        break;
        case VIEWTAG_ARTISTS:
            [self artistsTableSelectionDidChange:row];
        break;
        case VIEWTAG_ALBUMS:
            [self albumsTableSelectionDidChange:row];
        break;
        case VIEWTAG_TEMPO:
            [self temposTableSelectionDidChange:row];
        break;
        case VIEWTAG_KEY:
            [self keysTableSelectionDidChange:row];
        break;
        case VIEWTAG_FILTERED: {
            MediaMetaData* item = row >= 0 ? _filteredItems[row] : nil;
            NSURL* url = item.location;
            switch (item.locationType) {
                case MediaMetaDataLocationTypeFile:    NSLog(@"that item is a file");  break;
                case MediaMetaDataLocationTypeURL:     NSLog(@"that item is a URL");   break;
                case MediaMetaDataLocationTypeRemote:  NSLog(@"that item is remote");  break;
                case MediaMetaDataLocationTypeUnknown:
                default:
                    NSLog(@"that item is of unknown location type");
            }
            if (item.artwork) {
                NSLog(@"artwork is available");
            }
            if (url != nil && _delegate != nil) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self.delegate browseSelectedUrl:url meta:item];
                });
            }
            return;
        }
    }
}

- (BOOL)tableView:(NSTableView*)tableView shouldSelectRow:(NSInteger)row
{
    switch(tableView.tag) {
        case VIEWTAG_GENRE: {
            return YES;
        }
        case VIEWTAG_ARTISTS: {
            return YES;
        }
        case VIEWTAG_ALBUMS: {
            return YES;
        }
        case VIEWTAG_TEMPO: {
            return YES;
        }
        case VIEWTAG_KEY: {
            return YES;
        }
        case VIEWTAG_FILTERED: {
            return YES;
        }
        default:
            return YES;
    }
    return NO;
}

- (NSInteger)numberOfRowsInTableView:(NSTableView*)tableView
{
    switch(tableView.tag) {
        case VIEWTAG_GENRE:
            return _genres.count;
        case VIEWTAG_ARTISTS:
            return _artists.count;
        case VIEWTAG_ALBUMS:
            return _albums.count;
        case VIEWTAG_TEMPO:
            return _tempos.count;
        case VIEWTAG_KEY:
            return _keys.count;
        case VIEWTAG_FILTERED:
            return _filteredItems.count;
        default:
            return 0;
    }
    return 0;
}

-(NSString*)formattedDuration:(NSTimeInterval)interval
{
    NSDateComponentsFormatter* formatter = [[NSDateComponentsFormatter alloc] init];
    formatter.allowedUnits = NSCalendarUnitHour | NSCalendarUnitMinute | NSCalendarUnitSecond;
    formatter.zeroFormattingBehavior = NSDateComponentsFormatterZeroFormattingBehaviorDropLeading;
    return [formatter stringFromTimeInterval:interval / 1000];
}

- (void)tableView:(NSTableView*)tableView sortDescriptorsDidChange:(NSArray<NSSortDescriptor*>*)oldDescriptors
{
    NSArray<NSSortDescriptor*>* descriptors = [tableView sortDescriptors];
    _filteredItems = [_filteredItems sortedArrayUsingDescriptors:descriptors];
    [tableView reloadData];
}

- (NSView*)tableView:(NSTableView*)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row
{
    NSTableCellView *result = [tableView makeViewWithIdentifier:tableColumn.identifier owner:self];
    if (result == nil)
    {
        result = [[NSTableCellView alloc] initWithFrame:NSMakeRect(0.0,
                                                                   0.0,
                                                                   tableColumn.width,
                                                                   14.0)];
    
        NSTextField* tf = [[NSTextField alloc] initWithFrame:NSInsetRect(result.frame, 0, -4)];
        tf.editable = NO;
        tf.font = [NSFont systemFontOfSize:11.0];
        tf.drawsBackground = NO;
        tf.bordered = NO;
        tf.textColor = [NSColor secondaryLabelColor];
        [result addSubview:tf];
        result.textField = tf;
        result.identifier = tableColumn.identifier;
    }

    NSString* string = nil;
    switch(tableView.tag) {
        case VIEWTAG_GENRE:
            assert(row < _genres.count);
            string = _genres[row];
        break;
        case VIEWTAG_ARTISTS:
            assert(row < _artists.count);
            string = _artists[row];
        break;
        case VIEWTAG_ALBUMS:
            assert(row < _albums.count);
            string = _albums[row];
        break;
        case VIEWTAG_TEMPO:
            assert(row < _tempos.count);
            string = _tempos[row];
        break;
        case VIEWTAG_KEY:
            assert(row < _keys.count);
            string = _keys[row];
        break;
        case VIEWTAG_FILTERED:
            assert(row < _filteredItems.count);
            if ([tableColumn.identifier isEqualToString:@"TrackCell"]) {
                if (_filteredItems[row].track > 0) {
                    string = [NSString stringWithFormat:@"%ld", _filteredItems[row].track];
                }
            } else if ([tableColumn.identifier isEqualToString:@"TitleCell"]) {
                string = _filteredItems[row].title;
            } else if ([tableColumn.identifier isEqualToString:@"ArtistCell"]) {
                string = _filteredItems[row].artist;
            } else if ([tableColumn.identifier isEqualToString:@"AlbumCell"]) {
                string = _filteredItems[row].album;
            } else if ([tableColumn.identifier isEqualToString:@"TimeCell"]) {
                string = [self formattedDuration:_filteredItems[row].duration];
            } else if ([tableColumn.identifier isEqualToString:@"TempoCell"]) {
                if (_filteredItems[row].tempo > 0) {
                    string = [NSString stringWithFormat:@"%d", (unsigned int)_filteredItems[row].tempo];
                } else {
                    string = @"";
                }
            } else if ([tableColumn.identifier isEqualToString:@"KeyCell"]) {
                string = _filteredItems[row].key;
            } else if ([tableColumn.identifier isEqualToString:@"AddedCell"]) {
                string = [NSString BeautifulPast:_filteredItems[row].added];
            } else if ([tableColumn.identifier isEqualToString:@"GenreCell"]) {
                string = _filteredItems[row].genre;
            }
        break;
        default:
            string = @"<??? UNKNOWN ???>";
    }
    if (string == nil) {
        string = @"";
    }
    //if (result.backgroundStyle == NSBackgroundStyleEmphasized) {
    
    //result.textField.textColor = [NSColor secondaryLabelColor];
//    if (tableView.selectedRow >= 0) {
//        if (row == tableView.selectedRow) {
//            result.textField.textColor = [NSColor alternateSelectedControlTextColor];
//        }
//    }
    [result.textField setStringValue:string];

    //} else {
    //    result.textField.textColor = [NSColor secondaryLabelColor];
    //}
    

    return result;
}

@end
