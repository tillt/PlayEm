//
//  WaveRenderer.m
//  PlayEm
//
//  Created by Till Toenshoff on 21.01.24.
//  Copyright © 2024 Till Toenshoff. All rights reserved.
//

#import "WaveRenderer.h"
#import <MetalPerformanceShaders/MetalPerformanceShaders.h>

#import "GraphicsTools.h"
#import "ShaderTypes.h"
#import "MatrixUtilities.h"
#import "WaveShaderTypes.h"

static const NSUInteger kMaxBuffersInFlight = 3;
static const size_t kAlignedUniformsSize = (sizeof(WaveUniforms) & ~0xFF) + 0x100;


@interface WaveRenderer ()

@property (weak, nonatomic) AudioController* audio;
@property (weak, nonatomic) VisualSample* visual;

@property (strong, nonatomic) NSColor* color;
@property (strong, nonatomic) NSColor* background;

@property (strong, nonatomic) NSMutableArray* blockSourceChannelData;
@property (strong, nonatomic) NSMutableData* blockFrequencyData;

@property (weak, nonatomic) id<WaveRendererDelegate> delegate;

@end


@implementation WaveRenderer
{
    // Texture to render to and then sample from.
    id<MTLTexture> _waveTargetTexture;

    // Texture to render to and then sample from.
    id<MTLTexture> _waveMSAATexture;

    // Render pass descriptor to draw the scope to a texture.
    MTLRenderPassDescriptor* _wavePass;
    // A pipeline object to render to the offscreen texture.
    id<MTLRenderPipelineState> _waveState;

    // Render pass descriptor to draw the texture to screen.
    MTLRenderPassDescriptor* _drawPass;
    // A pipeline object to render to screen.
    id<MTLRenderPipelineState> _drawState;
    
    // Ratio of width to height to scale positions in the vertex shader.
    float _aspe_lineWidthctRatio;
    
    float _lineWidth;

    dispatch_semaphore_t _inFlightSemaphore;
    id <MTLDevice> _device;
    id <MTLCommandQueue> _commandQueue;

    id <MTLBuffer> _dynamicUniformBuffer;
    id <MTLBuffer> _linesUniformBuffer;
    
    MTLVertexDescriptor* _mtlVertexDescriptor;
    
    MPSImageBox* _bloom;
    MPSImageAreaMin* _erode;
    MPSImageGaussianBlur* _blur;

    uint32_t _uniformBufferOffset;
    uint32_t _sampleBufferOffset;
    uint32_t _frequencyBufferOffset;
    uint32_t _linesBufferOffset;

    uint32_t _msaaCount;
    
    size_t _sampleCount;
    size_t _sampleStepping;
    
    size_t _alignedUSamplesSize;
    size_t _alignedULinesSize;

    size_t _minTriggerOffset;

    uint8_t _uniformBufferIndex;

    void *_uniformBufferAddress;
    void *_sampleBufferAddress;
    void *_linesBufferAddress;

    matrix_float4x4 _projectionMatrix;
    matrix_float4x4 _feedbackProjectionMatrix;
    vector_float4 _feedbackColorFactor;
    
    float _rotation;
    float _lineAspectRatio;
    
    // WORKLOAD DATA
    
    NSMutableArray<NSData*>* _sourceChannelData;
    float** _source;
}

static NSSize _originalSize __attribute__((unused)) = {0.0,0.0};

-(nonnull instancetype)initWithMetalKitView:(nonnull MTKView *)view
                                      color:(NSColor*)color
                                 background:(NSColor*)background
                                   delegate:(id<WaveRendererDelegate>)delegate
{
    self = [super init];
    if(self)
    {
        _sampleCount = 1000;
        //_frequencyCount = 256;
        _device = view.device;
        _color = color;
        _msaaCount = 4;
        _background = background;
        _lineWidth = 0.0f;
        _lineAspectRatio = 0.0f;
        _inFlightSemaphore = dispatch_semaphore_create(kMaxBuffersInFlight);

        [self mtkView:view drawableSizeWillChange:view.frame.size];

        _delegate = delegate;
        
        [self _loadMetalWithView:view];
        
        _commandQueue = [_device newCommandQueue];

        //[self _buildMesh];
    }
    return self;
}


