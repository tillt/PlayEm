//
//  CALayer+PauseAnimations.h
//  PlayEm
//
//  Created by Till Toenshoff on 11/10/24.
//  Copyright © 2024 Till Toenshoff. All rights reserved.
//

#import <QuartzCore/QuartzCore.h>

NS_ASSUME_NONNULL_BEGIN

@interface CALayer (PauseAnimations)

- (void)resumeAnimating;
- (void)pauseAnimating;

@end

NS_ASSUME_NONNULL_END
