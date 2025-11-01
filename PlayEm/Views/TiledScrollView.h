//
//  TiledScrollView.h
//  PlayEm
//
//  Created by Till Toenshoff on 05.12.20.
//  Copyright © 2020 Till Toenshoff. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import <QuartzCore/QuartzCore.h>
#import "WaveView.h"

NS_ASSUME_NONNULL_BEGIN

extern const CGFloat kDirectWaveViewTileWidth;

@class VisualSample;
@class TileView;

@interface TiledScrollView : NSScrollView

@property (assign, nonatomic) BOOL horizontal;
@property (weak, nonatomic) id<CALayerDelegate> layerDelegate;
@property (weak, nonatomic) id<CALayerDelegate> beatLayerDelegate;
@property (assign, nonatomic) NSSize tileSize;

- (NSMutableArray*)reusableViews;

@end


NS_ASSUME_NONNULL_END
