//
//  TotalWaveView.h
//  PlayEm
//
//  Created by Till Toenshoff on 14.03.21.
//  Copyright © 2021 Till Toenshoff. All rights reserved.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

extern const CGFloat kTotalWaveViewTileWidth;

@interface TotalWaveView : NSView

@property (weak, nonatomic) IBOutlet id<CALayerDelegate> layerDelegate;
@property (assign, nonatomic) unsigned long long frames;
@property (assign, nonatomic) unsigned long long currentFrame;


//- (void)updateDuration:(NSTimeInterval)duration;
- (void)refresh;
- (void)resize;

@end

NS_ASSUME_NONNULL_END
