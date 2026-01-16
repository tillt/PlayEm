//
//  WaveWindowController+RemoteCommands.m
//  PlayEm
//
//  Created by Till Toenshoff on 2026-01-16.
//  Copyright (c) 2026 Till Toenshoff. All rights reserved.
//

#import "WaveWindowController+RemoteCommands.h"

#import <MediaPlayer/MediaPlayer.h>

#import "AudioController.h"

@interface WaveWindowController ()
- (void)seekToTime:(NSTimeInterval)time;
- (IBAction)playNext:(id)sender;
- (IBAction)playPrevious:(id)sender;
@end

@implementation WaveWindowController (RemoteCommands)

- (NSArray*)remoteCommands
{
    MPRemoteCommandCenter* cc = [MPRemoteCommandCenter sharedCommandCenter];
    return @[
        cc.playCommand,
        cc.pauseCommand,
        cc.stopCommand,
        cc.togglePlayPauseCommand,
        cc.nextTrackCommand,
        cc.previousTrackCommand,
        cc.skipForwardCommand,
        cc.skipBackwardCommand,
        cc.changePlaybackPositionCommand,
    ];
}

- (MPRemoteCommandHandlerStatus)remoteCommandEvent:(MPRemoteCommandEvent*)event
{
    MPRemoteCommandCenter* cc = [MPRemoteCommandCenter sharedCommandCenter];
    if (event.command == cc.playCommand) {
        [self.audioController play];
        return MPRemoteCommandHandlerStatusSuccess;
    }
    if (event.command == cc.pauseCommand) {
        [self.audioController pause];
        return MPRemoteCommandHandlerStatusSuccess;
    }
    if (event.command == cc.togglePlayPauseCommand) {
        [self.audioController togglePause];
        return MPRemoteCommandHandlerStatusSuccess;
    }
    if (event.command == cc.changePlaybackPositionCommand) {
        MPChangePlaybackPositionCommandEvent* positionEvent = (MPChangePlaybackPositionCommandEvent*) event;
        [self seekToTime:positionEvent.positionTime + 1];
        return MPRemoteCommandHandlerStatusSuccess;
    }
    if (event.command == cc.nextTrackCommand) {
        [self playNext:self];
        return MPRemoteCommandHandlerStatusSuccess;
    }
    if (event.command == cc.previousTrackCommand) {
        [self playPrevious:self];
        return MPRemoteCommandHandlerStatusSuccess;
    }
    if (event.command == cc.skipForwardCommand) {
        [self seekToTime:self.audioController.currentTime + 10.0];
        return MPRemoteCommandHandlerStatusSuccess;
    }
    if (event.command == cc.skipBackwardCommand) {
        [self seekToTime:self.audioController.currentTime - 10.0];
        return MPRemoteCommandHandlerStatusSuccess;
    }

    NSLog(@"%s was not able to handle remote control event '%s'", __PRETTY_FUNCTION__, [event.description UTF8String]);

    return MPRemoteCommandHandlerStatusCommandFailed;
}

/// Adds this controller as a target for remote commands as issued by
/// the media menu and keys.
- (void)subscribeToRemoteCommands
{
    MPRemoteCommandCenter* commandCenter = [MPRemoteCommandCenter sharedCommandCenter];

    commandCenter.ratingCommand.enabled = NO;
    commandCenter.likeCommand.enabled = NO;
    commandCenter.dislikeCommand.enabled = NO;
    commandCenter.bookmarkCommand.enabled = NO;
    commandCenter.enableLanguageOptionCommand.enabled = NO;
    commandCenter.disableLanguageOptionCommand.enabled = NO;
    commandCenter.seekForwardCommand.enabled = NO;
    commandCenter.seekBackwardCommand.enabled = NO;
    commandCenter.skipForwardCommand.preferredIntervals = @[ @(10.0) ];
    commandCenter.skipBackwardCommand.preferredIntervals = @[ @(10.0) ];
    for (MPRemoteCommand* command in [self remoteCommands]) {
        [command addTarget:self action:@selector(remoteCommandEvent:)];
    }
}

- (void)unsubscribeFromRemoteCommands
{
    [MPNowPlayingInfoCenter defaultCenter].nowPlayingInfo = nil;

    for (MPRemoteCommand* command in [self remoteCommands]) {
        [command removeTarget:self];
    }
}

@end
