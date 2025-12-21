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

#import <CoreImage/CoreImage.h>

#import "CAShapeLayer+Path.h"
#import "NSBezierPath+CGPath.h"
#import "ProfilingPointsOfInterest.h"

#import "MediaMetaData.h"

#import "TableHeaderCell.h"
#import "TableRowView.h"
#import "TableCellView.h"

#import "NSString+BeautifulPast.h"
#import "NSURL+WithoutParameters.h"

NSString* const kSongsColTrackNumber = @"TrackCell";
NSString* const kSongsColTitle = @"TitleCell";
NSString* const kSongsColArtist = @"ArtistCell";
NSString* const kSongsColAlbum = @"AlbumCell";
NSString* const kSongsColTime = @"TimeCell";
NSString* const kSongsColTempo = @"TempoCell";
NSString* const kSongsColKey = @"KeyCell";
NSString* const kSongsColRating = @"RatingCell";
NSString* const kSongsColTags = @"TagsCell";
NSString* const kSongsColAdded = @"AddedCell";
NSString* const kSongsColGenre = @"GenreCell";

@interface BrowserController ()
@property (nonatomic, strong) ITLibrary* library;
@property (nonatomic, strong) NSMutableArray<MediaMetaData*>* cachedLibrary;

@property (nonatomic, weak) NSTableView* genresTable;
@property (nonatomic, weak) NSTableView* artistsTable;
@property (nonatomic, weak) NSTableView* albumsTable;
@property (nonatomic, weak) NSTableView* temposTable;
@property (nonatomic, weak) NSTableView* keysTable;
@property (nonatomic, weak) NSTableView* songsTable;
@property (nonatomic, weak) NSTableView* ratingsTable;
@property (nonatomic, weak) NSTableView* tagsTable;
@property (nonatomic, weak) NSSearchField* searchField;

@property (nonatomic, copy) NSURL* currentLocation;

@property (nonatomic, strong) NSMutableArray<NSString*>* genres;
@property (nonatomic, strong) NSMutableArray<NSString*>* artists;
@property (nonatomic, strong) NSMutableArray<NSString*>* albums;
@property (nonatomic, strong) NSMutableArray<NSString*>* tempos;
@property (nonatomic, strong) NSMutableArray<NSString*>* keys;
@property (nonatomic, strong) NSMutableArray<NSString*>* ratings;
@property (nonatomic, strong) NSMutableArray<NSString*>* tags;
@property (nonatomic, strong) NSArray<MediaMetaData*>* filteredItems;

@property (strong, nonatomic) dispatch_queue_t filterQueue;

@end

@implementation BrowserController
{
    bool _updatingGenres;
    bool _updatingArtists;
    bool _updatingAlbums;
    bool _updatingTempos;
    bool _updatingKeys;
    bool _updatingRatings;
    bool _updatingTags;
    
    MediaMetaData* _lazyUpdatedMeta;
}

- (id)initWithGenresTable:(NSTableView*)genresTable
             artistsTable:(NSTableView*)artistsTable
              albumsTable:(NSTableView*)albumsTable
              temposTable:(NSTableView*)temposTable
               songsTable:(NSTableView*)songsTable
                keysTable:(NSTableView*)keysTable
             ratingsTable:(NSTableView*)ratingsTable
                tagsTable:(NSTableView*)tagsTable
              searchField:(NSSearchField*)searchField
                 delegate:(id<BrowserControllerDelegate>)delegate
{
    self = [super init];
    if (self) {
        _delegate = delegate;
        
        _currentLocation = nil;

        _updatingGenres = NO;
        _updatingArtists = NO;
        _updatingAlbums = NO;
        _updatingTempos = NO;
        _updatingKeys = NO;
        _updatingRatings = NO;
        _updatingTags = NO;

        _genres = [NSMutableArray array];
        _artists = [NSMutableArray array];
        _albums = [NSMutableArray array];
        _tempos = [NSMutableArray array];
        _keys = [NSMutableArray array];
        _ratings = [NSMutableArray array];
        _tags = [NSMutableArray array];
        
        _searchField = searchField;
        _searchField.delegate = self;

        _genresTable = genresTable;
        _genresTable.dataSource = self;
        _genresTable.delegate = self;
        _genresTable.nextKeyView = artistsTable;

        _artistsTable = artistsTable;
        _artistsTable.dataSource = self;
        _artistsTable.delegate = self;
        _artistsTable.nextKeyView = albumsTable;

        _albumsTable = albumsTable;
        _albumsTable.dataSource = self;
        _albumsTable.delegate = self;
        _albumsTable.nextKeyView = temposTable;

        _temposTable = temposTable;
        _temposTable.dataSource = self;
        _temposTable.delegate = self;
        _temposTable.nextKeyView = keysTable;

        _keysTable = keysTable;
        _keysTable.dataSource = self;
        _keysTable.delegate = self;
        _keysTable.nextKeyView = songsTable;

        _ratingsTable = ratingsTable;
        _ratingsTable.dataSource = self;
        _ratingsTable.delegate = self;
        _ratingsTable.nextKeyView = ratingsTable;

        _tagsTable = tagsTable;
        _tagsTable.dataSource = self;
        _tagsTable.delegate = self;
        _tagsTable.nextKeyView = tagsTable;

        _songsTable = songsTable;
        _songsTable.dataSource = self;
        _songsTable.delegate = self;
        _songsTable.allowsTypeSelect = YES;
        _songsTable.allowsColumnReordering = NO;
        _songsTable.allowsColumnResizing = YES;
        _songsTable.doubleAction = @selector(doubleClickedSongsTableRow:);
        
        dispatch_queue_attr_t attr = dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL,
                                                                             QOS_CLASS_USER_INTERACTIVE,
                                                                             0);
        _filterQueue = dispatch_queue_create("PlayEm.BrowserFilterQueue", attr);

        [self loadITunesLibrary];
    }
    return self;
}

