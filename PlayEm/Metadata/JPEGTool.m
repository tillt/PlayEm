#import "JPEGTool.h"
#import <CoreImage/CoreImage.h>
#import <VideoToolbox/VideoToolbox.h>

typedef struct {
    __strong NSData *result;
    dispatch_semaphore_t sema;
} EncodeContext;

@implementation JPEGTool

+ (CVPixelBufferRef)create420PixelBuffer:(CGSize)size {
    NSDictionary* attrs = @{
        (id)kCVPixelBufferCGImageCompatibilityKey: @YES,
        (id)kCVPixelBufferCGBitmapContextCompatibilityKey: @YES,
        (id)kCVPixelBufferWidthKey: @(size.width),
        (id)kCVPixelBufferHeightKey: @(size.height),
        (id)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_420YpCbCr8BiPlanarFullRange),
    };
    CVPixelBufferRef pb = NULL;
    if (CVPixelBufferCreate(kCFAllocatorDefault,
                            size.width, size.height,
                            kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
                            (__bridge CFDictionaryRef)attrs,
                            &pb) != kCVReturnSuccess) {
        return NULL;
    }
    return pb;
}

+ (void)renderNSImage:(NSImage*)image intoPixelBuffer:(CVPixelBufferRef)pb
{
    CIImage* ciImage = [[CIImage alloc] initWithData:[image TIFFRepresentation]];
    CIContext* ctx = [CIContext contextWithOptions:nil];

    CVPixelBufferLockBaseAddress(pb, 0);
    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    [ctx render:ciImage
   toCVPixelBuffer:pb
           bounds:CGRectMake(0, 0,
                             CVPixelBufferGetWidth(pb),
                             CVPixelBufferGetHeight(pb))
       colorSpace:cs];
    if (cs) CGColorSpaceRelease(cs);
    CVPixelBufferUnlockBaseAddress(pb, 0);
}

static void JPEGCallback(void* outputCallbackRefCon,
                         void* sourceFrameRefCon,
                         OSStatus status,
                         VTEncodeInfoFlags infoFlags,
                         CMSampleBufferRef sampleBuffer)
{
    EncodeContext* ctx = (EncodeContext*)outputCallbackRefCon;
    if (status == noErr && sampleBuffer && CMSampleBufferIsValid(sampleBuffer)) {
        CMBlockBufferRef bb = CMSampleBufferGetDataBuffer(sampleBuffer);
        if (bb) {
            size_t len = CMBlockBufferGetDataLength(bb);
            NSMutableData *data = [NSMutableData dataWithLength:len];
            if (CMBlockBufferCopyDataBytes(bb, 0, len, data.mutableBytes) == kCMBlockBufferNoErr) {
                ctx->result = [data copy]; // strong retain
            }
        }
    }
    dispatch_semaphore_signal(ctx->sema);
}

+ (nullable NSData *)encodeImageToJPEG420:(NSImage*)image quality:(CGFloat)quality
{
    CVPixelBufferRef pb = [self create420PixelBuffer:image.size];
    if (pb == nil) {
        NSLog(@"failed to image in pixelbuffer");
        return nil;
    }
    [self renderNSImage:image intoPixelBuffer:pb];

    EncodeContext ctx = { .result = nil, .sema = dispatch_semaphore_create(0) };

    VTCompressionSessionRef session = NULL;
    OSStatus err = VTCompressionSessionCreate(kCFAllocatorDefault,
                                              image.size.width,
                                              image.size.height,
                                              kCMVideoCodecType_JPEG,
                                              NULL, NULL, NULL,
                                              JPEGCallback,
                                              &ctx,
                                              &session);
    if (err != noErr || !session) {
        CVPixelBufferRelease(pb);
        return nil;
    }

    VTSessionSetProperty(session,
                         kVTCompressionPropertyKey_Quality,
                         (__bridge CFTypeRef)@(quality));
    VTCompressionSessionPrepareToEncodeFrames(session);

    CMTime pts = CMTimeMake(0, 1);
    err = VTCompressionSessionEncodeFrame(session, pb, pts, kCMTimeInvalid, NULL, NULL, NULL);
    CVPixelBufferRelease(pb);

    VTCompressionSessionCompleteFrames(session, kCMTimeInvalid);
    dispatch_semaphore_wait(ctx.sema, DISPATCH_TIME_FOREVER);

    VTCompressionSessionInvalidate(session);
    CFRelease(session);

    return ctx.result;
}

