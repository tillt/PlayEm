//
//  TiledWaveView.m
//  PlayEm
//
//  Created by Till Toenshoff on 02.05.20.
//  Copyright © 2020 Till Toenshoff. All rights reserved.
//

#import "TiledWaveView.h"

#import <QuartzCore/QuartzCore.h>

@implementation TiledWaveView

- (void)awakeFromNib
{
    self.layer = [CALayer layer];
    self.wantsLayer = YES;
    self.layer.masksToBounds = YES;
    self.layer.cornerRadius = 8.0f;

    _waveImageLayer = [CATiledLayer layer];
    _waveImageLayer.delegate = self;
    _zoomLevel = 1.0f;
    _waveImageLayer.frame = self.bounds;
    // set the levels of detail (range is 2^-2 to 2^1)
    _waveImageLayer.levelsOfDetail = 1;
    _waveImageLayer.tileSize = NSMakeSize(1024.0, 1024.0);
    // set the bias for how many 'zoom in' levels there are
    _waveImageLayer.levelsOfDetailBias = 1; // up to 2x (2^1)of the largest photo
    [_waveImageLayer setNeedsDisplay]; // display the whole layer

    [self.layer addSublayer:_waveImageLayer];
}

- (void)resizeWithOldSuperviewSize:(NSSize)oldSize
{
    [super resizeWithOldSuperviewSize:oldSize];
    
    _waveImageLayer.frame = self.bounds;
    [self needsDisplay];
}

#pragma mark Tiled layer delegate methods

- (void)drawLayer:(CALayer*)layer inContext:(CGContextRef)context
{
    // Fetch clip box in *world* space; context's CTM is preconfigured for world space->tile pixel space transform
    CGRect box = CGContextGetClipBoundingBox(context);
    
    // Calculate tile index
    CGSize tileSize = [(CATiledLayer*)layer tileSize];
    CGRect tbox = CGRectApplyAffineTransform(CGRectMake(0, 0, tileSize.width, tileSize.height),
                                             CGAffineTransformInvert(CGContextGetCTM(context)));
    CGFloat x = box.origin.x / tbox.size.width;
    CGFloat y = box.origin.y / tbox.size.height;
    CGPoint tile = CGPointMake(x, y);
    
    // Clear background
    //CGContextSetFillColorWithColor(context, [[UIColor grayColor] CGColor]);
    //CGContextFillRect(context, box);
    
    // Rendering the paths
    CGContextSaveGState(context);
    
    /*
    //CGContextConcatCTM(context, [self transformForTile:tile]);
    //NSArray* pathGroups = [self pathGroupsForTile:tile];


    for (PathGroup* pg in pathGroups)
    {
        CGContextSaveGState(context);
        
        CGContextConcatCTM(context, pg.modelTransform);
        
        for (Path* p in pg.paths)
        {
            [p renderToContext:context];
        }
        
        CGContextRestoreGState(context);
    }
    CGContextRestoreGState(context);
    */
    // Render label (Setup)
    NSFont* font = [NSFont fontWithName:@"CourierNewPS-BoldMT" size:16];
    CGContextSelectFont(context, [[font fontName] cStringUsingEncoding:NSASCIIStringEncoding], [font pointSize], kCGEncodingMacRoman);
    CGContextSetTextDrawingMode(context, kCGTextFill);
    //CGContextSetTextMatrix(context, CGAffineTransformMakeScale(1, -1));
    CGContextSetFillColorWithColor(context, [[NSColor greenColor] CGColor]);
    
    // Draw label
    NSString* s = [NSString stringWithFormat:@"(%.1f, %.1f)",x,y];
    CGContextShowTextAtPoint(context,
                             box.origin.x,
                             box.origin.y + [font pointSize],
                             [s cStringUsingEncoding:NSMacOSRomanStringEncoding],
                             [s lengthOfBytesUsingEncoding:NSMacOSRomanStringEncoding]);
}

@end
