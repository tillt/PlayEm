//
//  TiledWaveView.h
//  PlayEm
//
//  Created by Till Toenshoff on 02.05.20.
//  Copyright © 2020 Till Toenshoff. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@class CATiledLayer;

NS_ASSUME_NONNULL_BEGIN

@interface TiledWaveView : NSView <CALayerDelegate>
@property (strong, nonatomic) CATiledLayer *waveImageLayer;
@property (assign, nonatomic) CGFloat zoomLevel;
@end

NS_ASSUME_NONNULL_END