- (void)reloadData
{
    if (_cachedLibrary == nil) {
        NSLog(@"we dont have a cached library just yet - reload will happen when that is established");
        return;
    }

    NSArray<NSSortDescriptor*>* descriptors = [_songsTable sortDescriptors];
    
    BrowserController* __weak weakSelf = self;
    
    NSMutableArray<MediaMetaData*>* __block cachedLibrary = _cachedLibrary;
    NSArray<MediaMetaData*>* __block filteredItems = _filteredItems;

    NSString* needle = _searchField.stringValue;
    NSString* genre = _genresTable.selectedRow > 0 ? _genres[_genresTable.selectedRow] : nil;
    NSString* artist = _artistsTable.selectedRow > 0 ? _artists[_artistsTable.selectedRow] : nil;
    NSString* album = _albumsTable.selectedRow > 0 ? _albums[_albumsTable.selectedRow] : nil;
    NSString* tempo = _temposTable.selectedRow > 0 ? _tempos[_temposTable.selectedRow] : nil;
    NSString* key = _keysTable.selectedRow > 0 ? _keys[_keysTable.selectedRow] : nil;
    NSString* rating = _ratingsTable.selectedRow > 0 ? _ratings[_ratingsTable.selectedRow] : nil;
    NSString* tag = _tagsTable.selectedRow > 0 ? _tags[_tagsTable.selectedRow] : nil;

    dispatch_async(_filterQueue, ^{
        // Apply filtering and sorting.
        filteredItems = [[weakSelf filterMediaItems:cachedLibrary
                                              genre:genre
                                             artist:artist
                                              album:album
                                              tempo:tempo
                                                key:key
                                             rating:rating
                                                tag:tag
                                             needle:needle] sortedArrayUsingDescriptors:descriptors];

        // This weird construct shall assure that we only reload those columns that are
        // undetermined by a selection with a priority built in. 
        // That means that if the user selected an `album` but nothing else, `reloadData`
        // will re-populate all the table to the right - that is `tempos`, `keys` and so on columns.
        // If the user had selected a `genre` but nothing else, all but the `genres` column
        // get reloaded. If the user selected a `key` but nothing else, nothing gets reloaded.
        NSMutableArray* destGenres = nil;
        NSMutableArray* destArtists = nil;
        NSMutableArray* destAlbums = nil;
        NSMutableArray* destTempos = nil;
        NSMutableArray* destKeys = nil;
        NSMutableArray* destRatings = nil;
        NSMutableArray* destTags = nil;
        if (tag == nil) {
            destTags = weakSelf.tags;
            if (rating == nil) {
                destRatings = weakSelf.ratings;
                if (key == nil) {
                    destKeys = weakSelf.keys;
                    if (tempo == nil) {
                        destTempos = weakSelf.tempos;
                        if (album == nil) {
                            destAlbums = weakSelf.albums;
                            if (artist == nil) {
                                destArtists = weakSelf.artists;
                                if (genre == nil) {
                                    destGenres = weakSelf.genres;
                                }
                            }
                        }
                    }
                }
            }
        }
        [weakSelf columnsFromMediaItems:filteredItems
                                 genres:destGenres
                                artists:destArtists
                                 albums:destAlbums
                                 tempos:destTempos
                                   keys:destKeys
                                ratings:destRatings
                                   tags:destTags];

        dispatch_sync(dispatch_get_main_queue(), ^{
            weakSelf.filteredItems = filteredItems;
            
            [weakSelf setNowPlayingWithMeta:self->_lazyUpdatedMeta];

            NSIndexSet* genreSelections = [self->_genresTable selectedRowIndexes];
            NSIndexSet* artistSelections = [self->_artistsTable selectedRowIndexes];
            NSIndexSet* albumSelections = [self->_albumsTable selectedRowIndexes];
            NSIndexSet* tempoSelections = [self->_temposTable selectedRowIndexes];
            NSIndexSet* keySelections = [self->_keysTable selectedRowIndexes];
            NSIndexSet* ratingSelections = [self->_ratingsTable selectedRowIndexes];
            NSIndexSet* tagSelections = [self->_tagsTable selectedRowIndexes];
            NSIndexSet* songSelections = [self->_songsTable selectedRowIndexes];

            [weakSelf.genresTable beginUpdates];
            [weakSelf.genresTable reloadData];
            [weakSelf.genresTable endUpdates];
            
            [weakSelf.albumsTable beginUpdates];
            [weakSelf.albumsTable reloadData];
            [weakSelf.albumsTable endUpdates];
            
            [weakSelf.artistsTable beginUpdates];
            [weakSelf.artistsTable reloadData];
            [weakSelf.artistsTable endUpdates];
            
            [weakSelf.temposTable beginUpdates];
            [weakSelf.temposTable reloadData];
            [weakSelf.temposTable endUpdates];
                        
            [weakSelf.keysTable beginUpdates];
            [weakSelf.keysTable reloadData];
            [weakSelf.keysTable endUpdates];

            [weakSelf.ratingsTable beginUpdates];
            [weakSelf.ratingsTable reloadData];
            [weakSelf.ratingsTable endUpdates];

            [weakSelf.tagsTable beginUpdates];
            [weakSelf.tagsTable reloadData];
            [weakSelf.tagsTable endUpdates];

            [weakSelf.songsTable beginUpdates];
            [weakSelf.songsTable reloadData];
            [weakSelf.songsTable endUpdates];

            self->_updatingGenres = YES;
            self->_updatingArtists = YES;
            self->_updatingAlbums = YES;
            self->_updatingTempos = YES;
            self->_updatingKeys = YES;
            self->_updatingRatings = YES;
            self->_updatingTags = YES;

            [weakSelf.genresTable selectRowIndexes:genreSelections
                              byExtendingSelection:NO];
            [weakSelf.artistsTable selectRowIndexes:artistSelections
                              byExtendingSelection:NO];
            [weakSelf.albumsTable selectRowIndexes:albumSelections
                              byExtendingSelection:NO];
            [weakSelf.temposTable selectRowIndexes:tempoSelections
                              byExtendingSelection:NO];
            [weakSelf.keysTable selectRowIndexes:keySelections
                              byExtendingSelection:NO];
            [weakSelf.ratingsTable selectRowIndexes:ratingSelections
                              byExtendingSelection:NO];
            [weakSelf.tagsTable selectRowIndexes:tagSelections
                              byExtendingSelection:NO];
            [weakSelf.songsTable selectRowIndexes:songSelections
                              byExtendingSelection:NO];
            NSLog(@"selecting songs %@", songSelections);

            self->_updatingGenres = NO;
            self->_updatingArtists = NO;
            self->_updatingAlbums = NO;
            self->_updatingTempos = NO;
            self->_updatingKeys = NO;
            self->_updatingRatings = NO;
            self->_updatingTags = NO;
            
            [weakSelf.delegate updateSongsCount:weakSelf.cachedLibrary.count
                                       filtered:weakSelf.filteredItems.count];
        });
    });
}

- (void)metaChangedForMeta:(MediaMetaData *)meta updatedMeta:(MediaMetaData *)updatedMeta
{
    NSAssert(meta != nil, @"updated MediaMetaData %p has no known original", updatedMeta);
    NSAssert(updatedMeta != nil, @"no updated MediaMetaData given - what is happening");

    NSUInteger index = [self.cachedLibrary indexOfObject:meta];
    if (index == NSNotFound) {
        // We may end up right here when the song in question does not originally come from
        // the filtered list of songs. In such cases, get the actual meta object from the
        // cached library using the URL from the "original" meta.
        NSUInteger fakeIndex = [self songsRowForMeta:meta];
        if (fakeIndex == NSNotFound) {
            NSLog(@"MediaMetaData for %@ does not exist in filtered library", meta.location);
            return;
        }
        meta = self.filteredItems[fakeIndex];
        // We need the index of that meta from the cached library for the following logic.
        index = [self.cachedLibrary indexOfObject:meta];
    }
    if (index != NSNotFound) {
        NSLog(@"MediaMetaData %p updated does not exist in cached library", meta);
        [self.cachedLibrary replaceObjectAtIndex:index withObject:updatedMeta];
    }
    //NSLog(@"replaced metadata in cachedLibrary %p with %p", meta, updatedMeta);

    NSMutableArray* filtered = [NSMutableArray arrayWithArray:_filteredItems];
    index = [filtered indexOfObject:meta];
    if (index == NSNotFound) {
        NSLog(@"MediaMetaData %p updated does not exist in filtered library", meta);
        return;
    }
    [filtered replaceObjectAtIndex:index withObject:updatedMeta];
    //NSLog(@"replaced metadata in filteredObject %p with %p", meta, updatedMeta);
    self.filteredItems = filtered;
}

