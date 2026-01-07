//
//  MediaMetaData+JPEGTool.m
//  PlayEm
//
//  Created by Till Toenshoff on 12/17/25.
//  Copyright © 2025 Till Toenshoff. All rights reserved.
//

#import "../NSImage+Resize.h"
#import "JPEGTool.h"
#import "MediaMetaData.h"

@implementation MediaMetaData (JPEGTool)

- (NSData*)sizedJPEG420
{
    JPEGSamplingInfo info;

    // Get the artwork. If there was none, return a default image.
    NSData* source = self.artworkWithDefault;
    assert(source);

    BOOL yuvOK = [JPEGTool isJPEGYUV420:source samplingInfo:&info];
    BOOL sizeOK = ((info.width == 800) && (info.height == 800));

    NSData* artwork420 = nil;

    if (info.isJPEG && sizeOK && yuvOK) {
        artwork420 = self.artwork;
    }

    if (artwork420 == nil) {
        NSImage* image = [self imageFromArtwork];

        sizeOK = ((image.size.width == 800) && (image.size.height == 800));
        if (!sizeOK) {
            image = [NSImage resizedImageWithData:source size:NSMakeSize(800, 800)];
        }
        // Get us a YUVJ 4:2:0 encoded JPEG file as data from that image. We need
        // those to assert proper compatibility. For our own purposes we could even
        // encode PNG files within the MJPEG track and that works fine -
        // surprisingly fine. Just other players like QuickTime wont like that at
        // all and display black images.
        artwork420 = [JPEGTool encodeImageToJPEG420:image quality:1.0];
    }

    return artwork420;
}

@end
