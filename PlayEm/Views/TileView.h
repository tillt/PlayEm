//
//  TileView.h
//  PlayEm
//
//  Created by Till Toenshoff on 8/23/25.
//  Copyright © 2025 Till Toenshoff. All rights reserved.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@class WaveLayerDelegate;
@class BeatLayerDelegate;

@interface TileView : NSView

- (nonnull instancetype)initWithFrame:(CGRect)frameRect
                        waveLayerDelegate:(id<CALayerDelegate>)layerDelegate;

@property (readwrite, nonatomic, assign) NSInteger tileTag;

@property (readwrite, nonatomic, strong) CALayer* beatLayer;
@property (readwrite, nonatomic, strong) CALayer* waveLayer;
@property (readwrite, nonatomic, strong) CALayer* markLayer;

@end


NS_ASSUME_NONNULL_END
