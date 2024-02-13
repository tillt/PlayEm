//
//  WaveTile.m
//  PlayEm
//
//  Created by Till Toenshoff on 31.01.24.
//  Copyright © 2024 Till Toenshoff. All rights reserved.
//

#import "WaveTile.h"
#import "VisualPair.h"

@implementation WaveTile
{
    id<MTLDevice> _device;
}

static int _bufferIndex = 0;

-(nonnull instancetype)initWithDevice:(id<MTLDevice>)device size:(NSSize)size
{
    self = [super init];
    if(self)
    {
        _device = device;
        
        size_t alignedSize = ((size_t)(size.width + 1) * sizeof(VisualPair) & ~0xFF) + 0x100;
        _pairsBuffer = [_device newBufferWithLength:alignedSize options:MTLResourceStorageModeShared];
        _pairsBuffer.label = [NSString stringWithFormat:@"PairsBufferTile%d", _bufferIndex];
        
        MTLTextureDescriptor *texDescriptor = [MTLTextureDescriptor new];
        texDescriptor.textureType = MTLTextureType2D;
        texDescriptor.storageMode = MTLStorageModePrivate;
        texDescriptor.width = size.width + 1.0;
        texDescriptor.height = size.height;
        texDescriptor.pixelFormat = MTLPixelFormatRGBA8Unorm;
        texDescriptor.usage = MTLTextureUsageShaderRead | MTLTextureUsageShaderWrite;
        texDescriptor.sampleCount = 1;

        _frame = CGRectMake(0.0, 0.0, size.width + 1.0, size.height);
        _texture = [_device newTextureWithDescriptor:texDescriptor];
        _texture.label = [NSString stringWithFormat:@"WaveTileTexture%d", _bufferIndex];

        _bufferIndex++;

        _needsDisplay = NO;
    }
    return self;
}

- (void)copyFromData:(NSData*)source
{
    VisualPair* data = (VisualPair*)source.bytes;
    memcpy(_pairsBuffer.contents, data, source.length);
    _needsDisplay = YES;
}

@end
