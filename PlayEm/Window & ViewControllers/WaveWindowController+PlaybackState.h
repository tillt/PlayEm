//
//  WaveWindowController+PlaybackState.h
//  PlayEm
//
//  Created by Till Toenshoff on 2026-01-16.
//  Copyright (c) 2026 Till Toenshoff. All rights reserved.
//

#import "WaveWindowController.h"

@interface WaveWindowController (PlaybackState)

- (void)AudioControllerPlaybackStateChange:(NSNotification*)notification;
- (void)setNowPlayingWithMeta:(MediaMetaData*)meta;
- (void)updateRemotePosition;

@end