- (NSMutableArray*)cacheFromiTunesLibrary:(ITLibrary*)library
{
    NSMutableArray<MediaMetaData*>* cache = [NSMutableArray new];
    
    NSLog(@"iTunes returned %ld items", library.allMediaItems.count);

    size_t skippedCloudItems = 0;
    size_t skippedAAXFiles = 0;
    for (ITLibMediaItem* d in library.allMediaItems) {
        // We cannot support cloud based items, unfortunately.
        if (d.cloud) {
            skippedCloudItems++;
            continue;
        }
        // We cannot support encrypted audiobooks, unfortunately.
        if ([[[d.location filePathURL] pathExtension] isEqualToString:@"aax"] ) {
            skippedAAXFiles++;
            continue;
        }
        MediaMetaData* m = [MediaMetaData mediaMetaDataWithITLibMediaItem:d error:nil];
        [cache addObject:m];
    }

    NSLog(@"%ld cloud based items ignored", skippedCloudItems);
    NSLog(@"%ld encrypted audiobooks ignored", skippedAAXFiles);

    return cache;
}

- (void)resetTableView:(NSTableView*)table
{
    NSIndexSet* zeroSet = [NSIndexSet indexSetWithIndex:0];
    [table beginUpdates];
    [table selectRowIndexes:zeroSet byExtendingSelection:NO];
    [table reloadData];
    [table endUpdates];
}

- (void)reloadTableView:(NSTableView*)table
{
    [table beginUpdates];
    [table reloadData];
    [table endUpdates];
}

- (void)loadITunesLibrary
{
    NSError *error = nil;
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
    _keys = [NSMutableArray array];
    _tempos = [NSMutableArray array];
    _ratings = [NSMutableArray array];
    _tags = [NSMutableArray array];

    [self resetTableView:_genresTable];
    [self resetTableView:_artistsTable];
    [self resetTableView:_albumsTable];
    [self resetTableView:_temposTable];
    [self resetTableView:_keysTable];
    [self resetTableView:_ratingsTable];
    [self resetTableView:_tagsTable];
    [self resetTableView:_songsTable];
    
    BrowserController* __weak weakSelf = self;
    
    NSArray<NSSortDescriptor*>* descriptors = [_songsTable sortDescriptors];
    
    dispatch_async(_filterQueue, ^{
        //[_delegate loadLibraryState:LoadStateStarted value:0.0];
        
        NSMutableArray<MediaMetaData*>* cachedLibrary = [weakSelf cacheFromiTunesLibrary:weakSelf.library];
        
        // Apply sorting.
        weakSelf.filteredItems = [cachedLibrary sortedArrayUsingDescriptors:descriptors];
        weakSelf.cachedLibrary = cachedLibrary;
        
        [weakSelf columnsFromMediaItems:weakSelf.filteredItems
                                 genres:weakSelf.genres
                                artists:weakSelf.artists
                                 albums:weakSelf.albums
                                 tempos:weakSelf.tempos
                                   keys:weakSelf.keys
                                ratings:weakSelf.ratings
                                   tags:weakSelf.tags];
        
        dispatch_sync(dispatch_get_main_queue(), ^{
            [weakSelf reloadTableView:weakSelf.genresTable];
            
            [weakSelf.delegate updateSongsCount:weakSelf.cachedLibrary.count
                                       filtered:weakSelf.filteredItems.count];
            
            self->_updatingGenres = NO;
            self->_updatingArtists = NO;
            self->_updatingAlbums = NO;
            self->_updatingTempos = NO;
            self->_updatingKeys = NO;
            self->_updatingRatings = NO;
            self->_updatingTags = NO;
            [weakSelf.genresTable selectRowIndexes:[NSIndexSet indexSetWithIndex:0]
                              byExtendingSelection:NO];
            
            [weakSelf reloadTableView:weakSelf.albumsTable];
            [weakSelf reloadTableView:weakSelf.artistsTable];
            [weakSelf reloadTableView:weakSelf.temposTable];
            [weakSelf reloadTableView:weakSelf.keysTable];
            [weakSelf reloadTableView:weakSelf.ratingsTable];
            [weakSelf reloadTableView:weakSelf.tagsTable];
            [weakSelf reloadTableView:weakSelf.songsTable];
            
            [weakSelf setNowPlayingWithMeta:self->_lazyUpdatedMeta];
        });
    });
}

- (void)setNowPlayingWithMeta:(MediaMetaData*)meta
{
    if ( _filteredItems != nil) {
        [self setCurrentMeta:meta];
        [self setPlaying:YES];
        [self showSongRowForMeta:meta];
    } else {
        _lazyUpdatedMeta = meta;
    }
}

- (void)setPlaying:(BOOL)playing
{
    NSUInteger lastIndex = [_filteredItems indexOfObjectPassingTest:^BOOL(MediaMetaData* meta, NSUInteger idx, BOOL* stop) {
        return [meta.location.absoluteString isEqualToString:_currentLocation.absoluteString];
    }];
    if (lastIndex != NSNotFound && lastIndex < [_songsTable numberOfRows]) {
        TableRowView* rowView = [_songsTable rowViewAtRow:lastIndex makeIfNecessary:YES];
        [rowView setExtraState:playing ? kExtraStatePlaying : kExtraStateActive];
    }
}

- (NSUInteger)songsRowForMeta:(MediaMetaData*)meta
{
    // Get meta item index.
    NSURL* needle = [meta.location URLWithoutParameters];
    return [_filteredItems indexOfObjectPassingTest:^BOOL(MediaMetaData* meta, NSUInteger idx, BOOL* stop) {
        return [meta.location.absoluteString isEqualToString:needle.absoluteString];
    }];
}

- (void)setCurrentMeta:(MediaMetaData*)meta
{
    NSURL* currentLocation = [meta.location URLWithoutParameters];
    // FIXME; This is a horrendous hack using a static variable for storing the location
    // of the currently active meta.
    //[MediaMetaData setActiveLocation:currentLocation];

    if (currentLocation == _currentLocation) {
        return;
    }
    
    NSUInteger lastIndex = [_filteredItems indexOfObjectPassingTest:^BOOL(MediaMetaData* meta, NSUInteger idx, BOOL* stop) {
        return [meta.location.absoluteString isEqualToString:_currentLocation.absoluteString];
    }];
    if (lastIndex != NSNotFound && lastIndex < [_songsTable numberOfRows]) {
        TableRowView* rowView = [_songsTable rowViewAtRow:lastIndex makeIfNecessary:YES];
        [rowView setExtraState:kExtraStateNormal];
    }

    NSUInteger index = [_filteredItems indexOfObjectPassingTest:^BOOL(MediaMetaData* meta, NSUInteger idx, BOOL* stop) {
        return [meta.location.absoluteString isEqualToString:currentLocation.absoluteString];
    }];
    if (index != NSNotFound && index < [_songsTable numberOfRows]) {
        TableRowView* rowView = [_songsTable rowViewAtRow:index makeIfNecessary:YES];
        [rowView setExtraState:kExtraStateActive];
    }
    
    _currentLocation = currentLocation;
}

- (void)updatedNeedle
{
    NSString* needle = _searchField.stringValue;
    NSLog(@"starting search for: %@", needle);

    NSString* genre = _genresTable.selectedRow > 0 ? _genres[_genresTable.selectedRow] : nil;
    NSString* artist = _artistsTable.selectedRow > 0 ? _artists[_artistsTable.selectedRow] : nil;
    NSString* album = _albumsTable.selectedRow > 0 ? _albums[_albumsTable.selectedRow] : nil;
    NSString* tempo = _temposTable.selectedRow > 0 ? _tempos[_temposTable.selectedRow] : nil;
    NSString* key = _keysTable.selectedRow > 0 ? _keys[_keysTable.selectedRow] : nil;
    NSString* rating = _ratingsTable.selectedRow > 0 ? _ratings[_ratingsTable.selectedRow] : nil;
    NSString* tag = _tagsTable.selectedRow > 0 ? _tags[_tagsTable.selectedRow] : nil;

    BrowserController* __weak weakSelf = self;
    NSArray<NSSortDescriptor*>* descriptors = [_songsTable sortDescriptors];

    dispatch_async(_filterQueue, ^{
        weakSelf.filteredItems = [[weakSelf filterMediaItems:weakSelf.cachedLibrary
                                                       genre:genre
                                                      artist:artist
                                                       album:album
                                                       tempo:tempo
                                                         key:key
                                                      rating:rating
                                                         tag:tag
                                                      needle:needle] sortedArrayUsingDescriptors:descriptors];

        dispatch_sync(dispatch_get_main_queue(), ^{
            [weakSelf.songsTable beginUpdates];
            [weakSelf.songsTable reloadData];
            [weakSelf.songsTable endUpdates];
        });
    });
}

