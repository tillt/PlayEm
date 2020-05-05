//
//  CAShapeLayer+CAShapeLayer_Path.h
//  PlayEm
//
//  Created by Till Toenshoff on 23.10.22.
//  Copyright © 2022 Till Toenshoff. All rights reserved.
//

#import <QuartzCore/QuartzCore.h>

NS_ASSUME_NONNULL_BEGIN

@interface CAShapeLayer (Path)

+ (CAShapeLayer*)MaskLayerFromRect:(NSRect)rect;

@end

NS_ASSUME_NONNULL_END
