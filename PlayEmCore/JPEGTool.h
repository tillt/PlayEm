#import <Foundation/Foundation.h>

#import <AppKit/AppKit.h>

typedef struct {
    BOOL isJPEG;
    BOOL isYUV420;
    uint8_t hv[3][2];  // [component][H/V], 0=Luma, 1=Cb, 2=Cr
    uint16_t width;    // parsed from SOF
    uint16_t height;   // parsed from SOF
} JPEGSamplingInfo;

@interface JPEGTool : NSObject

/// Encode an NSImage to JPEG with YUV420 sampling. Returns nil on failure.
+ (nullable NSData*)encodeImageToJPEG420:(NSImage* _Nonnull)image quality:(CGFloat)quality;  // 0.0–1.0

/// Check if a JPEG (NSData) is YUV420. Optionally fills samplingInfo.
+ (BOOL)isJPEGYUV420:(NSData* _Nonnull)jpegData samplingInfo:(JPEGSamplingInfo* _Nullable)infoOut;

+ (BOOL)isJPEGYUV420:(NSData* _Nonnull)jpegData;

@end
