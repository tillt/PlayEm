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

@class TimedMediaMetaData;
@class AudioController;

extern NSString * const kTracklistControllerChangedActiveTrackNotification;

@protocol TracklistControllerDelegate <NSObject>

- (NSString*)standardStringFromFrame:(unsigned long long)frame;

- (NSString*)stringFromFrame:(unsigned long long)frame;
- (NSURL*)linkedURL;

- (void)playAtFrame:(unsigned long long)frame;
- (void)updatedTracks;

@end

@interface TracklistController : NSResponder <NSTableViewDelegate, NSTableViewDataSource>

@property (nonatomic, weak) id <TracklistControllerDelegate> delegate;
@property (nonatomic, weak) MediaMetaData* current;
@property (nonatomic, assign) unsigned long long currentFrame;
@property (nonatomic, readonly) TimedMediaMetaData* currentTrack;

- (id)initWithTracklistTable:(NSTableView*)table
                   delegate:(id<TracklistControllerDelegate>)delegate;

- (void)addTrack:(TimedMediaMetaData*)track;
- (void)moveTrackAtFrame:(unsigned long long)oldFrame frame:(unsigned long long)newFrame;

- (NSMenu*)menu;
- (IBAction)exportTracklist:(id)sender;

@end

NS_ASSUME_NONNULL_END