- (void)_loadMetalWithView:(nonnull MTKView*)view;
{
    assert(view.frame.size.width * view.frame.size.height);
    NSError *error;

    /// Load Metal state objects and initalize renderer dependent view properties.
    view.colorPixelFormat = MTLPixelFormatBGRA8Unorm;
    view.sampleCount = 1;
    view.clearColor = [GraphicsTools MetalClearColorFromColor:_background];
    view.paused = NO;
    view.framebufferOnly = YES;
    
    // Set up a texture for rendering to and sampling from
    MTLTextureDescriptor *texDescriptor = [MTLTextureDescriptor new];
    texDescriptor.textureType = MTLTextureType2D;
    texDescriptor.storageMode = MTLStorageModePrivate;
    texDescriptor.width = view.drawableSize.width;
    texDescriptor.height = view.drawableSize.height;
    texDescriptor.pixelFormat = MTLPixelFormatRGBA8Unorm;
    texDescriptor.usage = MTLTextureUsageRenderTarget | MTLTextureUsageShaderRead;

    id<MTLLibrary> defaultLibrary = [_device newDefaultLibrary];

    // Set up pipeline for rendering to screen.
    MTLRenderPipelineDescriptor *pipelineStateDescriptor = [[MTLRenderPipelineDescriptor alloc] init];
    pipelineStateDescriptor.label = @"Drawable Render Pipeline";
    pipelineStateDescriptor.rasterSampleCount = view.sampleCount;
    pipelineStateDescriptor.vertexFunction =  [defaultLibrary newFunctionWithName:@"projectTexture"];
    pipelineStateDescriptor.fragmentFunction =  [defaultLibrary newFunctionWithName:@"drawableTextureFragmentShader"];
    pipelineStateDescriptor.colorAttachments[0].pixelFormat = view.colorPixelFormat;
    pipelineStateDescriptor.colorAttachments[0].blendingEnabled = YES;
    pipelineStateDescriptor.colorAttachments[0].rgbBlendOperation = MTLBlendOperationAdd;
    pipelineStateDescriptor.colorAttachments[0].alphaBlendOperation = MTLBlendOperationAdd;
    pipelineStateDescriptor.colorAttachments[0].sourceRGBBlendFactor = MTLBlendFactorOne;
    pipelineStateDescriptor.colorAttachments[0].sourceAlphaBlendFactor = MTLBlendFactorSourceAlpha;
    pipelineStateDescriptor.colorAttachments[0].destinationRGBBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
    pipelineStateDescriptor.colorAttachments[0].destinationAlphaBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
    _drawState = [_device newRenderPipelineStateWithDescriptor:pipelineStateDescriptor error:&error];
    NSAssert(_drawState, @"Failed to create pipeline state to render to screen: %@", error);
    
    texDescriptor.sampleCount = _msaaCount;
    texDescriptor.storageMode = MTLStorageModePrivate;
    texDescriptor.textureType = _msaaCount > 1 ? MTLTextureType2DMultisample : MTLTextureType2D;

    _waveMSAATexture = [_device newTextureWithDescriptor:texDescriptor];

    texDescriptor.sampleCount = 1;
    texDescriptor.textureType = MTLTextureType2D;

    // Set up a render pass descriptor for the render pass to render into _scopeTargetTexture.
    _waveTargetTexture = [_device newTextureWithDescriptor:texDescriptor];
        
    // FIXME: MSAA count alternative code is rubbish -- currently only works with MSAA > 1

    _wavePass = [[MTLRenderPassDescriptor alloc] init];
    _wavePass.colorAttachments[0].texture = _waveMSAATexture;
    _wavePass.colorAttachments[0].loadAction = MTLLoadActionClear;
    _wavePass.colorAttachments[0].clearColor = MTLClearColorMake(0.0, 0.0, 0.0, 0.0);
    _wavePass.colorAttachments[0].storeAction = _msaaCount > 1 ? MTLStoreActionMultisampleResolve : MTLStoreActionStore;
    _wavePass.colorAttachments[0].resolveTexture = _waveTargetTexture;

    // Set up pipeline for rendering the scope to the offscreen texture. Reuse the
    // descriptor and change properties that differ.
    pipelineStateDescriptor.label = @"Offscreen Scope Render Pipeline";
    pipelineStateDescriptor.rasterSampleCount = _msaaCount;
    //pipelineStateDescriptor.vertexFunction = [defaultLibrary newFunctionWithName:@"scopeInstanceShader"];
    pipelineStateDescriptor.vertexFunction = [defaultLibrary newFunctionWithName:@"polySegmentInstanceShader"];
    pipelineStateDescriptor.fragmentFunction = [defaultLibrary newFunctionWithName:@"scopeFragmentShader"];
    pipelineStateDescriptor.colorAttachments[0].pixelFormat = _waveTargetTexture.pixelFormat;
    pipelineStateDescriptor.colorAttachments[0].blendingEnabled = YES;
    pipelineStateDescriptor.colorAttachments[0].rgbBlendOperation = MTLBlendOperationAdd;
    pipelineStateDescriptor.colorAttachments[0].alphaBlendOperation = MTLBlendOperationAdd;
    pipelineStateDescriptor.colorAttachments[0].sourceRGBBlendFactor = MTLBlendFactorSourceAlpha;
    pipelineStateDescriptor.colorAttachments[0].sourceAlphaBlendFactor = MTLBlendFactorSourceAlpha;
    pipelineStateDescriptor.colorAttachments[0].destinationRGBBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
    pipelineStateDescriptor.colorAttachments[0].destinationAlphaBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
    _waveState = [_device newRenderPipelineStateWithDescriptor:pipelineStateDescriptor error:&error];
    NSAssert(_waveState, @"Failed to create pipeline state to render the scope to a texture: %@", error);

    // Create offscreen textures for:
    // - last results for feedback
    // - previous results for feedback
    // - last frequencies
    texDescriptor.usage = MTLTextureUsageShaderWrite | MTLTextureUsageShaderRead;

    NSUInteger uniformBufferSize = kAlignedUniformsSize * kMaxBuffersInFlight;
    _dynamicUniformBuffer = [_device newBufferWithLength:uniformBufferSize
                                                 options:MTLResourceStorageModeShared];
    _dynamicUniformBuffer.label = @"UniformBuffer";

    _alignedULinesSize = ((_sampleCount * sizeof(PolyNode)) & ~0xFF) + 0x100;
    NSUInteger linesBufferSize = _alignedULinesSize;
    _linesUniformBuffer = [_device newBufferWithLength:linesBufferSize
                                               options:MTLResourceStorageModeShared];
    _linesUniformBuffer.label = @"LinesBuffer";
    
    _linesBufferAddress = (uint8_t *)_linesUniformBuffer.contents;
}

