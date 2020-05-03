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

static void performFFT(FFTSetup fft, float *data, size_t numberOfFrames, float *frequencyData)
{
    // 2^(round(log2(numberOfFrames)).
    const int bufferLog2 = round(log2(numberOfFrames));
    const float fftNormFactor = 1.0 / (numberOfFrames / 4.0);

    static BOOL initialized = NO;
    static float *outReal = NULL;
    static float *outImaginary = NULL;
    static COMPLEX_SPLIT *output = NULL;
    
    if (!initialized) {
        // All `malloc` memory allocations are 16-byte aligned as needed by the altivec functions.
        outReal = (float *)malloc(sizeof(float) * numberOfFrames / 2.0);
        outImaginary = (float *)malloc(sizeof(float) * numberOfFrames / 2.0);
        output = (COMPLEX_SPLIT *)malloc(sizeof(COMPLEX_SPLIT));
        output->realp = outReal;
        output->imagp = outImaginary;
        initialized = YES;
    }
    // 2^(round(log2(numberOfFrames)).

    // Initialize arrays to all zeros.
    for (int i =0 ;i < kWindowSamples / 2; ++i) {
        outReal[i] = 0;
        outImaginary[i] = 0;
    }
    // Put all of the even numbered elements into outReal and odd numbered into outImaginary.
    vDSP_ctoz((COMPLEX *)data, 2, output, 1, numberOfFrames / 2);
    vDSP_fft_zrip(fft, output, 1, bufferLog2, FFT_FORWARD);
    // Scale the FFT data.
    vDSP_vsmul(output->realp, 1, &fftNormFactor, output->realp, 1, kFrequencyDataLength);
    vDSP_vsmul(output->imagp, 1, &fftNormFactor, output->imagp, 1, kFrequencyDataLength);
    // Take the absolute value of the output to get in range of 0 to 1.
    vDSP_zvabs(output, 1, frequencyData, 1, kFrequencyDataLength);
    /*
    
    vDSP_ztoc(&A, 1, (COMPLEX*)displayData, 2, numSamples/2);
    // Normalize
    float scale = 1.f/displayData[0];
    vDSP_vsmul(displayData, 1, &scale, displayData, 1, numSamples);
    //scale fft
    Float32 mFFTNormFactor = 1.0/(2*numSamples);
    vDSP_vsmul(A.realp, 1, &mFFTNormFactor, A.realp, 1, numSamples/2);
    vDSP_vsmul(A.imagp, 1, &mFFTNormFactor, A.imagp, 1, numSamples/2);
    
    
    
    //cblas_sscal(bufferFrames, 1.0 / (bufferFrames * 2), outData, 1);
    
     */
}



@interface Visualizer ()

//@property (strong, nonatomic) AVAudioPlayer* audioPlayer;
@property (weak, nonatomic) NSView *fftView;
@property (weak, nonatomic) NSView *scopeView;

@property (strong, nonatomic) NSMutableData *window;
@property (strong, nonatomic) NSMutableData *frequencyData;
@property (assign, nonatomic) FFTSetup fftSetup;

@end

@implementation Visualizer



/*
    44100 *
 */

