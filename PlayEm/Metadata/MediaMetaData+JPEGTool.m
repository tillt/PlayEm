//
//  MediaMetaData+JPEGTool.m
//  PlayEm
//
//  Created by Till Toenshoff on 12/17/25.
//  Copyright © 2025 Till Toenshoff. All rights reserved.
//

#import "MediaMetaData.h"
#import "JPEGTool.h"
#import "../NSImage+Resize.h"

@implementation MediaMetaData(JPEGTool)

- (NSData*)sizedJPEG420
{
    JPEGSamplingInfo info;
    
    if (self.artwork == nil) {
        NSLog(@"there is no artwork available");
        return nil;
    }

    BOOL yuvOK = [JPEGTool jpegIsYUV420:self.artwork samplingInfo:&info];
    BOOL sizeOK = ((info.width == 800) && (info.height == 800));

    NSData* artwork420 = nil;

    if (info.isJPEG && sizeOK && yuvOK) {
        NSLog(@"image already in JPEG 4:2:0 format, no need to re-encode");
        NSLog(@"image has the right dimensions, no need to resize");
        artwork420 = self.artwork;
    }

    if (artwork420 == nil) {
        NSImage* image = [self imageFromArtwork];

        sizeOK = ((image.size.width == 800) && (image.size.height == 800));
        if (!sizeOK) {
            NSLog(@"image needs resize");
            image = [NSImage resizedImageWithData:self.artwork size:NSMakeSize(800, 800)];
        } else {
            NSLog(@"image size %f x %f", image.size.width, image.size.height);
        }

        NSLog(@"image needs re-encode");
        artwork420 = [JPEGTool encodeImageToJPEG420:image quality:1.0];
    }

    return artwork420;
}

@end