#pragma mark - MTKViewDelegate


- (void)mtkView:(nonnull MTKView *)view drawableSizeWillChange:(CGSize)size
{
    /// Respond to drawable size or orientation changes here
    ///
    ///
    
    float widthFactor = size.width / view.bounds.size.width;
    float heightFactor = size.height / view.bounds.size.height;
    
    _lineAspectRatio = size.height / size.width;
    
    _lineWidth = 3.0f / size.height;

    float sigma = ScaleWithOriginalFrame(0.7f, _originalSize.width, size.width);
    _blur = [[MPSImageGaussianBlur alloc] initWithDevice:_device sigma:sigma];
    _blur.edgeMode = MPSImageEdgeModeClamp;
//    float width = (((ceil(scaleWithOriginalFrame(5.0f, _originalSize.height, _originalSize.height + size.height / 50.0f))) / 2) * 2) + 1;
//    float height = (((ceil(scaleWithOriginalFrame(3.0f, _originalSize.height, _originalSize.height + size.height / 50.0f))) / 2) * 2) + 1;
//    float width = (((ceil(scaleWithOriginalFrame(5.0f, _originalSize.height, size.height))) / 2) * 2) + 1;
//    float height = (((ceil(scaleWithOriginalFrame(3.0f, _originalSize.height, size.height))) / 2) * 2) + 1;

//    float width = (((ceil(scaleWithOriginalFrame(5.0f, _originalSize.height * _originalSize.width, size.height * size.width))) / 2) * 2) + 1;
//    float height = (((ceil(scaleWithOriginalFrame(3.0f, _originalSize.height * _originalSize.width, size.height * size.width))) / 2) * 2) + 1;
      float width = (((ceil(ScaleWithOriginalFrame(3.0f, _originalSize.height, _originalSize.height + (size.height/30) ))) / 2) * 2) + 1;
      float height = (((ceil(ScaleWithOriginalFrame(3.0f, _originalSize.height, _originalSize.height + (size.height/30) ))) / 2) * 2) + 1;
//    float width = 5.0f;
//    float height = 3.0f;

    _erode = [[MPSImageAreaMin alloc] initWithDevice:_device kernelWidth:width kernelHeight:height];
//    width = ((((int)ceil(scaleWithOriginalFrame(31.0f, _originalSize.height, _originalSize.height + size.height / 50.0f))) / 2) * 2) + 1;
//    height = ((((int)ceil(scaleWithOriginalFrame(17.0f, _originalSize.height, _originalSize.height + size.height / 50.0f))) / 2) * 2) + 1;
//    width = ((((int)ceil(scaleWithOriginalFrame(31.0f, _originalSize.height, _originalSize.height + (size.height / 2.0)))) / 2) * 2) + 1;
//    height = ((((int)ceil(scaleWithOriginalFrame(17.0f, _originalSize.height, _originalSize.height + ( size.height / 2.0)))) / 2) * 2) + 1;

    //width = ((((int)ceil(scaleWithOriginalFrame(31.0f, _originalSize.height, _originalSize.height))) / 2) * 2) + 1;
//    width = ((((int)ceil(scaleWithOriginalFrame(17.0f, _originalSize.height * _originalSize.width, size.height * size.width))) / 2) * 2) + 1;
//    height = ((((int)ceil(scaleWithOriginalFrame(17.0f, _originalSize.height * _originalSize.width, size.height * size.width))) / 2) * 2) + 1;

    width = ((((int)ceil(ScaleWithOriginalFrame(17.0f, _originalSize.height, _originalSize.height + (size.height/30) ))) / 2) * 2) + 1;
    height = ((((int)ceil(ScaleWithOriginalFrame(17.0f, _originalSize.height, _originalSize.height + (size.height/30) ))) / 2) * 2) + 1;

    _bloom = [[MPSImageBox alloc] initWithDevice:_device kernelWidth:width kernelHeight:height];
    
    _projectionMatrix = matrix_orthographic(-size.width, size.width, size.height, -size.height, 0, 0);
    _projectionMatrix = matrix_multiply(matrix4x4_scale(1.0f, _lineAspectRatio, 0.0), _projectionMatrix);
    _projectionMatrix = matrix_multiply(matrix4x4_scale(widthFactor, heightFactor, 0.0), _projectionMatrix);
}

