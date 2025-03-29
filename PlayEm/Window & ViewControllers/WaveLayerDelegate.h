//
//  WaveLayerDelegate.h
//  PlayEm
//
//  Created by Till Toenshoff on 25.08.23.
//  Copyright © 2023 Till Toenshoff. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <Cocoa/Cocoa.h>
#import <QuartzCore/QuartzCore.h>

NS_ASSUME_NONNULL_BEGIN
@class VisualSample;
@class WaveView;

typedef CGFloat (^OffsetBlock) (void);
typedef CGFloat (^TotalWidthBlock) (void);

@interface WaveLayerDelegate : NSObject <CALayerDelegate>

@property (weak, nonatomic) VisualSample* visualSample;
@property (strong, nonatomic) NSColor* fillColor;
@property (strong, nonatomic) NSColor* outlineColor;
@property (strong, nonatomic) OffsetBlock offsetBlock;
@property (strong, nonatomic) TotalWidthBlock widthBlock;

@end

NS_ASSUME_NONNULL_END
