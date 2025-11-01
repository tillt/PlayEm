//
//  TileView.h
//  PlayEm
//
//  Created by Till Toenshoff on 8/23/25.
//  Copyright © 2025 Till Toenshoff. All rights reserved.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@protocol WaveLayerDelegate;
@protocol BeatLayerDelegate;

@interface TileView : NSView

- (nonnull instancetype)initWithFrame:(CGRect)frameRect layerDelegate:(id<WaveLayerDelegate>)layerDelegate overlayLayerDelegate:(id<BeatLayerDelegate>)overlayLayerDelegate;

@property (readwrite, nonatomic, assign) NSInteger tileTag;
@property (readwrite, nonatomic, strong) CALayer* overlayLayer;

@end


NS_ASSUME_NONNULL_END
