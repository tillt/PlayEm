//
//  CALayer+PauseAnimations.h
//  PlayEm
//
//  Created by Till Toenshoff on 11/10/24.
//  Copyright © 2024 Till Toenshoff. All rights reserved.
//

#import "CALayer+PauseAnimations.h"

@implementation CALayer (PauseAnimations)

- (void)resumeAnimating
{
    CFTimeInterval pausedTime = [self timeOffset];
    self.speed = 1.0;
    self.timeOffset = 0.0;
    self.beginTime = 0.0;
    CFTimeInterval timeSincePause = [self convertTime:CACurrentMediaTime() fromLayer:nil] - pausedTime;
    self.beginTime = timeSincePause;
}

- (void)pauseAnimating
{
    CFTimeInterval pausedTime = [self convertTime:CACurrentMediaTime() fromLayer:nil];
    self.speed = 0.0;
    self.timeOffset = pausedTime;
}

@end
