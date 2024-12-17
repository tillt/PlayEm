//
//  IdentificationActiveView.h
//  PlayEm
//
//  Created by Till Toenshoff on 10.06.24.
//  Copyright © 2024 Till Toenshoff. All rights reserved.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface IdentificationCoverView : NSView
@property (nonatomic, strong) NSImage* image;
@property (nonatomic, assign) float overlayIntensity;
@property (nonatomic, assign) BOOL sepiaForSecondImageLayer;
@property (nonatomic, assign) float secondImageLayerOpacity;


- (void)startAnimating;
- (void)stopAnimating;
- (void)pauseAnimating;

@end

NS_ASSUME_NONNULL_END
