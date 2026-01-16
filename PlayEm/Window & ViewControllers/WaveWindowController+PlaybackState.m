//
//  WaveWindowController+PlaybackState.m
//  PlayEm
//
//  Created by Till Toenshoff on 2026-01-16.
//  Copyright (c) 2026 Till Toenshoff. All rights reserved.
//

#import "WaveWindowController+PlaybackState.h"

#import <MediaPlayer/MediaPlayer.h>

#import "AudioController.h"
#import "BrowserController.h"
#import "ControlPanelController.h"
#import "MediaMetaData.h"
#import "PlaylistController.h"
#import "ScopeRenderer.h"
#import "../Views/SymbolButton.h"

@interface WaveWindowController ()
@property (nonatomic, strong) ControlPanelController* controlPanelController;
@property (nonatomic, strong) MediaMetaData* meta;
@property (nonatomic, strong) PlaylistController* playlist;
@property (nonatomic, strong) ScopeRenderer* renderer;

- (void)startVisuals;
- (BOOL)lockScreen;
- (BOOL)unlockScreen;
- (void)setPlaybackActive:(BOOL)active;
- (void)setPlaybackState:(MPNowPlayingPlaybackState)state;
- (void)setNowPlayingWithMeta:(MediaMetaData*)meta;
- (IBAction)playNext:(id)sender;
@end

@implementation WaveWindowController (PlaybackState)

- (void)AudioControllerPlaybackStateChange:(NSNotification*)notification
{
    NSString* state = notification.object;
    if ([state isEqualToString:kPlaybackStateStarted]) {
        [self audioControllerPlaybackStarted];
    } else if ([state isEqualToString:kPlaybackStatePlaying]) {
        [self audioControllerPlaybackPlaying];
    } else if ([state isEqualToString:kPlaybackStatePaused]) {
        [self audioControllerPlaybackPaused];
    } else if ([state isEqualToString:kPlaybackStateEnded]) {
        [self audioControllerPlaybackEnded];
    }
}

- (void)setPlaybackState:(MPNowPlayingPlaybackState)state
{
    MPNowPlayingInfoCenter* center = [MPNowPlayingInfoCenter defaultCenter];
    center.playbackState = state;
}

- (void)setNowPlayingWithMeta:(MediaMetaData*)meta
{
    NSMutableDictionary* songInfo = [[NSMutableDictionary alloc] init];
    [songInfo setObject:meta.title == nil ? @"" : meta.title forKey:MPMediaItemPropertyTitle];
    [songInfo setObject:meta.artist == nil ? @"" : meta.artist forKey:MPMediaItemPropertyArtist];
    [songInfo setObject:meta.album == nil ? @"" : meta.album forKey:MPMediaItemPropertyAlbumTitle];
    if (meta.track != nil) {
        [songInfo setObject:meta.track forKey:MPMediaItemPropertyAlbumTrackNumber];
    }
    if (meta.tracks != nil) {
        [songInfo setObject:meta.tracks forKey:MPMediaItemPropertyAlbumTrackCount];
    }
    if (meta.genre != nil) {
        [songInfo setObject:meta.genre forKey:MPMediaItemPropertyGenre];
    }
    if (meta.year != nil) {
        [songInfo setObject:meta.year forKey:MPMediaItemPropertyReleaseDate];
    }
    NSImage* artworkImage = [meta imageFromArtwork];
    MPMediaItemArtwork* artwork = [[MPMediaItemArtwork alloc] initWithBoundsSize:artworkImage.size
                                                                  requestHandler:^(CGSize size) {
                                                                      return artworkImage;
                                                                  }];
    [songInfo setObject:artwork forKey:MPMediaItemPropertyArtwork];

    [songInfo setObject:@(self.audioController.expectedDuration) forKey:MPMediaItemPropertyPlaybackDuration];
    [songInfo setObject:@(self.audioController.currentTime) forKey:MPNowPlayingInfoPropertyElapsedPlaybackTime];
    [songInfo setObject:@(self.audioController.tempoShift) forKey:MPNowPlayingInfoPropertyPlaybackRate];

    MPNowPlayingInfoCenter* center = [MPNowPlayingInfoCenter defaultCenter];
    center.nowPlayingInfo = songInfo;
}

- (void)updateRemotePosition
{
    NSMutableDictionary* songInfo = [NSMutableDictionary dictionaryWithDictionary:[[MPNowPlayingInfoCenter defaultCenter] nowPlayingInfo]];
    [songInfo setObject:@(self.audioController.expectedDuration) forKey:MPMediaItemPropertyPlaybackDuration];
    [songInfo setObject:@(self.audioController.currentTime) forKey:MPNowPlayingInfoPropertyElapsedPlaybackTime];
    [[MPNowPlayingInfoCenter defaultCenter] setNowPlayingInfo:songInfo];
}

- (void)audioControllerPlaybackStarted
{
    NSLog(@"audioControllerPlaybackStarted");
    [self startVisuals];
    [self.playlist playedMeta:self.meta];
}

- (void)audioControllerPlaybackPlaying
{
    NSLog(@"audioControllerPlaybackPlaying");
    // Make state obvious to user.
    [self setPlaybackActive:YES];
    [self.playlist setPlaying:YES];
    [self.browser setNowPlayingWithMeta:self.meta];
    [self setNowPlayingWithMeta:self.meta];
    [self setPlaybackState:MPNowPlayingPlaybackStatePlaying];
    [self updateRemotePosition];
    [self lockScreen];
}

- (void)audioControllerPlaybackPaused
{
    NSLog(@"audioControllerPlaybackPaused");
    // Make state obvious to user.
    [self setPlaybackActive:NO];
    [self.playlist setPlaying:NO];
    [self.browser setPlaying:NO];
    [self setNowPlayingWithMeta:self.meta];
    [self setPlaybackState:MPNowPlayingPlaybackStatePaused];
    [self updateRemotePosition];
    [self unlockScreen];
}

- (void)audioControllerPlaybackEnded
{
    NSLog(@"audioControllerPlaybackEnded");
    // Make state obvious to user.
    [self setPlaybackActive:NO];
    [self.playlist setPlaying:NO];
    [self.browser setPlaying:NO];
    [self setNowPlayingWithMeta:self.meta];
    [self setPlaybackState:MPNowPlayingPlaybackStateStopped];
    [self updateRemotePosition];
    [self unlockScreen];

    // Stop the scope rendering.
    [self.renderer stop:self.scopeView];

    if (self.controlPanelController.loop.state == NSControlStateValueOn) {
        [self.audioController play];
        return;
    }

    [self playNext:self];
}

@end