- (void)showSongRowForMeta:(MediaMetaData*)meta
{
    NSUInteger rowIndex = [self songsRowForMeta:meta];
    if (rowIndex == NSNotFound) {
        NSLog(@"song not found, nothign to show");
        return;
    }
    [_songsTable scrollRowToVisible:rowIndex];
}

- (MediaMetaData* _Nullable)nextSong
{
    NSUInteger row = [self songsRowForMeta:_delegate.currentSongMeta];
    return [self metaAtSongRow:row + 1];
}

- (MediaMetaData* _Nullable)metaAtSongRow:(NSUInteger)row
{
    if (row >= self.filteredItems.count) {
        NSLog(@"end of songs listed reached");
        return nil;
    }
    return self.filteredItems[row];
}

- (IBAction)playNextInPlaylist:(id)sender
{
    [self.songsTable.selectedRowIndexes enumerateIndexesWithOptions:NSEnumerationReverse
                                                         usingBlock:^(NSUInteger idx, BOOL *stop) {
        MediaMetaData* meta = self.filteredItems[idx];
        NSLog(@"playNext item: %@", meta);
        [_delegate addToPlaylistNext:meta];
    }];
}

- (IBAction)playLaterInPlaylist:(id)sender
{
    [self.songsTable.selectedRowIndexes enumerateIndexesWithOptions:NSEnumerationReverse
                                                         usingBlock:^(NSUInteger idx, BOOL *stop) {
        MediaMetaData* meta = self.filteredItems[idx];
        NSLog(@"playLater item: %@", meta);
        [_delegate addToPlaylistLater:meta];
    }];
}

- (void)showInfoForCurrentSong:(id)sender
{
    [self.delegate showInfoForMetas:[NSArray arrayWithObject:self.delegate.currentSongMeta]];
}

- (void)showInfoForSelectedSongs:(id)sender
{
    NSMutableArray* metas = [NSMutableArray array];
    if (self.songsTable.clickedRow >= 0) {
        assert(self.songsTable.clickedRow < self.filteredItems.count);
        [metas addObject:self.filteredItems[self.songsTable.clickedRow]];
        NSLog(@"item: %@", self.filteredItems[self.songsTable.clickedRow]);
    } else {
        [metas addObjectsFromArray:[self selectedSongMetas]];
    }
    [self.delegate showInfoForMetas:metas];
}

- (IBAction)showInFinder:(id)sender
{
    MediaMetaData* meta = nil;
    if (self.songsTable.clickedRow >= 0) {
        assert(self.songsTable.clickedRow < self.filteredItems.count);
        meta = self.filteredItems[self.songsTable.clickedRow];
        NSLog(@"item: %@", self.filteredItems[self.songsTable.clickedRow]);
    } else if (self.delegate.currentSongMeta != nil) {
        meta = self.delegate.currentSongMeta;
    }
    if (meta == nil) {
        return;
    }
    NSArray<NSURL*>* fileURLs = [NSArray arrayWithObjects:meta.location, nil];
    [[NSWorkspace sharedWorkspace] activateFileViewerSelectingURLs:fileURLs];
}

- (NSArray*)filterMediaItems:(NSArray<MediaMetaData*>*)items
                       genre:(NSString*)genre
                      artist:(NSString*)artist
                       album:(NSString*)album
                       tempo:(NSString*)tempo
                         key:(NSString*)key
                       rating:(NSString*)rating
                         tag:(NSString*)tag
                      needle:(NSString*)needle
{
    NSLog(@"filtered based on genre:%@ artist:%@ album:%@ tempo:%@ key:%@, rating:%@, tag:%@, needle: %@", genre, artist, album, tempo, key, rating, tag, needle);
    NSMutableArray* filtered = [NSMutableArray array];

    for (MediaMetaData *d in items) {
        NSArray* tags = nil;
        if (d.tags && d.tags.length) {
            if ([[d.tags substringToIndex:1] isEqualToString:@"#"]) {
                tags = [[d.tags substringFromIndex:1] componentsSeparatedByString:@"#"];
            }
        }
        // Filter per column browser first.
        if ((genre == nil || (d.genre && d.genre.length && [d.genre isEqualTo:genre])) &&
            (artist == nil || (d.artist && d.artist.length && [d.artist isEqualTo:artist])) &&
            (album == nil || (d.album && d.album.length && [d.album isEqualTo:album])) &&
            (key == nil || (d.key && d.key.length && [d.key isEqualTo:key])) &&
            (rating == nil || (d.rating && d.stars.length && [d.stars isEqualTo:rating])) &&
            (tag == nil || [tags containsObject:tag]) &&
            (tempo == nil || (d.tempo && [[d.tempo stringValue] isEqualTo:tempo]))) {
            // When the user entered a search needle, we additionally filter for that.
            if (needle.length) {
                if ((d.genre && d.genre.length && [d.genre localizedCaseInsensitiveContainsString:needle]) ||
                    (d.title && d.title.length && [d.title localizedCaseInsensitiveContainsString:needle]) ||
                    (d.artist && d.artist.length && [d.artist localizedCaseInsensitiveContainsString:needle]) ||
                    (d.album && d.album.length && [d.album localizedCaseInsensitiveContainsString:needle]) ||
                    (d.key && d.key.length && [d.key localizedCaseInsensitiveContainsString:needle]) ||
                    (d.rating && d.stars.length && [d.stars localizedCaseInsensitiveContainsString:needle]) ||
                    ([tags containsObject:needle]) ||
                    ([[d.tempo stringValue] localizedCaseInsensitiveContainsString:needle])) {
                    [filtered addObject:d];
                }
            } else {
                [filtered addObject:d];
            }
        }
    }

    NSLog(@"filtered narrowed from %ld to %ld entries", items.count, filtered.count);

    NSUInteger count = filtered.count;
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.delegate updateSongsCount:self->_cachedLibrary.count filtered:count];
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
                      ratings:(NSMutableArray*)ratings
                         tags:(NSMutableArray*)tags
{
    NSMutableDictionary* filteredGenres = [NSMutableDictionary dictionary];
    NSMutableDictionary* filteredArtists = [NSMutableDictionary dictionary];
    NSMutableDictionary* filteredAlbums = [NSMutableDictionary dictionary];
    NSMutableDictionary* filteredTempos = [NSMutableDictionary dictionary];
    NSMutableDictionary* filteredKeys = [NSMutableDictionary dictionary];
    NSMutableDictionary* filteredRatings = [NSMutableDictionary dictionary];
    NSMutableDictionary* filteredTags = [NSMutableDictionary dictionary];

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
        if (d.tempo && [d.tempo intValue] > 0) {
            NSString* t = [d.tempo stringValue];
            filteredTempos[t] = t;
        }
        if (d.key && d.key.length > 0) {
            filteredKeys[d.key] = d.key;
        }
        if (d.rating && [d.rating intValue] > 0) {
            NSString* s = d.stars;
            filteredRatings[s] = s;
        }
        if (d.tags && d.tags.length > 0) {
            if ([[d.tags substringToIndex:1] isEqualToString:@"#"]) {
                NSString* r = [d.tags substringFromIndex:1];
                NSArray<NSString*>* components = [r componentsSeparatedByString:@"#"];
                for (NSString* tag in components) {
                    filteredTags[tag] = tag;
                }
            }
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.delegate loadLibraryState:LoadStateLoading 
                                      value:(double)(itemIndex + 1) / (double)itemCount];
        });
        itemIndex++;
    }
    
    if (genres != nil) {
        NSArray* array = [filteredGenres allKeys];
        NSString* label = [NSString stringWithFormat:array.count != 1 ? @"All (%ld Genres)" : @"All (%ld Genre)", array.count];
        [genres setArray:[array sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)]];
        [genres insertObject:label atIndex:0];
    }
    if (artists != nil) {
        NSArray* array = [filteredArtists allKeys];
        NSString* label = [NSString stringWithFormat:array.count != 1 ? @"All (%ld Artists)" : @"All (%ld Artist)", array.count];
        [artists setArray:[[filteredArtists allKeys] sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)]];
        [artists insertObject:label atIndex:0];
    }
    if (albums != nil) {
        NSArray* array = [filteredAlbums allKeys];
        NSString* label = [NSString stringWithFormat:array.count != 1 ? @"All (%ld Albums)" : @"All (%ld Album)", array.count];
        [albums setArray:[[filteredAlbums allKeys] sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)]];
        [albums insertObject:label atIndex:0];
    }
    if (tempos != nil) {
        NSArray* array = [filteredTempos allKeys];
        NSString* label = [NSString stringWithFormat:array.count != 1 ? @"All (%ld Tempos)" : @"All (%ld Tempo)", array.count];
        [tempos setArray:[[filteredTempos allKeys] sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)]];
        [tempos insertObject:label atIndex:0];
    }
    if (keys != nil) {
        NSArray* array = [filteredKeys allKeys];
        NSString* label = [NSString stringWithFormat:array.count != 1 ? @"All (%ld Keys)" : @"All (%ld Key)", array.count];
        [keys setArray:[[filteredKeys allKeys] sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)]];
        [keys insertObject:label atIndex:0];
    }
    if (ratings != nil) {
        NSArray* array = [filteredRatings allKeys];
        NSString* label = [NSString stringWithFormat:array.count != 1 ? @"All (%ld Ratings)" : @"All (%ld Rating)", array.count];
        [ratings setArray:[[filteredRatings allKeys] sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)]];
        [ratings insertObject:label atIndex:0];
    }
    if (tags != nil) {
        NSArray* array = [filteredTags allKeys];
        NSString* label = [NSString stringWithFormat:array.count != 1 ? @"All (%ld Tags)" : @"All (%ld Tag)", array.count];
        [tags setArray:[[filteredTags allKeys] sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)]];
        [tags insertObject:label atIndex:0];
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.delegate loadLibraryState:LoadStateStopped];
    });
}

