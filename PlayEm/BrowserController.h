//
//  BrowserController.h
//  PlayEm
//
//  Created by Till Toenshoff on 13.09.20.
//  Copyright © 2020 Till Toenshoff. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import <Foundation/Foundation.h>
#import "LoadState.h"

NS_ASSUME_NONNULL_BEGIN

#define VIEWTAG_GENRE    42
#define VIEWTAG_ARTISTS  43
#define VIEWTAG_ALBUMS   44
#define VIEWTAG_TEMPO    45
#define VIEWTAG_KEY      46
#define VIEWTAG_FILTERED 50

@class MediaMetaData;

@protocol BrowserControllerDelegate <NSObject>
- (void)browseSelectedUrl:(NSURL*)url meta:(MediaMetaData*)meta;
- (void)loadLibraryState:(LoadState)state;
- (void)loadLibraryState:(LoadState)state value:(double)value;
- (void)addToPlaylistNext:(MediaMetaData*)meta;
- (void)addToPlaylistLater:(MediaMetaData*)meta;
- (void)updateSongsCount:(size_t)songs;
@end

@interface BrowserController : NSResponder <NSTableViewDelegate, NSTableViewDataSource>
@property (nonatomic, weak) id <BrowserControllerDelegate> delegate;

- (id)initWithGenresTable:(NSTableView*)genresTable
             artistsTable:(NSTableView*)artistsTable
              albumsTable:(NSTableView*)albumsTable
              temposTable:(NSTableView*)temposTable
               songsTable:(NSTableView*)songsTable
                 delegate:(id <BrowserControllerDelegate>)delegate;
- (void)loadITunesLibrary;
- (void)reloadData;
- (void)metaChangedForMeta:(MediaMetaData *)meta updatedMeta:(MediaMetaData *)updatedMeta;
- (NSArray<NSString*>*)knownGenres;
- (IBAction)playNext:(id)sender;
- (IBAction)playLater:(id)sender;
- (IBAction)showInFinder:(id)sender;
- (NSArray<MediaMetaData*>*)selectedSongMetas;

@end

NS_ASSUME_NONNULL_END
