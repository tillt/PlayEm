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
@class MarkLayerController;

@interface TiledScrollView : NSScrollView

@property (assign, nonatomic) BOOL horizontal;
@property (weak, nonatomic) MarkLayerController*  markLayerController;
@property (assign, nonatomic) NSSize tileSize;

@property (strong, nonatomic) CALayer* shinyLayer;
@property (strong, nonatomic) CALayer* normalLayer;

- (NSMutableArray*)reusableViews;

@end


NS_ASSUME_NONNULL_END
