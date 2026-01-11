//
//  MediaMetaData+ImageController.m
//  PlayEmCore
//
//  Created by Till Toenshoff on 1/10/26.
//  Copyright © 2026 Till Toenshoff. All rights reserved.
//

#import "MediaMetaData+ImageController.h"
#import "../ImageController.h"

@implementation MediaMetaData (ImageController)

- (void)resolvedArtworkForSize:(CGFloat)size callback:(void (^)(NSImage*))callback
{
    // We may have data available but not resized properly.
    // We may have exactly the right graphics available through the image cache.
    // We may not have any image data available yet and need a resized default for now.
    // And we may never have better data than a resized default.
    
    NSData* data = self.artwork;
    NSString* hash = self.artworkHash;
    if (data == nil) {
        data = [MediaMetaData defaultArtworkData];
        hash = @"Default";
    }
    
    [[ImageController shared] imageForData:data
                                       key:hash
                                      size:size
                                completion:^(NSImage* image) {
        if (image == nil) {
            return;
        }
        // We got an early image, lets allow the callback to set use it already.
        callback(image);

        // Do we still need proper artwork data, or is that done?
        if (self.artwork == nil) {
            if (self.artworkLocation != nil) {
                [[ImageController shared] resolveDataForURL:self.artworkLocation
                                                   callback:^(NSData* data) {
                    self.artwork = data;
                    [[ImageController shared] imageForData:self.artwork
                                                       key:self.artworkHash
                                                      size:size
                                                completion:^(NSImage* image) {
                        if (image == nil) {
                            return;
                        }
                        // We got an image, lets allow the callback to set it to the
                        // resized, cached artwork.
                        callback(image);
                    }];
                }];
            }
        }
    }];
}

@end
