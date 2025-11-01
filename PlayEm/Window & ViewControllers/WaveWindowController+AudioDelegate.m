
#import "WaveWindowController.h"
#import "WaveWindowController+AudioDelegate.h"

@implementation WaveWindowController(AudioDelegate)

- (void)startVisuals
{
    // Start beats.
    [self beatEffectStart];

    // Start the scope renderer.
    [_renderer play:_audioController visual:_visualSample scope:_scopeView];

    [self setupDisplayLink];
}

- (void)audioControllerPlaybackStarted
{
    NSLog(@"audioControllerPlaybackStarted");
    [self startVisuals];
    [_playlist playedMeta:_meta];
}

- (void)audioControllerPlaybackPlaying
{
    NSLog(@"audioControllerPlaybackPlaying");
    // Make state obvious to user.
    [self setPlaybackActive:YES];

    [_playlist setPlaying:YES];
    [_browser setPlaying:YES];

    [self setNowPlayingWithMeta:_meta];
    MPNowPlayingInfoCenter* center = [MPNowPlayingInfoCenter defaultCenter];
    center.playbackState = MPNowPlayingPlaybackStatePlaying;
    [self updateRemotePosition];

    [self lockScreen];
}

- (void)audioControllerPlaybackPaused
{
    NSLog(@"audioControllerPlaybackPaused");
    // Make state obvious to user.
    [self setPlaybackActive:NO];
    [_playlist setPlaying:NO];
    [_browser setPlaying:NO];

    [self setNowPlayingWithMeta:_meta];
    MPNowPlayingInfoCenter* center = [MPNowPlayingInfoCenter defaultCenter];
    center.playbackState = MPNowPlayingPlaybackStatePaused;
    [self updateRemotePosition];

    [self unlockScreen];
}

- (void)audioControllerPlaybackEnded
{
    NSLog(@"audioControllerPlaybackEnded");
    // Make state obvious to user.
    [self setPlaybackActive:NO];
    [_playlist setPlaying:NO];
    [_browser setPlaying:NO];

    [self setNowPlayingWithMeta:_meta];
    MPNowPlayingInfoCenter* center = [MPNowPlayingInfoCenter defaultCenter];
    center.playbackState = MPNowPlayingPlaybackStateStopped;
    [self updateRemotePosition];

    [self unlockScreen];

    // Stop the scope rendering.
    [_renderer stop:_scopeView];

    if (_controlPanelController.loop.state == NSControlStateValueOn) {
        [_audioController play];
        return;
    }
    
    [self playNext:self];
}

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

@end
