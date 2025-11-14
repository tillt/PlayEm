//
//  MarkLayerController.h
//  PlayEm
//
//  Created by Till Toenshoff on 11/9/25.
//  Copyright © 2025 Till Toenshoff. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <Cocoa/Cocoa.h>
#import <QuartzCore/QuartzCore.h>
#import "../Sample/BeatEvent.h"

NS_ASSUME_NONNULL_BEGIN

@class BeatTrackedSample;
@class WaveView;
@class TrackList;
@class TileView;
@class VisualSample;

typedef CGFloat (^OffsetBlock) (void);
typedef CGFloat (^TotalWidthBlock) (void);

@interface MarkLayerController : NSObject <CALayerDelegate>

@property (strong, nonatomic) WaveView* waveView;

@property (weak, nonatomic, nullable) TrackList* trackList;
@property (weak, nonatomic, nullable) VisualSample* visualSample;
@property (weak, nonatomic, nullable) BeatTrackedSample* beatSample;

@property (assign, nonatomic) unsigned long long frames;

@property (assign, nonatomic) CGFloat markerWidth;
@property (strong, nonatomic) NSColor* markerColor;

@property (assign, nonatomic) CGFloat beatWidth;
@property (strong, nonatomic) NSColor* beatColor;

@property (assign, nonatomic) CGFloat barWidth;
@property (strong, nonatomic) NSColor* barColor;

@property (assign, nonatomic) BeatEventStyle beatMask;

@property (strong, nonatomic) NSColor* waveFillColor;
@property (strong, nonatomic) NSColor* waveOutlineColor;
@property (strong, nonatomic) OffsetBlock offsetBlock;
@property (strong, nonatomic) TotalWidthBlock widthBlock;

- (void)updateTileView:(TileView*)tile;

@end

NS_ASSUME_NONNULL_END
