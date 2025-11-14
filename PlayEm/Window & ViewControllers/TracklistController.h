//
//  TracklistController.h
//  PlayEm
//
//  Created by Till Toenshoff on 9/27/25.
//  Copyright © 2025 Till Toenshoff. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import <Foundation/Foundation.h>
#import "MediaMetaData.h"

NS_ASSUME_NONNULL_BEGIN

@class IdentifiedTrack;
@class AudioController;

@protocol TracklistControllerDelegate <NSObject>

//- (void)browseSelectedUrl:(NSURL*)url meta:(MediaMetaData*)meta;

- (NSString*)stringFromFrame:(unsigned long long)frame;

- (void)playAtFrame:(unsigned long long)frame;
- (void)reloadTracks;

@end

@interface TracklistController : NSResponder <NSTableViewDelegate, NSTableViewDataSource>

@property (nonatomic, weak) id <TracklistControllerDelegate> delegate;
@property (nonatomic, weak) MediaMetaData* current;
@property (nonatomic, assign) unsigned long long currentFrame;

- (id)initWithTracklistTable:(NSTableView*)table
                   delegate:(id<TracklistControllerDelegate>)delegate;

- (void)addTrack:(IdentifiedTrack*)track;
- (NSMenu*)menu;

@end

NS_ASSUME_NONNULL_END
