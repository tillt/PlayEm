//
//  Visualizer.m
//  PlayEm
//
//  Created by Till Toenshoff on 11.04.20.
//  Copyright © 2020 Till Toenshoff. All rights reserved.
//

#import "Visualizer.h"

#import <Cocoa/Cocoa.h>
#import <Accelerate/Accelerate.h>  //Include the Accelerate framework to perform FFT
#import <AppKit/AppKit.h>
#import <AVFoundation/AVFoundation.h>

#import "VisualSample.h"
#import "Sample.h"
#import "AudioController.h"

const size_t kWindowSamples = 4096;
const size_t kFrequencyDataLength = 256;

/*
 - (NSMutableArray*)performFFT: (float*) data withFrames: (int) numSamples {
 // 1. init
 float bufferSize = numSamples;
 uint32_t maxFrames = numSamples;
 displayData = (float*)malloc(maxFrames*sizeof(float));
 bzero(displayData, maxFrames*sizeof(float));
 int log2n = log2f(maxFrames);
 int n = 1 << log2n;
 assert(n == maxFrames);
 float nOver2 = maxFrames/2;
 A.realp = (float*)malloc(nOver2 * sizeof(float));
 A.imagp = (float*)malloc(nOver2 * sizeof(float));
 fftSetup = vDSP_create_fftsetup(log2n, FFT_RADIX2);
 // 2. calcuate
 bufferSize = numSamples;
 float ln = log2f(numSamples);
 vDSP_ctoz((COMPLEX*)data, 2, &A, 1, numSamples/2);
 //fft
 vDSP_fft_zrip(fftSetup, &A, 1, ln, FFT_FORWARD);
 // Absolute square (equivalent to mag^2)
 vDSP_zvmags(&A, 1, A.realp, 1, numSamples/2);
 // make imaginary part to zero in order to filter them out in the following loop
 bzero(A.imagp, (numSamples/2) * sizeof(float));
 //convert complex split to real
 vDSP_ztoc(&A, 1, (COMPLEX*)displayData, 2, numSamples/2);
 // Normalize
 float scale = 1.f/displayData[0];
 vDSP_vsmul(displayData, 1, &scale, displayData, 1, numSamples);
 //scale fft
 Float32 mFFTNormFactor = 1.0/(2*numSamples);
 vDSP_vsmul(A.realp, 1, &mFFTNormFactor, A.realp, 1, numSamples/2);
 vDSP_vsmul(A.imagp, 1, &mFFTNormFactor, A.imagp, 1, numSamples/2);
 */


@interface Visualizer ()

//@property (strong, nonatomic) AVAudioPlayer* audioPlayer;
@property (weak, nonatomic) MTKView* scopeView;

@property (strong, nonatomic) NSMutableData* window;
@property (strong, nonatomic) NSMutableData* frequencyData;
@property (assign, nonatomic) FFTSetup fftSetup;
@property (assign, nonatomic) BOOL fftModeLED;
@property (assign, nonatomic) size_t minTriggerOffset;


@end


@implementation Visualizer

/*
    44100 *
 */

- (id)initWithScopeView:(MTKView*)scopeView
{
    self = [super init];
    if (self) {
        _window = [[NSMutableData alloc] initWithCapacity:sizeof(float) * kWindowSamples];
        _scopeView = scopeView;
        _fftModeLED = NO;
        _minTriggerOffset = 0;
        
        _lightColor = [NSColor colorWithRed:(CGFloat)0xfd / 255.0
                                      green:(CGFloat)0xb6 / 255.0
                                       blue:(CGFloat)0x57 / 255.0
                                      alpha:1.0];

        /*
        _backgroundColor = [NSColor colorWithRed:(CGFloat)0x30 / 255.0
                                           green:(CGFloat)0x30 / 255.0
                                            blue:(CGFloat)0x32 / 255.0
                                           alpha:1.0];
        */

        _backgroundColor = [NSColor colorWithRed:(CGFloat)0x00 / 255.0
                                           green:(CGFloat)0x00 / 255.0
                                            blue:(CGFloat)0x00 / 255.0
                                           alpha:0.02];
        
        _scopeView.device = MTLCreateSystemDefaultDevice();
        if(!_scopeView.device) {
            NSLog(@"Metal is not supported on this device");
        } else {
            _renderer = [[ScopeRenderer alloc] initWithMetalKitView:_scopeView
                                                              color:_lightColor
                                                         background:_backgroundColor];

            [_renderer mtkView:_scopeView drawableSizeWillChange:_scopeView.bounds.size];
            _scopeView.delegate = _renderer;
            _scopeView.layer.opaque = false;
        }
    }
    return self;
}


