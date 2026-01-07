//
//  NSImage+Resize.m
//  PlayEm
//
//  Created by Till Toenshoff on 3/29/25.
//  Copyright © 2025 Till Toenshoff. All rights reserved.
//

#import "CoreImage/CoreImage.h"
#import "NSImage+Resize.h"

@implementation NSImage (Resize)

+ (NSImage* _Nullable)resizedImage:(NSImage* _Nullable)image size:(NSSize)target
{
    if (image == nil) {
        return nil;
    }
    NSImageRep* rep = [image bestRepresentationForRect:NSMakeRect(0, 0, image.size.width, image.size.height) context:nil hints:nil];
    CGImageRef src = [rep CGImageForProposedRect:NULL context:nil hints:nil];
    if (!src) {
        return nil;
    }

    CGColorSpaceRef sRGB = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    CGContextRef ctx = CGBitmapContextCreate(NULL, target.width, target.height, 8, 0, sRGB, kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Host);
    if (!ctx) {
        CGColorSpaceRelease(sRGB);
        return nil;
    }

    CGContextSetInterpolationQuality(ctx, kCGInterpolationHigh);
    CGContextDrawImage(ctx, CGRectMake(0, 0, target.width, target.height), src);
    CGImageRef scaled = CGBitmapContextCreateImage(ctx);

    NSImage* out = [[NSImage alloc] initWithCGImage:scaled size:NSMakeSize(target.width, target.height)];

    CGImageRelease(scaled);
    CGContextRelease(ctx);
    CGColorSpaceRelease(sRGB);

    return out;
}

+ (NSImage* _Nullable)resizedImageWithData:(NSData* _Nullable)jpegData size:(NSSize)target
{
    if (jpegData == nil) {
        return nil;
    }
    // Decode with an explicit sRGB input space
    NSDictionary* imgOpts = @{kCIImageColorSpace : (__bridge id)[NSColorSpace sRGBColorSpace].CGColorSpace};
    CIImage* src = [CIImage imageWithData:jpegData options:imgOpts];
    if (!src) {
        return nil;
    }

    // Compute scale factor
    CGFloat scale = target.width / src.extent.size.width;

    // High-quality scale
    CIFilter* lanczos = [CIFilter filterWithName:@"CILanczosScaleTransform"];
    [lanczos setDefaults];
    [lanczos setValue:src forKey:kCIInputImageKey];
    [lanczos setValue:@(scale) forKey:@"inputScale"];
    [lanczos setValue:@1.0 forKey:@"inputAspectRatio"];
    CIImage* outCI = lanczos.outputImage;
    if (!outCI) {
        return nil;
    }

    // CI context pinned to sRGB in and out
    CIContext* ctx = [CIContext contextWithOptions:@{
        kCIContextWorkingColorSpace : (__bridge id)[NSColorSpace sRGBColorSpace].CGColorSpace,
        kCIContextOutputColorSpace : (__bridge id)[NSColorSpace sRGBColorSpace].CGColorSpace
    }];

    CGRect outRect = CGRectMake(0, 0, target.width, target.height);
    CGImageRef cg = [ctx createCGImage:outCI fromRect:outRect];
    if (!cg) {
        return nil;
    }

    NSImage* result = [[NSImage alloc] initWithCGImage:cg size:NSMakeSize(target.width, target.height)];
    CGImageRelease(cg);
    return result;
}

@end