-(void)genresTableViewSelectionDidChange:(NSInteger)row
{
    if (_updatingGenres) {
        return;
    }

    NSString* genre = row > 0 ? _genres[row] : nil;
    NSString* artist = nil;
    NSString* album = nil;
    NSString* tempo = nil;
    NSString* key = nil;
    NSString* rating = nil;
    NSString* tag = nil;
    NSString* needle = nil;

    BrowserController* __weak weakSelf = self;

    NSArray<NSSortDescriptor*>* descriptors = [_songsTable sortDescriptors];

    dispatch_async(_filterQueue, ^{
        weakSelf.filteredItems = [[self filterMediaItems:weakSelf.cachedLibrary
                                                   genre:genre
                                                  artist:artist
                                                   album:album
                                                   tempo:tempo
                                                     key:key
                                                  rating:rating
                                                     tag:tag
                                                  needle:needle] sortedArrayUsingDescriptors:descriptors];
        
        [weakSelf columnsFromMediaItems:weakSelf.filteredItems
                                 genres:nil
                                artists:weakSelf.artists
                                 albums:weakSelf.albums
                                 tempos:weakSelf.tempos
                                   keys:weakSelf.keys
                                ratings:weakSelf.ratings
                                   tags:weakSelf.tags];

        dispatch_sync(dispatch_get_main_queue(), ^{
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

            [weakSelf.ratingsTable beginUpdates];
            [weakSelf.ratingsTable reloadData];
            [weakSelf.ratingsTable endUpdates];

            [weakSelf.tagsTable beginUpdates];
            [weakSelf.tagsTable reloadData];
            [weakSelf.tagsTable endUpdates];

            [weakSelf.songsTable beginUpdates];
            [weakSelf.songsTable reloadData];
            [weakSelf.songsTable endUpdates];

            NSIndexSet* zeroSet = [NSIndexSet indexSetWithIndex:0];
            self->_updatingArtists = YES;
            self->_updatingAlbums = YES;
            self->_updatingTempos = YES;
            self->_updatingKeys = YES;
            self->_updatingRatings = YES;
            self->_updatingTags = YES;
            [weakSelf.artistsTable selectRowIndexes:zeroSet byExtendingSelection:NO];
            [weakSelf.albumsTable selectRowIndexes:zeroSet byExtendingSelection:NO];
            [weakSelf.temposTable selectRowIndexes:zeroSet byExtendingSelection:NO];
            [weakSelf.keysTable selectRowIndexes:zeroSet byExtendingSelection:NO];
            [weakSelf.ratingsTable selectRowIndexes:zeroSet byExtendingSelection:NO];
            [weakSelf.tagsTable selectRowIndexes:zeroSet byExtendingSelection:NO];
            self->_updatingArtists = NO;
            self->_updatingAlbums = NO;
            self->_updatingTempos = NO;
            self->_updatingKeys = NO;
            self->_updatingRatings = NO;
            self->_updatingTags = NO;
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
    NSString* rating = nil;
    NSString* tag = nil;
    NSString* needle = nil;

    NSArray<NSSortDescriptor*>* descriptors = [_songsTable sortDescriptors];

    dispatch_async(_filterQueue, ^{
        weakSelf.filteredItems = [[weakSelf filterMediaItems:weakSelf.cachedLibrary
                                                      genre:genre
                                                     artist:artist
                                                      album:album
                                                      tempo:tempo
                                                        key:key
                                                      rating:rating
                                                         tag:tag
                                                      needle:needle] sortedArrayUsingDescriptors:descriptors];
    
        [weakSelf columnsFromMediaItems:weakSelf.filteredItems
                                 genres:nil
                                artists:nil
                                 albums:weakSelf.albums
                                 tempos:weakSelf.tempos
                                   keys:weakSelf.keys
                                ratings:weakSelf.ratings
                                   tags:weakSelf.tags];

        dispatch_sync(dispatch_get_main_queue(), ^{
            [weakSelf.albumsTable beginUpdates];
            [weakSelf.albumsTable reloadData];
            [weakSelf.albumsTable endUpdates];

            [weakSelf.temposTable beginUpdates];
            [weakSelf.temposTable reloadData];
            [weakSelf.temposTable endUpdates];

            [weakSelf.keysTable beginUpdates];
            [weakSelf.keysTable reloadData];
            [weakSelf.keysTable endUpdates];

            [weakSelf.ratingsTable beginUpdates];
            [weakSelf.ratingsTable reloadData];
            [weakSelf.ratingsTable endUpdates];

            [weakSelf.tagsTable beginUpdates];
            [weakSelf.tagsTable reloadData];
            [weakSelf.tagsTable endUpdates];

            [weakSelf.songsTable beginUpdates];
            [weakSelf.songsTable reloadData];
            [weakSelf.songsTable endUpdates];

            NSIndexSet* zeroSet = [NSIndexSet indexSetWithIndex:0];
            self->_updatingAlbums = YES;
            self->_updatingTempos = YES;
            self->_updatingKeys = YES;
            self->_updatingRatings = YES;
            self->_updatingTags = YES;
            [weakSelf.albumsTable selectRowIndexes:zeroSet byExtendingSelection:NO];
            [weakSelf.temposTable selectRowIndexes:zeroSet byExtendingSelection:NO];
            [weakSelf.keysTable selectRowIndexes:zeroSet byExtendingSelection:NO];
            [weakSelf.ratingsTable selectRowIndexes:zeroSet byExtendingSelection:NO];
            [weakSelf.tagsTable selectRowIndexes:zeroSet byExtendingSelection:NO];
            self->_updatingAlbums = NO;
            self->_updatingTempos = NO;
            self->_updatingKeys = NO;
            self->_updatingRatings = NO;
            self->_updatingTags = NO;
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
    NSString* rating = nil;
    NSString* tag = nil;
    NSString* needle = nil;

    BrowserController* __weak weakSelf = self;

    NSArray<NSSortDescriptor*>* descriptors = [_songsTable sortDescriptors];

    dispatch_async(_filterQueue, ^{
        weakSelf.filteredItems = [[weakSelf filterMediaItems:weakSelf.cachedLibrary
                                                       genre:genre
                                                      artist:artist
                                                       album:album
                                                       tempo:tempo
                                                         key:key
                                                      rating:rating
                                                         tag:tag
                                                      needle:needle] sortedArrayUsingDescriptors:descriptors];

        [weakSelf columnsFromMediaItems:weakSelf.filteredItems
                                 genres:nil
                                artists:nil
                                 albums:nil
                                 tempos:weakSelf.tempos
                                   keys:weakSelf.keys
                                ratings:weakSelf.ratings
                                   tags:weakSelf.tags];

        dispatch_sync(dispatch_get_main_queue(), ^{
            [weakSelf.temposTable beginUpdates];
            [weakSelf.temposTable reloadData];
            [weakSelf.temposTable endUpdates];

            [weakSelf.keysTable beginUpdates];
            [weakSelf.keysTable reloadData];
            [weakSelf.keysTable endUpdates];

            [weakSelf.ratingsTable beginUpdates];
            [weakSelf.ratingsTable reloadData];
            [weakSelf.ratingsTable endUpdates];

            [weakSelf.tagsTable beginUpdates];
            [weakSelf.tagsTable reloadData];
            [weakSelf.tagsTable endUpdates];

            [weakSelf.songsTable beginUpdates];
            [weakSelf.songsTable reloadData];
            [weakSelf.songsTable endUpdates];

            NSIndexSet* zeroSet = [NSIndexSet indexSetWithIndex:0];
            self->_updatingTempos = YES;
            self->_updatingKeys = YES;
            self->_updatingRatings = YES;
            self->_updatingTags = YES;
            [weakSelf.temposTable selectRowIndexes:zeroSet byExtendingSelection:NO];
            [weakSelf.keysTable selectRowIndexes:zeroSet byExtendingSelection:NO];
            [weakSelf.ratingsTable selectRowIndexes:zeroSet byExtendingSelection:NO];
            [weakSelf.tagsTable selectRowIndexes:zeroSet byExtendingSelection:NO];
            self->_updatingTempos = NO;
            self->_updatingKeys = NO;
            self->_updatingRatings = NO;
            self->_updatingTags = NO;
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
    NSString* rating = nil;
    NSString* tag = nil;
    NSString* needle = nil;

    BrowserController* __weak weakSelf = self;
    NSArray<NSSortDescriptor*>* descriptors = [_songsTable sortDescriptors];

    dispatch_async(_filterQueue, ^{
        weakSelf.filteredItems = [[weakSelf filterMediaItems:weakSelf.cachedLibrary
                                                       genre:genre
                                                      artist:artist
                                                       album:album
                                                       tempo:tempo
                                                         key:key
                                                      rating:rating
                                                         tag:tag
                                                      needle:needle] sortedArrayUsingDescriptors:descriptors];

        [weakSelf columnsFromMediaItems:weakSelf.filteredItems
                                 genres:nil
                                artists:nil
                                 albums:nil
                                 tempos:nil
                                   keys:weakSelf.keys
                                ratings:weakSelf.ratings
                                   tags:weakSelf.tags];

        dispatch_sync(dispatch_get_main_queue(), ^{
            [weakSelf.keysTable beginUpdates];
            [weakSelf.keysTable reloadData];
            [weakSelf.keysTable endUpdates];

            [weakSelf.ratingsTable beginUpdates];
            [weakSelf.ratingsTable reloadData];
            [weakSelf.ratingsTable endUpdates];

            [weakSelf.tagsTable beginUpdates];
            [weakSelf.tagsTable reloadData];
            [weakSelf.tagsTable endUpdates];

            [weakSelf.songsTable beginUpdates];
            [weakSelf.songsTable reloadData];
            [weakSelf.songsTable endUpdates];

            NSIndexSet* zeroSet = [NSIndexSet indexSetWithIndex:0];
            
            self->_updatingKeys = YES;
            self->_updatingRatings = YES;
            self->_updatingTags = YES;
            [weakSelf.keysTable selectRowIndexes:zeroSet byExtendingSelection:NO];
            [weakSelf.ratingsTable selectRowIndexes:zeroSet byExtendingSelection:NO];
            [weakSelf.tagsTable selectRowIndexes:zeroSet byExtendingSelection:NO];
            self->_updatingKeys = NO;
            self->_updatingRatings = NO;
            self->_updatingTags = NO;
        });
    });
    return;
}

-(void)keysTableSelectionDidChange:(NSInteger)row
{
    if (_updatingKeys) {
        return;
    }
    NSString* genre = _genresTable.selectedRow > 0 ? _genres[_genresTable.selectedRow] : nil;
    NSString* artist = _artistsTable.selectedRow > 0 ? _artists[_artistsTable.selectedRow] : nil;
    NSString* album = _albumsTable.selectedRow > 0 ? _albums[_albumsTable.selectedRow] : nil;
    NSString* tempo = _temposTable.selectedRow > 0 ? _tempos[_temposTable.selectedRow] : nil;
    NSString* key = row > 0 ? _keys[row] : nil;
    NSString* rating = nil;
    NSString* tag = nil;
    NSString* needle = nil;

    BrowserController* __weak weakSelf = self;
    NSArray<NSSortDescriptor*>* descriptors = [_songsTable sortDescriptors];

    dispatch_async(_filterQueue, ^{
        weakSelf.filteredItems = [[weakSelf filterMediaItems:weakSelf.cachedLibrary
                                                       genre:genre
                                                      artist:artist
                                                       album:album
                                                       tempo:tempo
                                                         key:key
                                                      rating:rating
                                                         tag:tag
                                                      needle:needle] sortedArrayUsingDescriptors:descriptors];

        dispatch_sync(dispatch_get_main_queue(), ^{
            [weakSelf.ratingsTable beginUpdates];
            [weakSelf.ratingsTable reloadData];
            [weakSelf.ratingsTable endUpdates];

            [weakSelf.tagsTable beginUpdates];
            [weakSelf.tagsTable reloadData];
            [weakSelf.tagsTable endUpdates];

            [weakSelf.songsTable beginUpdates];
            [weakSelf.songsTable reloadData];
            [weakSelf.songsTable endUpdates];

            NSIndexSet* zeroSet = [NSIndexSet indexSetWithIndex:0];
            
            self->_updatingRatings = YES;
            self->_updatingTags = YES;
            [weakSelf.ratingsTable selectRowIndexes:zeroSet byExtendingSelection:NO];
            [weakSelf.tagsTable selectRowIndexes:zeroSet byExtendingSelection:NO];
            self->_updatingRatings = NO;
            self->_updatingTags = NO;
        });
    });
}

-(void)ratingsTableSelectionDidChange:(NSInteger)row
{
    if (_updatingRatings) {
        return;
    }
    NSString* genre = _genresTable.selectedRow > 0 ? _genres[_genresTable.selectedRow] : nil;
    NSString* artist = _artistsTable.selectedRow > 0 ? _artists[_artistsTable.selectedRow] : nil;
    NSString* album = _albumsTable.selectedRow > 0 ? _albums[_albumsTable.selectedRow] : nil;
    NSString* tempo = _temposTable.selectedRow > 0 ? _tempos[_temposTable.selectedRow] : nil;
    NSString* key = _keysTable.selectedRow > 0 ? _keys[_keysTable.selectedRow] : nil;
    NSString* rating = row > 0 ? _ratings[row] : nil;
    NSString* tag = nil;
    NSString* needle = nil;

    BrowserController* __weak weakSelf = self;
    NSArray<NSSortDescriptor*>* descriptors = [_songsTable sortDescriptors];

    dispatch_async(_filterQueue, ^{
        weakSelf.filteredItems = [[weakSelf filterMediaItems:weakSelf.cachedLibrary
                                                       genre:genre
                                                      artist:artist
                                                       album:album
                                                       tempo:tempo
                                                         key:key
                                                      rating:rating
                                                         tag:tag
                                                      needle:needle] sortedArrayUsingDescriptors:descriptors];

        dispatch_sync(dispatch_get_main_queue(), ^{
            [weakSelf.tagsTable beginUpdates];
            [weakSelf.tagsTable reloadData];
            [weakSelf.tagsTable endUpdates];

            [weakSelf.songsTable beginUpdates];
            [weakSelf.songsTable reloadData];
            [weakSelf.songsTable endUpdates];

            NSIndexSet* zeroSet = [NSIndexSet indexSetWithIndex:0];
            
            self->_updatingTags = YES;
            [weakSelf.tagsTable selectRowIndexes:zeroSet byExtendingSelection:NO];
            self->_updatingTags = NO;
        });
    });
}

-(void)tagsTableSelectionDidChange:(NSInteger)row
{
    if (_updatingTags) {
        return;
    }
    NSString* genre = _genresTable.selectedRow > 0 ? _genres[_genresTable.selectedRow] : nil;
    NSString* artist = _artistsTable.selectedRow > 0 ? _artists[_artistsTable.selectedRow] : nil;
    NSString* album = _albumsTable.selectedRow > 0 ? _albums[_albumsTable.selectedRow] : nil;
    NSString* tempo = _temposTable.selectedRow > 0 ? _tempos[_temposTable.selectedRow] : nil;
    NSString* key = _keysTable.selectedRow > 0 ? _keys[_keysTable.selectedRow] : nil;
    NSString* rating = _ratingsTable.selectedRow > 0 ? _ratings[_ratingsTable.selectedRow] : nil;
    NSString* tag = row > 0 ? _tags[row] : nil;
    NSString* needle = nil;

    BrowserController* __weak weakSelf = self;
    NSArray<NSSortDescriptor*>* descriptors = [_songsTable sortDescriptors];

    dispatch_async(_filterQueue, ^{
        weakSelf.filteredItems = [[weakSelf filterMediaItems:weakSelf.cachedLibrary
                                                       genre:genre
                                                      artist:artist
                                                       album:album
                                                       tempo:tempo
                                                         key:key
                                                      rating:rating
                                                         tag:tag
                                                      needle:needle] sortedArrayUsingDescriptors:descriptors];

        dispatch_sync(dispatch_get_main_queue(), ^{
            [weakSelf.songsTable beginUpdates];
            [weakSelf.songsTable reloadData];
            [weakSelf.songsTable endUpdates];
        });
    });
}

-(void)doubleClickedSongsTableRow:(id)sender
{
    NSInteger row = [_songsTable clickedRow];
    if (row < 0) {
        return;
    }

    MediaMetaData* item = _filteredItems[row];
    NSURL* url = item.location;
    switch ([item.locationType intValue]) {
        case MediaMetaDataLocationTypeFile:    NSLog(@"that item is a file");  break;
        case MediaMetaDataLocationTypeURL:     NSLog(@"that item is a URL");   break;
        case MediaMetaDataLocationTypeRemote:  NSLog(@"that item is remote");  break;
        case MediaMetaDataLocationTypeUnknown:
        default:
            NSLog(@"that item (%p) is of unknown location type %@", item, item.locationType);
    }
    if (url != nil && _delegate != nil) {
        [self.delegate browseSelectedUrl:url meta:item];
    }
}

-(NSString*)formattedDuration:(NSTimeInterval)interval
{
    NSDateComponentsFormatter* formatter = [[NSDateComponentsFormatter alloc] init];
    formatter.allowedUnits = NSCalendarUnitHour | NSCalendarUnitMinute | NSCalendarUnitSecond;
    formatter.zeroFormattingBehavior = NSDateComponentsFormatterZeroFormattingBehaviorDropLeading;
    return [formatter stringFromTimeInterval:interval / 1000];
}

- (NSArray<NSString*>*)knownGenres
{
    if (_genres.count == 0) {
        return [NSArray array];
    }
    return [_genres subarrayWithRange:NSMakeRange(1, _genres.count - 1)];
}

- (NSArray<MediaMetaData*>*)selectedSongMetas
{
    __block NSMutableArray<MediaMetaData*>* metas = [NSMutableArray array];;
    [self.songsTable.selectedRowIndexes enumerateIndexesWithOptions:NSEnumerationReverse
                                                         usingBlock:^(NSUInteger idx, BOOL *stop) {
        MediaMetaData* meta = self.filteredItems[idx];
        [metas addObject:meta];
    }];
    if (metas.count == 0 && self.songsTable.clickedRow >= 0) {
        [metas addObject:self.filteredItems[self.songsTable.clickedRow]];
    }

    return metas;
}

- (NSString *)stringValueForRow:(NSInteger)row 
                    tableColumn:(NSTableColumn* _Nullable)tableColumn
                      tableView:(NSTableView* _Nonnull)tableView
{
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
        case VIEWTAG_RATING:
            assert(row < _ratings.count);
            string = _ratings[row];
            //string = [self starsWithRating:[[ _ratings[row] intValue]];
            break;
        case VIEWTAG_TAGS:
            assert(row < _tags.count);
            string = _tags[row];
            break;
        case VIEWTAG_SONGS:
            assert(row < _filteredItems.count);
            if ([tableColumn.identifier isEqualToString:@"TrackCell"]) {
                if ([_filteredItems[row].track intValue] > 0) {
                    string = [_filteredItems[row].track stringValue];
                }
            } else if ([tableColumn.identifier isEqualToString:@"TitleCell"]) {
                string = _filteredItems[row].title;
            } else if ([tableColumn.identifier isEqualToString:@"ArtistCell"]) {
                string = _filteredItems[row].artist;
            } else if ([tableColumn.identifier isEqualToString:@"AlbumCell"]) {
                string = _filteredItems[row].album;
            } else if ([tableColumn.identifier isEqualToString:@"TimeCell"]) {
                string = [self formattedDuration:[_filteredItems[row].duration floatValue]];
            } else if ([tableColumn.identifier isEqualToString:@"TempoCell"]) {
                if ([_filteredItems[row].tempo intValue] > 0) {
                    string = [_filteredItems[row].tempo stringValue];
                } else {
                    string = @"";
                }
            } else if ([tableColumn.identifier isEqualToString:@"KeyCell"]) {
                string = _filteredItems[row].key;
            } else if ([tableColumn.identifier isEqualToString:@"RatingCell"]) {
                string = _filteredItems[row].stars;
            } else if ([tableColumn.identifier isEqualToString:@"TagsCell"]) {
                string = _filteredItems[row].tags;
            } else if ([tableColumn.identifier isEqualToString:@"AddedCell"]) {
                string = [NSString BeautifulPast:_filteredItems[row].added];
            } else if ([tableColumn.identifier isEqualToString:@"GenreCell"]) {
                string = _filteredItems[row].genre;
            }
            break;
        default:
            string = @"<??? UNHANDLED TABLEVIEW ???>";
    }

    return string;
}

#pragma mark - Table View delegate

- (BOOL)tableView:(NSTableView*)tableView shouldTypeSelectForEvent:(NSEvent*)event withCurrentSearchString:(NSString*)searchString
{
    NSLog(@"current event: %@", event.debugDescription);
    NSLog(@"current search string: '%@'", searchString);
    return YES;
}

- (NSString*)tableView:(NSTableView*)tableView
typeSelectStringForTableColumn:(NSTableColumn*)tableColumn
                    row:(NSInteger)row
{
    return [self stringValueForRow:row tableColumn:tableColumn tableView:tableView];
}

-(void)tableViewSelectionDidChange:(NSNotification *)notification{

    NSTableView* tableView = [notification object];
    NSInteger row = [tableView selectedRow];
    if (row == -1) {
        return;
    }
    
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
        case VIEWTAG_RATING:
            [self ratingsTableSelectionDidChange:row];
        break;
        case VIEWTAG_TAGS:
            [self tagsTableSelectionDidChange:row];
        break;
        case VIEWTAG_SONGS:
            break;
    }
}

- (BOOL)tableView:(NSTableView*)tableView shouldSelectRow:(NSInteger)row
{
    // Cant select an invalid row.
    if (row == -1) {
        return NO;
    }

    switch(tableView.tag) {
        case VIEWTAG_GENRE:
            return YES;
        case VIEWTAG_ARTISTS:
            return YES;
        case VIEWTAG_ALBUMS:
            return YES;
        case VIEWTAG_TEMPO:
            return YES;
        case VIEWTAG_KEY:
            return YES;
        case VIEWTAG_SONGS:
            return YES;
        case VIEWTAG_RATING:
            return YES;
        case VIEWTAG_TAGS:
            return YES;
        default:
            return YES;
    }

    return YES;
}

- (void)tableView:(NSTableView*)tableView sortDescriptorsDidChange:(NSArray<NSSortDescriptor*>*)oldDescriptors
{
    NSArray<NSSortDescriptor*>* descriptors = [tableView sortDescriptors];
    _filteredItems = [_filteredItems sortedArrayUsingDescriptors:descriptors];
    [tableView reloadData];
}

- (void)tableView:(NSTableView *)tableView didAddRowView:(NSTableRowView *)rowView forRow:(NSInteger)row
{
    TableRowView* view = (TableRowView*)rowView;
    if (tableView.tag == VIEWTAG_SONGS) {
        if ([_filteredItems[row].location.absoluteString isEqualToString:_currentLocation.absoluteString]) {
            if (_delegate.playing) {
                [view setExtraState:kExtraStatePlaying];
            } else {
                [view setExtraState:kExtraStateActive];
            }
        } else {
            [view setExtraState:kExtraStateNormal];
        }
    }
}

- (NSTableRowView*)tableView:(NSTableView*)tableView rowViewForRow:(NSInteger)row
{
    static NSString* const kRowIdentifier = @"PlayEmTableRow";

    TableRowView* rowView = [tableView makeViewWithIdentifier:kRowIdentifier owner:self];
    if (rowView == nil) {
        rowView = [[TableRowView alloc] initWithFrame:NSMakeRect(0.0, 
                                                                 0.0,
                                                                 tableView.bounds.size.width,
                                                                 tableView.rowHeight)];
        rowView.identifier = kRowIdentifier;
    }
    rowView.nextKeyView = tableView.nextKeyView;
    return rowView;
}
  
- (NSView*)tableView:(NSTableView*)tableView 
  viewForTableColumn:(NSTableColumn*)tableColumn
                 row:(NSInteger)row
{
    switch(tableView.tag) {
        case VIEWTAG_GENRE:
        case VIEWTAG_ARTISTS:
        case VIEWTAG_ALBUMS:
        case VIEWTAG_TEMPO:
        case VIEWTAG_KEY:
        case VIEWTAG_RATING:
        case VIEWTAG_TAGS:
        case VIEWTAG_SONGS:
            break;
        default:
            assert(NO);
    }

    TableCellView* result = [tableView makeViewWithIdentifier:tableColumn.identifier owner:self];
    
    if (result == nil) {
        result = [[TableCellView alloc] initWithFrame:NSMakeRect(0.0,
                                                                 0.0,
                                                                 tableColumn.width,
                                                                 tableView.rowHeight )];
        NSString* cellName = tableColumn.identifier;
        if (tableView.tag == VIEWTAG_SONGS) {
            if ([cellName isEqualToString:@"TrackCell"]) {
                [result.textField setAlignment:NSTextAlignmentRight];
            } else if ([cellName isEqualToString:@"TimeCell"]) {
                [result.textField setAlignment:NSTextAlignmentRight];
            } else if ([cellName isEqualToString:@"TempoCell"]) {
                [result.textField setAlignment:NSTextAlignmentRight];
            }
            //[result addConstraint: [NSLayoutConstraint constraintWithItem:result attribute:NSLayoutAttributeLeft relatedBy:NSLayoutRelationEqual toItem:tableView.enclosingScrollView attribute:NSLayoutAttributeLeft multiplier:1.0 constant:0.0]];
        }
        result.identifier = cellName;
    }

    NSString* s = [self stringValueForRow:row tableColumn:tableColumn tableView:tableView];
    if (s == nil) {
        s = @"";
    }
    result.textField.stringValue = s;
    result.nextKeyView = tableView.nextKeyView;

    return result;
}

#pragma mark - Table View data source

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
        case VIEWTAG_RATING:
            return _ratings.count;
        case VIEWTAG_TAGS:
            return _tags.count;
        case VIEWTAG_SONGS:
            return _filteredItems.count;
        default:
            return 0;
    }
    return 0;
}

#pragma mark - Search Field

- (void)controlTextDidChange:(NSNotification *)obj
{
    [self updatedNeedle];
}

- (void)searchFieldDidStartSearching:(NSSearchField*)sender
{
    [self updatedNeedle];
}

- (void)searchFieldDidEndSearching:(NSSearchField*)sender
{
    [self.delegate closeFilter];
    [self updatedNeedle];
}

@end