- (void)drawInMTKView:(nonnull MTKView *)view
{
    ///
    /// Per frame updates here
    ///

    dispatch_semaphore_wait(_inFlightSemaphore, DISPATCH_TIME_FOREVER);

    id <MTLCommandBuffer> commandBuffer = [_commandQueue commandBuffer];
    commandBuffer.label = @"Scope Command Buffer";

    __block dispatch_semaphore_t block_sema = _inFlightSemaphore;
    [commandBuffer addCompletedHandler:^(id<MTLCommandBuffer> buffer) {
        dispatch_semaphore_signal(block_sema);
    }];
    
    
//    [self _updateDynamicBufferState];
//    [self _updateEngine];
    
    
    {
        /// First pass rendering code: Drawing the wave lines.

        id<MTLRenderCommandEncoder> renderEncoder = [commandBuffer renderCommandEncoderWithDescriptor:_wavePass];

        renderEncoder.label = @"Wave Texture Render Pass";

        [renderEncoder setFrontFacingWinding:MTLWindingCounterClockwise];
        [renderEncoder setCullMode:MTLCullModeFront];
        [renderEncoder setRenderPipelineState:_waveState];

        [renderEncoder setVertexBuffer:_dynamicUniformBuffer
                                offset:_uniformBufferOffset
                               atIndex:BufferIndexUniforms];

        [renderEncoder setFragmentBuffer:_dynamicUniformBuffer
                                  offset:_uniformBufferOffset
                                 atIndex:BufferIndexUniforms];

        [renderEncoder setVertexBuffer:_linesUniformBuffer
                                offset:_linesBufferOffset
                               atIndex:BufferIndexScopeLines];
     
        [renderEncoder drawPrimitives:MTLPrimitiveTypeTriangleStrip
                          vertexStart:0
                          vertexCount:5
                        instanceCount:(_sampleCount + (_sampleStepping - 1))/ _sampleStepping];

        [renderEncoder endEncoding];
    }



    /// Delay getting the currentRenderPassDescriptor until we absolutely need it to avoid
    ///   holding onto the drawable and blocking the display pipeline any longer than necessar
    MTLRenderPassDescriptor* renderPassDescriptor = view.currentRenderPassDescriptor;

    if(renderPassDescriptor != nil) {

        /// Final pass rendering code: Display on screen.
        id<MTLRenderCommandEncoder> renderEncoder =
            [commandBuffer renderCommandEncoderWithDescriptor:renderPassDescriptor];
        renderEncoder.label = @"Drawable Render Pass";

        [renderEncoder setRenderPipelineState:_drawState];

        // Use the "dry signal" to mix on top of our fading.
        [renderEncoder setFragmentTexture:_waveTargetTexture atIndex:TextureIndexWave];

        // Draw quad with rendered texture.
        [renderEncoder drawPrimitives:MTLPrimitiveTypeTriangleStrip
                          vertexStart:0
                          vertexCount:4];

        [renderEncoder endEncoding];
  
        [commandBuffer presentDrawable:view.currentDrawable];
    }

    [commandBuffer commit];
}
@end
