//
//  PhosphorChaserView.m
//  PlayEm
//
//  Retro phosphor spinner with CI accumulator smear (no Metal).
//
//  Created by Till Toenshoff on 08.06.24.
//  Copyright © 2024 Till Toenshoff. All rights reserved.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface PhosphorChaserView : NSView
/// When active, the dot chases around the ring; when inactive, animation stops and the view hides itself.
@property (nonatomic, assign, getter=isActive) BOOL active;
/// Seconds per full revolution. Defaults to 1.2s.
@property (nonatomic, assign) NSTimeInterval period;
/// When YES, the chaser expects external tick calls (e.g. from a shared CADisplayLink) and will not start its own timer.
@property (nonatomic, assign) BOOL externallyDriven;

- (void)tickWithTimestamp:(CFTimeInterval)timestamp;

- (void)startAnimating;
- (void)stopAnimating;
@end

NS_ASSUME_NONNULL_END
