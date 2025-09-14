//
//  PlaylistController.h
//  PlayEm
//
//  Created by Till Toenshoff on 31.10.22.
//  Copyright © 2022 Till Toenshoff. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import <Foundation/Foundation.h>
#import "MediaMetaData.h"

NS_ASSUME_NONNULL_BEGIN

@protocol PlaylistControllerDelegate <NSObject>

- (void)browseSelectedUrl:(NSURL*)url meta:(MediaMetaData*)meta;

@end


@interface PlaylistController : NSResponder <NSTableViewDelegate, NSTableViewDataSource>

@property (nonatomic, weak) id <PlaylistControllerDelegate> delegate;
@property (nonatomic, strong) MediaMetaData* current;
@property (nonatomic, assign) BOOL playing;

- (id)initWithPlaylistTable:(NSTableView*)table
                   delegate:(id<PlaylistControllerDelegate>)delegate;

- (void)addLater:(MediaMetaData*)item;
- (void)addNext:(MediaMetaData*)item;
- (void)playedMeta:(MediaMetaData*)item;

- (MediaMetaData* _Nullable)nextItem;
- (MediaMetaData* _Nullable)itemAtIndex:(NSUInteger)index;

- (NSMenu*)menu;

@end

NS_ASSUME_NONNULL_END
