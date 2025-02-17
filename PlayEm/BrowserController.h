//
//  BrowserController.h
//  PlayEm
//
//  Created by Till Toenshoff on 13.09.20.
//  Copyright © 2020 Till Toenshoff. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import <Foundation/Foundation.h>
#import <Quartz/Quartz.h>

#import "LoadState.h"

NS_ASSUME_NONNULL_BEGIN

#define VIEWTAG_GENRE    42
#define VIEWTAG_ARTISTS  43
#define VIEWTAG_ALBUMS   44
#define VIEWTAG_TEMPO    45
#define VIEWTAG_KEY      46
#define VIEWTAG_RATING   47
#define VIEWTAG_TAGS     48
#define VIEWTAG_SONGS    50

extern NSString* const kSongsColTrackNumber;
extern NSString* const kSongsColTitle;
extern NSString* const kSongsColArtist;
extern NSString* const kSongsColAlbum;
extern NSString* const kSongsColTime;
extern NSString* const kSongsColTempo;
extern NSString* const kSongsColKey;
extern NSString* const kSongsColRating;
extern NSString* const kSongsColTags;
extern NSString* const kSongsColAdded;
extern NSString* const kSongsColGenre;


@class MediaMetaData;

@protocol BrowserControllerDelegate <NSObject>
- (MediaMetaData*)currentSongMeta;
- (BOOL)playing;
- (void)browseSelectedUrl:(NSURL*)url meta:(MediaMetaData*)meta;
- (void)loadLibraryState:(LoadState)state;
- (void)loadLibraryState:(LoadState)state value:(double)value;
- (void)addToPlaylistNext:(MediaMetaData*)meta;
- (void)addToPlaylistLater:(MediaMetaData*)meta;
- (void)updateSongsCount:(size_t)songs;
- (void)showInfoForMetas:(NSArray<MediaMetaData*>*)metas;
@end

@interface BrowserController : NSResponder <NSTableViewDelegate, NSTableViewDataSource, CAAnimationDelegate>

@property (nonatomic, weak) id <BrowserControllerDelegate> delegate;

- (id)initWithGenresTable:(NSTableView*)genresTable
             artistsTable:(NSTableView*)artistsTable
              albumsTable:(NSTableView*)albumsTable
              temposTable:(NSTableView*)temposTable
               songsTable:(NSTableView*)songsTable
                keysTable:(NSTableView*)keysTable
             ratingsTable:(NSTableView*)ratingsTable
              tagsTable:(NSTableView*)tagsTable
                 delegate:(id <BrowserControllerDelegate>)delegate;
- (void)loadITunesLibrary;
- (void)reloadData;
- (void)setPlaying:(BOOL)playing;
- (void)setCurrentMeta:(MediaMetaData*)meta;
- (void)metaChangedForMeta:(MediaMetaData *)meta updatedMeta:(MediaMetaData *)updatedMeta;
- (NSArray<NSString*>*)knownGenres;
- (IBAction)playNextInPlaylist:(id)sender;
- (IBAction)playLaterInPlaylist:(id)sender;
- (IBAction)showInFinder:(id)sender;
- (IBAction)showInfoForCurrentSong:(id)sender;
- (NSUInteger)currentSongRow;
- (MediaMetaData* _Nullable)nextSong;
- (NSArray<MediaMetaData*>*)selectedSongMetas;

@end

NS_ASSUME_NONNULL_END