+ (void)drawVisualSample:(VisualSample *)visual start:(unsigned long int )start length:(unsigned long int )length size:(CGSize)size color:(CGColorRef)color context:(CGContextRef)context
{
    CGContextSetFillColorWithColor(context, [[NSColor clearColor] CGColor]);
    CGContextFillRect(context, CGRectMake(0.0, 0.0, size.width, size.height));

    if (visual == nil || visual.buffer == nil || visual.buffer.bytes == nil) {
        return;
    }

    //[NSGraphicsContext saveGraphicsState];
    //[NSGraphicsContext setCurrentContext:

    unsigned long int totalSamples = visual.buffer.length / sizeof(VisualPair);
    
    if (totalSamples == 0) {
        return;
    }

    unsigned long int displaySampleOffset = start;
    unsigned long int displaySampleCount = length;

    double samplesPerPixel = displaySampleCount / size.width;
    VisualPair* data = (VisualPair *)visual.buffer.bytes;
    unsigned long int sampleIndex = displaySampleOffset;
    unsigned long int maxSampleIndex = displaySampleOffset + displaySampleCount - 1;

    double smallest = 0.0, biggest = 0.0;
    CGFloat x = 0.0;
     
    //[[NSColor underPageBackgroundColor] set];
    //1e1407
    //241809
    //503614
    //CGColorRef color = [[NSColor colorWithRed:(CGFloat)0x50 / 255.0 green:(CGFloat)0x36 / 255.0 blue:(CGFloat)0x14 / 255.0 alpha:1.0] CGColor];
    //CGContextSetStrokeColor(context, CGColorGetComponents(color));
    CGContextSetLineWidth(context, 1.0);
                        
    CGContextSetStrokeColorWithColor(context, color);
    
    CGFloat mid = (size.height / 2.0) - 1.0;

    double counter = 0.0;
    unsigned int fixed = 0;

    while(sampleIndex < maxSampleIndex) {
        counter += samplesPerPixel;
        fixed = (int)counter;

        smallest = 0.0f;
        biggest = 0.0f;

        for (size_t i=0;i < fixed;i++) {
            smallest = MIN(data[sampleIndex].negativeMax, smallest);
            biggest = MAX(data[sampleIndex].positiveMax, biggest);
            ++sampleIndex;
        }

        counter -= fixed;

        CGFloat top = mid + ((smallest * size.height) / 2.0) - 1.0;
        CGFloat bottom = mid + ((biggest * size.height) / 2.0) + 1.0;

        //[NSBezierPath strokeLineFromPoint:NSMakePoint(x, top) toPoint:NSMakePoint(x, bottom)];
        CGContextMoveToPoint(context, x, top);
        CGContextAddLineToPoint(context, x, bottom);
        CGContextStrokePath(context);
        x = x + 1.0f;
    };
}

+ (void)drawVisualSample:(VisualSample *)visual start:(NSTimeInterval)start duration:(NSTimeInterval)duration size:(CGSize)size color:(CGColorRef)color context:(CGContextRef)context
{
    unsigned long int totalSamples = visual.buffer.length / sizeof(VisualPair);
    
    if (totalSamples == 0) {
        return;
    }

    unsigned long int displaySampleOffset = (totalSamples * start) / visual.sample.duration;
    unsigned long int displaySampleCount = (totalSamples *  duration) / visual.sample.duration;

    [Visualizer drawVisualSample:visual start:displaySampleOffset length:displaySampleCount size:size color:color context:context];
}


