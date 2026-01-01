//
//  ImageController.m
//  PlayEm
//
//  Created by Till Toenshoff on 12/21/25.
//  Copyright © 2025 Till Toenshoff. All rights reserved.
//

#import "ImageController.h"
#import <AppKit/AppKit.h>
#import <CoreImage/CoreImage.h>
#import <iTunesLibrary/ITLibArtist.h>
#import <iTunesLibrary/ITLibAlbum.h>

@interface ImageController ()
@property (nonatomic) NSCache<NSString*, NSImage*>* cache;
@property (nonatomic) CIContext* ciContext;
@property (strong, nonatomic) dispatch_queue_t resizingQueue;
@property (strong, nonatomic) dispatch_queue_t downloadingQueue;
@end

@implementation ImageController

+ (instancetype)shared
{
    static ImageController *mgr;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        mgr = [[ImageController alloc] init];
    });
    return mgr;
}

- (instancetype)init
{
    self = [super init];
    if (self != nil) {
        self.cache = [NSCache new];
        self.cache.totalCostLimit = 50 * 1024 * 1024; // ~50 MB
        
        dispatch_queue_attr_t attr = dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL, QOS_CLASS_USER_INITIATED, 0);
        _resizingQueue = dispatch_queue_create("PlayEm.ImageControllerResizeQueue", attr);
        _downloadingQueue = dispatch_queue_create("PlayEm.ImageControllerDownloadQueue", attr);

        CGColorSpaceRef sRGB = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
        self.ciContext = [CIContext contextWithOptions:@{
            kCIContextOutputColorSpace: (__bridge id)sRGB
        }];
        CGColorSpaceRelease(sRGB);
    }
    return self;
}

- (void)imageForData:(NSData*)data
                 key:(NSString*)key
                size:(CGFloat)size
          completion:(void (^)(NSImage*image))completion
{
    NSString *cacheKey = [NSString stringWithFormat:@"%@-%.0f", key, size];
    NSImage *cached = [self.cache objectForKey:cacheKey];
    if (cached != nil) {
        completion(cached);
        return;
    }
    
    dispatch_async(_resizingQueue, ^{
        CIImage *ci = [CIImage imageWithData:data options:@{ kCIImageApplyOrientationProperty : @YES }];
        if (ci == nil) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(nil);
            });
            return;
        }
        
        CGFloat scale = size / MAX(ci.extent.size.width, ci.extent.size.height);
        CIFilter *f = [CIFilter filterWithName:@"CILanczosScaleTransform"];
        [f setValue:ci forKey:kCIInputImageKey];
        [f setValue:@(scale) forKey:kCIInputScaleKey];
        [f setValue:@1.0 forKey:kCIInputAspectRatioKey];
        CIImage *scaled = f.outputImage;
        
        CGImageRef cg = [self.ciContext createCGImage:scaled fromRect:scaled.extent];
        NSImage *thumb = nil;
        if (cg != nil) {
            thumb = [[NSImage alloc] initWithCGImage:cg size:NSMakeSize(size, size)];
            size_t cost = CGImageGetBytesPerRow(cg) * CGImageGetHeight(cg);
            [self.cache setObject:thumb forKey:cacheKey cost:cost];
            CGImageRelease(cg);
        }
        
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(thumb);
        });
    });
}

- (void)clearCache
{
    [self.cache removeAllObjects];
}

- (void)resolveDataForURL:(NSURL*)url callback:(void (^)(NSData*))callback
{
    dispatch_async(_downloadingQueue, ^{
        NSData* data = [[NSData alloc] initWithContentsOfURL:url];
        dispatch_async(dispatch_get_main_queue(), ^{
            callback(data);
        });
    });
}

- (NSString*)description
{
    return [NSString stringWithFormat:@"cache state: %@", self.cache.description];
}

@end

