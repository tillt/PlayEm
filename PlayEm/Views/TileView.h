//
//  TileView.h
//  PlayEm
//
//  Created by Till Toenshoff on 8/23/25.
//  Copyright © 2025 Till Toenshoff. All rights reserved.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface TileView : NSView

- (nonnull instancetype)initWithFrame:(CGRect)frameRect
                        waveLayerDelegate:(id<CALayerDelegate>)layerDelegate;

@property (readwrite, nonatomic, assign) NSInteger tileTag;

@property (readonly, nonatomic, strong) CALayer* beatLayer;
@property (readonly, nonatomic, strong) CALayer* waveLayer;
@property (readonly, nonatomic, strong) CALayer* markLayer;

@end


NS_ASSUME_NONNULL_END