+ (NSImage *)imageFromVisualSample:(VisualSample *)visual start:(NSTimeInterval)start duration:(NSTimeInterval)duration size:(CGSize)size
{
    if (visual == nil) {
        return nil;
    }
    
    NSLog(@"Creating image from visual sample...\n");
    NSLog(@"image size: %f %f\n", size.width, size.height);
    NSLog(@"sample duration: %lf\n", duration);

    NSBitmapImageRep* offscreenRep = [[NSBitmapImageRep alloc]
        initWithBitmapDataPlanes:NULL
                      pixelsWide:size.width
                      pixelsHigh:size.height
                   bitsPerSample:8
                 samplesPerPixel:4
                        hasAlpha:YES
                        isPlanar:NO
                  colorSpaceName:NSCalibratedRGBColorSpace
                     bytesPerRow:0
                    bitsPerPixel:0];

    NSGraphicsContext* nsContext = [NSGraphicsContext graphicsContextWithBitmapImageRep:offscreenRep];

    CGColorSpaceRef colorspace = CGColorSpaceCreateDeviceRGB();
    CGFloat components[] = {(CGFloat)0x50 / 255.0, (CGFloat)0x36 / 255.0, (CGFloat)0x14 / 255.0, 1.0};
    CGColorRef color = CGColorCreate(colorspace, components);

    [Visualizer drawVisualSample:visual start:start duration:duration size:size color:color context:[nsContext CGContext]];

    CGColorSpaceRelease(colorspace);
    CGColorRelease(color);

    NSImage* image = [[NSImage alloc] initWithSize:size];
    [image addRepresentation:offscreenRep];

    NSLog(@"Created image\n");

    return image;
}


+ (NSImage *)imageFromSample:(Sample *)sample start:(NSTimeInterval)start duration:(NSTimeInterval)duration size:(CGSize)size
{
    if (sample == nil) {
        return nil;
    }
    
    NSBitmapImageRep* offscreenRep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL
                                                                             pixelsWide:size.width
                                                                             pixelsHigh:size.height
                                                                          bitsPerSample:8
                                                                        samplesPerPixel:4
                                                                               hasAlpha:YES
                                                                               isPlanar:NO
                                                                         colorSpaceName:NSCalibratedRGBColorSpace
                                                                            bytesPerRow:0
                                                                           bitsPerPixel:0];

    NSGraphicsContext* nsContext = [NSGraphicsContext graphicsContextWithBitmapImageRep:offscreenRep];
    [NSGraphicsContext saveGraphicsState];
    [NSGraphicsContext setCurrentContext:nsContext];
    
    int channels = sample.channels;
    int bytesPerSample = 2;
    
    unsigned long int totalSamples = sample.size / bytesPerSample;
    
    unsigned long int displaySampleOffset = (totalSamples * start) / sample.duration;
    displaySampleOffset = (displaySampleOffset / channels) * channels;

    unsigned long int displaySampleCount = (totalSamples *  duration)  / sample.duration;
    displaySampleCount = (displaySampleCount / channels) * channels;
    
    double samplesPerPixel = displaySampleCount / size.width;
    const signed short int *data = (const signed short  int *)sample.data.bytes;
    double counter = 0.0f;
    unsigned long int sampleIndex = displaySampleOffset;
    unsigned long int maxSampleIndex = displaySampleOffset + displaySampleCount - 1;

    double smallest = 0.0, biggest = 0.0;
    double s = 0.0;
    CGFloat x = 0.0;
    
    [[NSColor systemBrownColor] set];

    CGFloat mid = (size.height / 2.0) - 1.0;

    while(sampleIndex < maxSampleIndex) {
        smallest = 0.0f;
        biggest = 0.0f;

        do {
            if (sampleIndex > maxSampleIndex) {
                break;
            }

            s = (double)data[sampleIndex];
            
            sampleIndex++;
            counter += 1.0f;

            if (channels > 1) {
                if (sampleIndex > maxSampleIndex) {
                    break;
                }

                s += (double)data[sampleIndex];

                sampleIndex++;
                counter += 1.0f;

                s /= 2.0f;
            }
            
            smallest = MIN(s, smallest);
            biggest = MAX(s, biggest);

        } while (counter < samplesPerPixel);
        
        // Distributing the fractional sample error by leaving a sub-sample or fraction - causing the next round to possibly be shorter than `samplesPerPixel`.
        counter -= samplesPerPixel;
      
        CGFloat top = mid + ((smallest * size.height) / 65535.0);
        CGFloat bottom = mid + ((biggest * size.height) / 65535.0);

        [NSBezierPath strokeLineFromPoint:NSMakePoint(x, top) toPoint:NSMakePoint(x, bottom)];

        x = x + 1.0f;
    };
   
    [NSGraphicsContext restoreGraphicsState];

    NSImage* image = [[NSImage alloc] initWithSize:size];
    [image addRepresentation:offscreenRep];

    NSLog(@"Created image\n");

    return image;
}

- (void)play:(AudioController *)audio visual:(VisualSample *)visual
{
    [_renderer play:audio visual:visual scope:_scopeView];
}

- (void)stop
{
    [_renderer stop:_scopeView];
}

@end