- (id)initWithFFTView:(NSView *)fftView scopeView:(NSView *)scopeView
{
    self = [super init];
    if (self) {
        _window = [[NSMutableData alloc] initWithCapacity:sizeof(float) * kWindowSamples];
        _frequencyData = [[NSMutableData alloc] initWithCapacity:sizeof(double) * kFrequencyDataLength];
        _fftSetup = vDSP_create_fftsetup(round(log2(kWindowSamples)), kFFTRadix2);
        _fftView = fftView;
        _scopeView = scopeView;
        
        CGFloat width = _fftView.bounds.size.width / (float)kFrequencyDataLength;
        CGFloat x = 0.0;
        for (int i=0;i < kFrequencyDataLength;i++) {
            CGRect frame = CGRectMake(x, 0.0, width, _fftView.bounds.size.height);
            CALayer *element = [[CALayer alloc] init];
            [element setBackgroundColor:[[NSColor colorWithRed:(CGFloat)0xfd / 255.0 green:(CGFloat)0xb6 / 255.0 blue:(CGFloat)0x57 / 255.0 alpha:1.0] CGColor]];
            element.frame = frame;
            [_fftView.layer addSublayer:element];
            element.position = CGPointMake(element.position.x, -_fftView.bounds.size.height);
            x += width;
        }
        
        CAShapeLayer *shapeLayer = [[CAShapeLayer alloc] init];
        shapeLayer.frame = _scopeView.bounds;
        [_scopeView.layer addSublayer:shapeLayer];

        CGFloat mid = _scopeView.bounds.size.height / 2.0;
        CGMutablePathRef path = CGPathCreateMutable();
        CGPathMoveToPoint(path, NULL, 0, mid);
        for (int i=1;i < _scopeView.bounds.size.width;i++) {
            CGPathAddLineToPoint(path, NULL, i, mid);
        }
        shapeLayer.lineWidth = 2.0;
        shapeLayer.strokeColor = [[NSColor colorWithRed:(CGFloat)0xfd / 255.0 green:(CGFloat)0xb6 / 255.0 blue:(CGFloat)0x57 / 255.0 alpha:1.0] CGColor];
        shapeLayer.fillColor = nil;
        shapeLayer.path = path;

        /*
        Class vibrantClass=NSClassFromString(@"NSVisualEffectView");
        NSVisualEffectView *vibrant=[[vibrantClass alloc] initWithFrame:_scopeView.bounds];
        [vibrant setAutoresizingMask:NSViewWidthSizable|NSViewHeightSizable];
        // uncomment for dark mode instead of light mode
        // [vibrant setAppearance:[NSAppearance appearanceNamed:NSAppearanceNameVibrantDark]];
        [vibrant setBlendingMode:NSVisualEffectBlendingModeWithinWindow];
        [_scopeView addSubview:vibrant positioned:NSWindowAbove relativeTo:nil];*/
    }
    return self;
}

- (void)resizeScope:(NSSize)size
{
    /*
    CGFloat mid = size.height / 2.0;
    CGMutablePathRef path = CGPathCreateMutable();
    CGPathMoveToPoint(path, NULL, 0, mid);

    for (int i=1;i < size.width;i++) {
        CGPathAddLineToPoint(path, NULL, i, mid);
    }
     */
    
    CAShapeLayer *shapeLayer = _scopeView.layer.sublayers[0];
    shapeLayer.frame = CGRectMake(0,0,size.width,size.height);
    shapeLayer.lineWidth = 2.0;
    shapeLayer.strokeColor = [[NSColor colorWithRed:(CGFloat)0xfd / 255.0 green:(CGFloat)0xb6 / 255.0 blue:(CGFloat)0x57 / 255.0 alpha:1.0] CGColor];
    shapeLayer.fillColor = [[NSColor clearColor] CGColor];
    //shapeLayer.path = path;
}

- (void)resizeFFT:(NSSize)size
{
    CGFloat width = size.width / (float)kFrequencyDataLength;
    CGFloat x = 0.0;
    for (int i=0;i < kFrequencyDataLength;i++) {
        CGRect frame = CGRectMake(x, 0.0, width, _fftView.bounds.size.height);
        CALayer *element = _fftView.layer.sublayers[i];
        element.frame = frame;
        element.position = CGPointMake(element.position.x, -_fftView.bounds.size.height);
        x += width;
    }
}