#pragma mark - JPEG sampling checker

static BOOL IsSOFMarker(uint8_t marker) {
    return (marker >= 0xC0 && marker <= 0xC3) ||
           (marker >= 0xC5 && marker <= 0xC7) ||
           (marker >= 0xC9 && marker <= 0xCB) ||
           (marker >= 0xCD && marker <= 0xCF);
}

+ (BOOL)jpegIsYUV420:(NSData*)jpegData samplingInfo:(JPEGSamplingInfo*)infoOut
{
    JPEGSamplingInfo localInfo = { .isYUV420 = NO, .isJPEG = NO, .hv = {{0}} };
    const uint8_t*data = (const uint8_t*)jpegData.bytes;
    const size_t len = jpegData.length;

    if (!data || len < 4) {
        if (infoOut) *infoOut = localInfo; {
            return NO;
        }
    }

    // Hard gate: must start with JPEG SOI 0xFF 0xD8.
    localInfo.isJPEG = (data[0] == 0xFF && data[1] == 0xD8);
    if (!localInfo.isJPEG) {
        if (infoOut) {
            *infoOut = localInfo;
        }
        return NO;
    }

    size_t i = 2;
    while (i + 3 < len) {
        if (data[i] != 0xFF) {
            i++;
            continue;
        }
        uint8_t marker = data[i + 1];
        if (marker == 0xFF) {
            i++;
            continue;
        }
        if (marker == 0xD9 || marker == 0xDA) {
            break; // EOI or SOS
        }
        if (i + 4 > len) {
            break;
        }

        uint16_t segLen = ((uint16_t)data[i + 2] << 8) | data[i + 3];
        if (segLen < 2 || i + 2 + segLen > len) {
            break;
        }

        if (IsSOFMarker(marker) && segLen >= 2 + 6 + 3 * 3) {
            uint8_t comps = data[i + 9];
            if (comps < 3) {
                if (infoOut) {
                    *infoOut = localInfo;
                    return NO;
                }
            }
            // SOF layout: precision, height, width, components…
            localInfo.height = ((uint16_t)data[i + 5] << 8) | data[i + 6];
            localInfo.width  = ((uint16_t)data[i + 7] << 8) | data[i + 8];
            
            uint8_t hv1 = data[i + 11];
            uint8_t hv2 = data[i + 14];
            uint8_t hv3 = data[i + 17];
            localInfo.hv[0][0] = hv1 >> 4; localInfo.hv[0][1] = hv1 & 0x0F;
            localInfo.hv[1][0] = hv2 >> 4; localInfo.hv[1][1] = hv2 & 0x0F;
            localInfo.hv[2][0] = hv3 >> 4; localInfo.hv[2][1] = hv3 & 0x0F;
            localInfo.isYUV420 = (localInfo.hv[0][0] == 2 && localInfo.hv[0][1] == 2 &&
                                  localInfo.hv[1][0] == 1 && localInfo.hv[1][1] == 1 &&
                                  localInfo.hv[2][0] == 1 && localInfo.hv[2][1] == 1);
            if (infoOut) {
                *infoOut = localInfo;
            }
            return localInfo.isYUV420;
        }
        i += 2 + segLen;
    }
    if (infoOut) {
        *infoOut = localInfo;
    }
    return NO;
}

+ (BOOL)jpegIsYUV420:(NSData *)jpegData {
    return [self jpegIsYUV420:jpegData samplingInfo:NULL];
}

@end