- (void)process:(AVAudioPCMBuffer *)audioPCMBuffer offet:(size_t)offset bufferSamples:(size_t)bufferSamples channels:(int)channels
{
    size_t midOffset = kWindowSamples / 2;
    size_t sample = offset < midOffset ? offset : offset - midOffset;
    
    sample = (sample / 2) * 2;
    
    float *window = self.window.mutableBytes;
    
    float last = 0.0f;
    float veryLast = 0.0f;
    bool triggered = NO;

    size_t minTriggerOffset = round(self.scopeView.bounds.size.width / 2.0) - 1;
    size_t triggerOffset = minTriggerOffset;

    for (size_t i = 0; i < kWindowSamples; i++) {
        if (channels > 1) {
            window[i] = (audioPCMBuffer.floatChannelData[0][sample] + audioPCMBuffer.floatChannelData[1][sample]) / 2.0;
        } else {
            window[i] = audioPCMBuffer.floatChannelData[0][sample];
        }

        if (!triggered) {
            //if (i > minTriggerOffset && window[i] >= 0.0 && veryLast < last && last <= window[i]) {
            if (i > minTriggerOffset && (window[i] > 0.0f && window[i] < 0.01f) && last + 0.001f < window[i]) {
                triggered = YES;
                triggerOffset = i;
            }
        }

        veryLast = last;
        last = window[i];

        ++sample;
        if (sample > bufferSamples) {
            NSLog(@"Exceeded %ld samples, starting over", sample - offset);
            sample = offset;
        }
    }

    const CGFloat midY = self.scopeView.bounds.size.height / 2.0;

    size_t start = triggerOffset - minTriggerOffset;
    
    CGFloat x = 0.0;

    CGMutablePathRef path = CGPathCreateMutable();
    CGPathMoveToPoint(path, NULL, 0.0, midY);
    
    for (size_t i = 0; i < kWindowSamples; i++) {
        if (x >= self.scopeView.bounds.size.width) {
            break;
        }
        int index = (i + start) % kWindowSamples;
        if (x == 0.0) {
            CGPathMoveToPoint(path, NULL, x, (1.0 + window[index]) * midY);
        } else {
            CGPathAddLineToPoint(path, NULL, x, (1.0 + window[index]) * midY);
        }
        ++x;
    }

    CAShapeLayer *shapeLayer = self.scopeView.layer.sublayers[0];
    shapeLayer.path = path;

    performFFT(self.fftSetup, window, kWindowSamples, self.frequencyData.mutableBytes);

    [CATransaction begin];
    [CATransaction setValue: (id) kCFBooleanTrue forKey: kCATransactionDisableActions];
    for (int i=0;i < kFrequencyDataLength;i++) {
        CALayer *element = _fftView.layer.sublayers[i];
        CGFloat height = MIN(((float *)self.frequencyData.bytes)[i] * _fftView.bounds.size.height + 1.0, _fftView.bounds.size.height);
        element.position = CGPointMake(element.position.x,
                                       height - (_fftView.bounds.size.height / 2.0));
    }
    [CATransaction commit];
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
    [NSGraphicsContext saveGraphicsState];
    [NSGraphicsContext setCurrentContext:nsContext];
    
    unsigned long int totalSamples = visual.buffer.length / sizeof(VisualPair);
    unsigned long int displaySampleOffset = (totalSamples * start) / visual.sample.duration;
    unsigned long int displaySampleCount = (totalSamples *  duration) / visual.sample.duration;
    
    double samplesPerPixel = displaySampleCount / size.width;
    VisualPair *data = (VisualPair *)visual.buffer.bytes;
    unsigned long int sampleIndex = displaySampleOffset;
    unsigned long int maxSampleIndex = displaySampleOffset + displaySampleCount - 1;

    double smallest = 0.0, biggest = 0.0;
    CGFloat x = 0.0;
    
    //[[NSColor underPageBackgroundColor] set];
    //1e1407
    //241809
    //503614
    [[NSColor colorWithRed:(CGFloat)0x50 / 255.0 green:(CGFloat)0x36 / 255.0 blue:(CGFloat)0x14 / 255.0 alpha:1.0] set];

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
        
        /*
             How about we store the data in something that allows for data to be
             sorted easily in chunks of `fixed`?
             We cannot presort with the current approach as our number of samples
             tested per pixel varies slightly.
             
             ??? The structure shall allow us collecting the extrema over a given amount
             of samples in ???
         */
    
        counter -= fixed;
        
        CGFloat top = mid + ((smallest * size.height) / 65535.0) - 1.0;
        CGFloat bottom = mid + ((biggest * size.height) / 65535.0) + 1.0;

        [NSBezierPath strokeLineFromPoint:NSMakePoint(x, top) toPoint:NSMakePoint(x, bottom)];

        x = x + 1.0f;
    };
   
    [NSGraphicsContext restoreGraphicsState];

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
    
   // [[NSColor systemIndigoColor] set];
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

@end
