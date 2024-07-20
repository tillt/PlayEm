//
//  WaveRenderer.m
//  PlayEm
//
//  Created by Till Toenshoff on 21.01.24.
//  Copyright © 2024 Till Toenshoff. All rights reserved.
//

#import "WaveRenderer.h"

#import <CoreGraphics/CoreGraphics.h>
#import <MetalPerformanceShaders/MetalPerformanceShaders.h>

#import "GraphicsTools.h"
#import "ShaderTypes.h"
#import "MatrixUtilities.h"
#import "WaveShaderTypes.h"
#import "AudioController.h"
#import "VisualSample.h"
#import "VisualPair.h"
#import "LazySample.h"
#import "WaveTile.h"
#import "MetalWaveView.h"

static const NSUInteger kMaxBuffersInFlight = 2;
static const size_t kAlignedUniformsSize = (sizeof(WaveUniforms) & ~0xFF) + 0x100;
static const size_t kMetalWaveViewTileWidth = 256;


@interface WaveRenderer ()

@property (weak, nonatomic) AudioController* audio;

@property (strong, nonatomic) NSColor* color;
@property (strong, nonatomic) NSColor* background;

@property (strong, nonatomic) NSMutableArray* blockSourceChannelData;
@property (strong, nonatomic) NSMutableData* blockFrequencyData;

@property (weak, nonatomic) id<WaveRendererDelegate> delegate;

@end


@implementation WaveRenderer
{
    MetalWaveView* _view;

    NSMutableArray<WaveTile*>* _reusableTiles;
    NSMutableArray<WaveTile*>* _visibleTiles;
    
    // Texture to render to and then sample from.
    id<MTLTexture> _waveTargetTexture;

    // Texture to render to and then sample from.
    id<MTLTexture> _waveMSAATexture;
    
    // Texture to compose onto and then sample from.
    id<MTLTexture> _composeTargetTexture;
    
    id<MTLTexture> _composeOverlayTexture;

    id<MTLTexture> _composeCurrentTimeTexture;

    NSSize _tileSize;

    MTLRenderPassDescriptor* _tilePass;
    id<MTLRenderPipelineState> _tileState;

    MTLRenderPassDescriptor* _wavePass;
    id<MTLRenderPipelineState> _waveState;
    
    MTLRenderPassDescriptor* _currentTimePass;
    id<MTLRenderPipelineState> _currentTimeState;

    MTLRenderPassDescriptor* _composePass;
    id<MTLRenderPipelineState> _composeState;

    MTLRenderPassDescriptor* _drawPass;
    id<MTLRenderPipelineState> _drawState;

    float _lineWidth;

    dispatch_semaphore_t _inFlightSemaphore;
    id <MTLDevice> _device;
    id <MTLCommandQueue> _commandQueue;

    id <MTLBuffer> _dynamicUniformBuffer;
    id <MTLBuffer> _visualPairsUniformBuffer;

    uint32_t _uniformBufferOffset;

    uint32_t _msaaCount;

    size_t _sampleStepping;
    
    uint8_t _uniformBufferIndex;
    void* _uniformBufferAddress;

    matrix_float4x4 _projectionMatrix;
    matrix_float4x4 _feedbackProjectionMatrix;
    vector_float4 _feedbackColorFactor;
    
    float _rotation;
    float _lineAspectRatio;
    
    MPSImageBox* _bloom;
    MPSImageAreaMin* _erode;
    MPSImageGaussianBlur* _blur;
    
    // WORKLOAD DATA
}

static NSSize _originalSize __attribute__((unused)) = {0.0,0.0};

-(nonnull instancetype)initWithView:(MetalWaveView *)view
                              color:(NSColor*)color
                         background:(NSColor*)background
                           delegate:(id<WaveRendererDelegate>)delegate
{
    self = [super init];
    if(self)
    {
        //_frequencyCount = 256;
        _device = view.device;
        _color = color;
        _msaaCount = 4;
        _background = background;
        _lineWidth = 0.0f;
        _lineAspectRatio = 0.0f;
        _inFlightSemaphore = dispatch_semaphore_create(kMaxBuffersInFlight);
        _view = view;
        view.waveRenderer = self;
       
        _tileSize = NSMakeSize(kMetalWaveViewTileWidth, view.bounds.size.height);
        
        _visibleTiles = [NSMutableArray new];
        _reusableTiles = [NSMutableArray new];

        if (_originalSize.width == 0.0f) {
            _originalSize.width = view.frame.size.width;
            _originalSize.height = view.frame.size.height;
        }
        [self mtkView:view drawableSizeWillChange:view.frame.size];

        _delegate = delegate;
        
        [self _loadMetalWithView:view];
        
        _commandQueue = [_device newCommandQueue];
        _commandQueue.label = @"Wave Command Queue";
        
        view.paused = YES;
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
    view.framebufferOnly = YES;
    
    MTLTextureDescriptor* texDescriptor = [MTLTextureDescriptor new];
    texDescriptor.textureType = MTLTextureType2D;
    texDescriptor.storageMode = MTLStorageModePrivate;
    texDescriptor.width = view.drawableSize.width;
    texDescriptor.height = view.drawableSize.height;
    texDescriptor.pixelFormat = MTLPixelFormatRGBA8Unorm;
    texDescriptor.usage = MTLTextureUsageRenderTarget;
    texDescriptor.sampleCount = 1;
    
    _waveMSAATexture = [_device newTextureWithDescriptor:texDescriptor];
    
    texDescriptor.sampleCount = 1;
    texDescriptor.textureType = MTLTextureType2D;
    texDescriptor.usage = MTLTextureUsageShaderWrite | MTLTextureUsageShaderRead | MTLTextureUsageRenderTarget;

    _waveTargetTexture = [_device newTextureWithDescriptor:texDescriptor];
    _waveTargetTexture.label = @"WaveTargetTexture";

    texDescriptor.usage = MTLTextureUsageShaderWrite | MTLTextureUsageShaderRead | MTLTextureUsageRenderTarget;

    _composeTargetTexture = [_device newTextureWithDescriptor:texDescriptor];
    _composeTargetTexture.label = @"ComposeTargetTexture";

    _composeOverlayTexture = [self _loadTextureWithDevice:view.device imageName:@"RastaPattern"];
    _composeOverlayTexture.label = @"ComposeOverlayTexture";

    _composeCurrentTimeTexture = [self _loadTextureWithDevice:view.device imageName:@"TotalCurrentTime"];
    _composeCurrentTimeTexture.label = @"ComposeCurrentTimeTexture";

    id<MTLLibrary> defaultLibrary = [_device newDefaultLibrary];
    
    // Set up pipeline for rendering to screen.
    MTLRenderPipelineDescriptor* pipelineStateDescriptor = [[MTLRenderPipelineDescriptor alloc] init];
    pipelineStateDescriptor.label = @"Drawable Wave Render Pipeline";
    pipelineStateDescriptor.rasterSampleCount = view.sampleCount;
    pipelineStateDescriptor.vertexFunction = [defaultLibrary newFunctionWithName:@"projectTexture"];
    pipelineStateDescriptor.fragmentFunction = [defaultLibrary newFunctionWithName:@"waveDrawableTextureFragmentShader"];
    pipelineStateDescriptor.colorAttachments[0].pixelFormat = view.colorPixelFormat;
    pipelineStateDescriptor.colorAttachments[0].blendingEnabled = YES;
    pipelineStateDescriptor.colorAttachments[0].rgbBlendOperation = MTLBlendOperationAdd;
    pipelineStateDescriptor.colorAttachments[0].alphaBlendOperation = MTLBlendOperationAdd;
    pipelineStateDescriptor.colorAttachments[0].sourceRGBBlendFactor = MTLBlendFactorOne;
    pipelineStateDescriptor.colorAttachments[0].sourceAlphaBlendFactor = MTLBlendFactorSourceAlpha;
    pipelineStateDescriptor.colorAttachments[0].destinationRGBBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
    pipelineStateDescriptor.colorAttachments[0].destinationAlphaBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
    _drawState = [_device newRenderPipelineStateWithDescriptor:pipelineStateDescriptor error:&error];
    NSAssert(_drawState, @"Failed to create pipeline state to render result to screen: %@", error);
    
    // FIXME: MSAA count alternative code is rubbish -- currently only works with MSAA > 1
    
    _tilePass = [[MTLRenderPassDescriptor alloc] init];
    _tilePass.colorAttachments[0].loadAction = MTLLoadActionClear;
    _tilePass.colorAttachments[0].clearColor = MTLClearColorMake(0.0, 0.0, 0.0, 0.0);
    _tilePass.colorAttachments[0].storeAction = MTLStoreActionStore;

    {
        pipelineStateDescriptor.label = @"Wave Tiles Render Pipeline";
        pipelineStateDescriptor.rasterSampleCount = 1;
        pipelineStateDescriptor.vertexFunction = [defaultLibrary newFunctionWithName:@"waveTileVertexShader"];
        pipelineStateDescriptor.fragmentFunction = [defaultLibrary newFunctionWithName:@"waveTileFragmentShader"];
        pipelineStateDescriptor.colorAttachments[0].pixelFormat = _waveTargetTexture.pixelFormat;
        pipelineStateDescriptor.colorAttachments[0].blendingEnabled = YES;
        pipelineStateDescriptor.colorAttachments[0].rgbBlendOperation = MTLBlendOperationAdd;
        pipelineStateDescriptor.colorAttachments[0].alphaBlendOperation = MTLBlendOperationAdd;
        pipelineStateDescriptor.colorAttachments[0].sourceRGBBlendFactor = MTLBlendFactorOne;
        pipelineStateDescriptor.colorAttachments[0].sourceAlphaBlendFactor = MTLBlendFactorSourceAlpha;
        pipelineStateDescriptor.colorAttachments[0].destinationRGBBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
        pipelineStateDescriptor.colorAttachments[0].destinationAlphaBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
        _tileState = [_device newRenderPipelineStateWithDescriptor:pipelineStateDescriptor error:&error];
        NSAssert(_tileState, @"Failed to create pipeline state to render the wave tile to a texture: %@", error);
    }
    
    // Set up a render pass descriptor for the render pass to render into _composeTargetTexture.

    _wavePass = [[MTLRenderPassDescriptor alloc] init];
    _wavePass.colorAttachments[0].texture = _waveTargetTexture;
    _wavePass.colorAttachments[0].loadAction = MTLLoadActionClear;
    _wavePass.colorAttachments[0].clearColor = MTLClearColorMake(0.0, 0.0, 0.0, 0.0);
    _wavePass.colorAttachments[0].storeAction = MTLStoreActionStore;

    // Set up pipeline for rendering to the offscreen texture.
    {
        pipelineStateDescriptor.label = @"Wave Project Render Pipeline";
        pipelineStateDescriptor.rasterSampleCount = 1;
        pipelineStateDescriptor.vertexFunction = [defaultLibrary newFunctionWithName:@"waveProjectTextureVertexShader"];
        pipelineStateDescriptor.fragmentFunction = [defaultLibrary newFunctionWithName:@"waveProjectTextureFragmentShader"];
        pipelineStateDescriptor.colorAttachments[0].pixelFormat = _waveTargetTexture.pixelFormat;
        pipelineStateDescriptor.colorAttachments[0].sourceRGBBlendFactor = MTLBlendFactorOne;
        pipelineStateDescriptor.colorAttachments[0].sourceAlphaBlendFactor = MTLBlendFactorSourceAlpha;
        pipelineStateDescriptor.colorAttachments[0].destinationRGBBlendFactor = MTLBlendFactorOne;
        _waveState = [_device newRenderPipelineStateWithDescriptor:pipelineStateDescriptor error:&error];
        NSAssert(_waveState, @"Failed to create pipeline state to compose wave textures to a texture: %@", error);
    }
    
    _currentTimePass = [[MTLRenderPassDescriptor alloc] init];
    _currentTimePass.colorAttachments[0].texture = _waveTargetTexture;
    _currentTimePass.colorAttachments[0].loadAction = MTLLoadActionLoad;
    _currentTimePass.colorAttachments[0].clearColor = MTLClearColorMake(0.0, 0.0, 0.0, 0.0);
    _currentTimePass.colorAttachments[0].storeAction = MTLStoreActionStore;

    {
        pipelineStateDescriptor.label = @"Wave Current Time Render Pipeline";
        pipelineStateDescriptor.rasterSampleCount = 1;
        pipelineStateDescriptor.vertexFunction = [defaultLibrary newFunctionWithName:@"waveCurrentTimeTextureVertexShader"];
        pipelineStateDescriptor.fragmentFunction = [defaultLibrary newFunctionWithName:@"waveCurrentTimeTextureFragmentShader"];
        pipelineStateDescriptor.colorAttachments[0].pixelFormat = _waveTargetTexture.pixelFormat;

        pipelineStateDescriptor.colorAttachments[0].rgbBlendOperation = MTLBlendOperationAdd;
        pipelineStateDescriptor.colorAttachments[0].alphaBlendOperation = MTLBlendOperationAdd;
        pipelineStateDescriptor.colorAttachments[0].sourceRGBBlendFactor = MTLBlendFactorOne;
        pipelineStateDescriptor.colorAttachments[0].sourceAlphaBlendFactor = MTLBlendFactorSourceAlpha;
        pipelineStateDescriptor.colorAttachments[0].destinationRGBBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
        pipelineStateDescriptor.colorAttachments[0].destinationAlphaBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
        _currentTimeState = [_device newRenderPipelineStateWithDescriptor:pipelineStateDescriptor error:&error];
        NSAssert(_currentTimeState, @"Failed to create pipeline state to current time wave to a texture: %@", error);
    }
    
    _composePass = [[MTLRenderPassDescriptor alloc] init];
    _composePass.colorAttachments[0].texture = _composeTargetTexture;
    _composePass.colorAttachments[0].loadAction = MTLLoadActionLoad;
    _composePass.colorAttachments[0].clearColor = MTLClearColorMake(0.0, 0.0, 0.0, 0.0);
    _composePass.colorAttachments[0].storeAction = MTLStoreActionStore;

    // Set up pipeline for rendering to the offscreen texture.
    {
        pipelineStateDescriptor.label = @"Wave Compose Render Pipeline";
        pipelineStateDescriptor.rasterSampleCount = 1;
        pipelineStateDescriptor.vertexFunction = [defaultLibrary newFunctionWithName:@"waveOverlayComposeTextureVertexShader"];
        pipelineStateDescriptor.fragmentFunction = [defaultLibrary newFunctionWithName:@"waveOverlayComposeTextureFragmentShader"];
        pipelineStateDescriptor.colorAttachments[0].pixelFormat = _composeTargetTexture.pixelFormat;
        pipelineStateDescriptor.colorAttachments[0].rgbBlendOperation = MTLBlendOperationAdd;
        pipelineStateDescriptor.colorAttachments[0].alphaBlendOperation = MTLBlendOperationAdd;
        pipelineStateDescriptor.colorAttachments[0].sourceRGBBlendFactor = MTLBlendFactorOne;
        pipelineStateDescriptor.colorAttachments[0].sourceAlphaBlendFactor = MTLBlendFactorSourceAlpha;
        pipelineStateDescriptor.colorAttachments[0].destinationRGBBlendFactor = MTLBlendFactorDestinationColor;
        pipelineStateDescriptor.colorAttachments[0].destinationAlphaBlendFactor = MTLBlendFactorOneMinusDestinationAlpha;
        _composeState = [_device newRenderPipelineStateWithDescriptor:pipelineStateDescriptor error:&error];
        NSAssert(_composeState, @"Failed to create pipeline state to compose wave to a texture: %@", error);
    }
    
    //width = ((((int)ceil(ScaleWithOriginalFrame(17.0f, _originalSize.height, _originalSize.height + (size.height/30) ))) / 2) * 2) + 1;
    //height = ((((int)ceil(ScaleWithOriginalFrame(17.0f, _originalSize.height, _originalSize.height + (size.height/30) ))) / 2) * 2) + 1;
    float width = 7.0;
    float height = 13.0;

    _bloom = [[MPSImageBox alloc] initWithDevice:_device kernelWidth:width kernelHeight:height];

    _dynamicUniformBuffer = [_device newBufferWithLength:kAlignedUniformsSize * kMaxBuffersInFlight
                                                 options:MTLResourceStorageModeShared];
    _dynamicUniformBuffer.label = @"UniformBuffer";
}

- (id<MTLTexture>)_loadTextureWithDevice:(id<MTLDevice>)device imageName:(NSString*)name
{
    NSError* error;
    MTKTextureLoader* loader = [[MTKTextureLoader alloc] initWithDevice:device];

    NSDictionary* textureLoaderOptions = @{
        MTKTextureLoaderOptionTextureUsage : @(MTLTextureUsageShaderRead),
        MTKTextureLoaderOptionTextureStorageMode : @(MTLStorageModePrivate)
    };
    
    id<MTLTexture> texture = [loader newTextureWithName:name
                                           scaleFactor:1
                                                bundle:nil
                                               options:textureLoaderOptions
                                                 error:&error];
    
    if(texture == nil) {
        NSLog(@"error creating the texture with name %@: %@", name, error.localizedDescription);
        return nil;
    }

    return texture;
}

- (void)invalidateTiles
{
    for (WaveTile* tile in _visibleTiles) {
        tile.needsDisplay = YES;
    }
}

- (void)setNeedsDisplay:(BOOL)needsDisplay
{
    if (_needsDisplay == needsDisplay) {
        return;
    }
    for (WaveTile* tile in _visibleTiles) {
        tile.needsDisplay = needsDisplay;
    }
    _needsDisplay = needsDisplay;
}

#pragma mark - MTKViewDelegate

- (void)mtkView:(nonnull MTKView*)view drawableSizeWillChange:(CGSize)size
{
    /// Respond to drawable size or orientation changes here
    ///
    ///
    
    float widthFactor = size.width / view.bounds.size.width;
    float heightFactor = size.height / view.bounds.size.height;
    
    _lineAspectRatio = size.height / size.width;
    
    _lineWidth = 3.0f / size.height;

//    float sigma = ScaleWithOriginalFrame(0.7f, _originalSize.width, size.width);
//    _blur = [[MPSImageGaussianBlur alloc] initWithDevice:_device sigma:sigma];
//    _blur.edgeMode = MPSImageEdgeModeClamp;

//    float width = (((ceil(ScaleWithOriginalFrame(3.0f, _originalSize.height, _originalSize.height + (size.height/30) ))) / 2) * 2) + 1;
//    float height = (((ceil(ScaleWithOriginalFrame(3.0f, _originalSize.height, _originalSize.height + (size.height/30) ))) / 2) * 2) + 1;

//    _erode = [[MPSImageAreaMin alloc] initWithDevice:_device kernelWidth:width kernelHeight:height];

//    width = ((((int)ceil(ScaleWithOriginalFrame(17.0f, _originalSize.height, _originalSize.height + (size.height/30) ))) / 2) * 2) + 1;
//    height = ((((int)ceil(ScaleWithOriginalFrame(17.0f, _originalSize.height, _originalSize.height + (size.height/30) ))) / 2) * 2) + 1;

//    _bloom = [[MPSImageBox alloc] initWithDevice:_device kernelWidth:width kernelHeight:height];
    
    _projectionMatrix = matrix_orthographic(-size.width, size.width, size.height, -size.height, 0, 0);
    _projectionMatrix = matrix_multiply(matrix4x4_scale(1.0f, _lineAspectRatio, 0.0), _projectionMatrix);
    _projectionMatrix = matrix_multiply(matrix4x4_scale(widthFactor, heightFactor, 0.0), _projectionMatrix);
}

- (void)_updateDynamicBufferState
{
    ///
    /// Update the state of our uniform buffers before rendering
    ///

    _uniformBufferIndex = (_uniformBufferIndex + 1) % kMaxBuffersInFlight;

    _uniformBufferOffset = kAlignedUniformsSize * _uniformBufferIndex;
    _uniformBufferAddress = ((uint8_t *)_dynamicUniformBuffer.contents) + _uniformBufferOffset;
}

- (void)_renderTile:(WaveTile*)tile 
             origin:(CGFloat)origin
      commandBuffer:(id<MTLCommandBuffer>)commandBuffer
{
    if (_visualSample == nil) {
        tile.needsDisplay = NO;
        return;
    }
    size_t start = MAX(0.0, ceil(origin));
    
    NSData* buffer = nil;
    buffer = [_visualSample visualsFromOrigin:start];

    if (buffer != nil) {
        [tile copyFromData:buffer];
        _tilePass.colorAttachments[0].texture = tile.texture;

        id<MTLRenderCommandEncoder> renderEncoder = [commandBuffer renderCommandEncoderWithDescriptor:_tilePass];

        renderEncoder.label = @"Wave Tile Texture Render Pass";

        [renderEncoder setRenderPipelineState:_tileState];

        [renderEncoder setVertexBuffer:_dynamicUniformBuffer
                                offset:_uniformBufferOffset
                               atIndex:WaveBufferIndexUniforms];

        [renderEncoder setFragmentBuffer:_dynamicUniformBuffer
                                  offset:_uniformBufferOffset
                                 atIndex:WaveBufferIndexUniforms];
        
        [renderEncoder setVertexBuffer:tile.pairsBuffer
                                offset:0
                               atIndex:WaveBufferIndexVisualPairs];

        [renderEncoder drawPrimitives:MTLPrimitiveTypeTriangleStrip
                          vertexStart:0
                          vertexCount:4 * (tile.frame.size.width + 1)];

        [renderEncoder endEncoding];
        tile.needsDisplay = NO;
    } else {
        tile.needsDisplay = NO;

        if (start >= _visualSample.width) {
            return;
        }

        [_visualSample prepareVisualsFromOrigin:start
                                  width:_tileSize.width + 1
                                 window:_view.rect.size.width
                                  total:_view.documentVisibleRect.size.width
                               callback:^(void){
            tile.needsDisplay = YES;
        }];
    }
}

- (void)_updateTiles
{
    assert(_view != nil);
    
    NSRect documentVisibleRect = _view.documentVisibleRect;
    // Lie to get the last tile invisilbe, always. That way we wont regularly
    // see updates of the right most tile when the scrolling follows playback.
    documentVisibleRect.size.width += _tileSize.width;

    const CGFloat xMin = floor(NSMinX(documentVisibleRect) / _tileSize.width) * _tileSize.width;
    const CGFloat xMax = xMin + (ceil((NSMaxX(documentVisibleRect) - xMin) / _tileSize.width) * _tileSize.width);
    const CGFloat yMin = floor(NSMinY(documentVisibleRect) / _tileSize.height) * _tileSize.height;
    const CGFloat yMax = ceil((NSMaxY(documentVisibleRect) - yMin) / _tileSize.height) * _tileSize.height;

    // Figure out the tile frames we would need to get full coverage and add them to
    // the to-do list.
    NSMutableSet* neededTileFrames = [NSMutableSet set];
    for (CGFloat x = xMin; x < xMax; x += _tileSize.width) {
        for (CGFloat y = yMin; y < yMax; y += _tileSize.height) {
            NSRect rect = NSMakeRect(x, y, _tileSize.width, _tileSize.height);
            [neededTileFrames addObject:[NSValue valueWithRect:rect]];
        }
    }
    
    // See if we already have subviews that cover these needed frames.
    
    for (WaveTile* waveTile in [_visibleTiles copy]) {
        NSValue* frameRectVal = [NSValue valueWithRect:waveTile.frame];
        // If we don't need this one any more.
        if (![neededTileFrames containsObject:frameRectVal]) {
            // Then recycle it.
            [_reusableTiles addObject:waveTile];
            [_visibleTiles removeObject:waveTile];
        } else {
            // Take this frame rect off the to-do list.
            [neededTileFrames removeObject:frameRectVal];
        }
    }

    // Add needed tiles from the to-do list.
    for (NSValue* neededFrame in neededTileFrames) {
        WaveTile* waveTile = [_reusableTiles lastObject];
        [_reusableTiles removeLastObject];
        // Create one if we did not find a reusable one.
        if (waveTile == nil) {
            waveTile = [[WaveTile alloc] initWithDevice:_view.device
                                                   size:_tileSize];
        }
        waveTile.frame = [neededFrame rectValue];
        waveTile.needsDisplay = YES;

        // Place it and install it.
        [_visibleTiles addObject:waveTile];
    }
}

- (void)_updateEngine
{
    WaveUniforms* uniforms = (WaveUniforms*)_uniformBufferAddress;

    uniforms->lineWidth = _lineWidth;
    uniforms->projectionMatrix = _projectionMatrix;
    uniforms->sampleCount = _tileSize.width;
    uniforms->lineAspectRatio = _lineAspectRatio;
    uniforms->color = [GraphicsTools ShaderColorFromColor:_color];
    uniforms->tileWidth = (kMetalWaveViewTileWidth * 2.0f) / _view.rect.size.width;
    
    const float halfWidth = _view.documentVisibleRect.size.width / 2.0f;
    const float offset = ((_view.documentTotalRect.size.width * _currentFrame) / _frames) - _view.documentVisibleRect.origin.x;
    uniforms->currentFrameOffset = (offset - halfWidth) / halfWidth;

    matrix_float4x4 modelMatrix = matrix4x4_identity();
    matrix_float4x4 viewMatrix = matrix4x4_identity();
    
    uniforms->modelViewMatrix = matrix_multiply(viewMatrix, modelMatrix);
}

- (void)drawInMTKView:(nonnull MTKView *)view
{
    dispatch_semaphore_wait(_inFlightSemaphore, DISPATCH_TIME_FOREVER);

    id<MTLCommandBuffer> commandBuffer = [_commandQueue commandBuffer];
    commandBuffer.label = @"Wave Command Buffer";

    __block dispatch_semaphore_t block_sema = _inFlightSemaphore;
    [commandBuffer addCompletedHandler:^(id<MTLCommandBuffer> buffer) {
        dispatch_semaphore_signal(block_sema);
    }];
        
    [self _updateDynamicBufferState];
    
    [self _updateTiles];

    [self _updateEngine];

    {
        for (int i = 0; i < _visibleTiles.count;i++) {
            WaveTile* waveTile = _visibleTiles[i];
            
            if (waveTile.needsDisplay == NO) {
                continue;
            }
            
            [self _renderTile:waveTile origin:waveTile.frame.origin.x commandBuffer:commandBuffer];
        }
    }
    
    {
        id<MTLRenderCommandEncoder> renderEncoder = [commandBuffer renderCommandEncoderWithDescriptor:_wavePass];
        renderEncoder.label = @"Project Wave Textured Tile Render Pass";

        [renderEncoder setRenderPipelineState:_waveState];
        [renderEncoder setVertexBuffer:_dynamicUniformBuffer
                                offset:_uniformBufferOffset
                               atIndex:WaveBufferIndexUniforms];
        [renderEncoder setFragmentBuffer:_dynamicUniformBuffer
                                  offset:_uniformBufferOffset
                                 atIndex:WaveBufferIndexUniforms];

        const float halfWidth = _view.rect.size.width / 2.0;

        for (WaveTile* waveTile in _visibleTiles) {
            // Set the wave tile texture as the source texture.
            [renderEncoder setFragmentTexture:waveTile.texture 
                                      atIndex:WaveTextureIndexSource];
            
            const float position = (((waveTile.frame.origin.x - _view.documentVisibleRect.origin.x) - halfWidth) / halfWidth);

            [renderEncoder setVertexBytes:&position
                                   length:sizeof(float)
                                  atIndex:WaveTextureIndexPosition];

            // Draw quad with rendered texture.
            [renderEncoder drawPrimitives:MTLPrimitiveTypeTriangleStrip
                              vertexStart:0
                              vertexCount:4];
        }

        [renderEncoder endEncoding];
    }

    {
        [_bloom encodeToCommandBuffer:commandBuffer
                             sourceTexture:_waveTargetTexture
                        destinationTexture:_composeTargetTexture];
    }

    {
        id<MTLRenderCommandEncoder> renderEncoder = [commandBuffer renderCommandEncoderWithDescriptor:_composePass];

        renderEncoder.label = @"Compose Wave Textured Render Pass";

        [renderEncoder setRenderPipelineState:_composeState];

        [renderEncoder setVertexBuffer:_dynamicUniformBuffer
                                offset:_uniformBufferOffset
                               atIndex:WaveBufferIndexUniforms];

        [renderEncoder setFragmentBuffer:_dynamicUniformBuffer
                                  offset:_uniformBufferOffset
                                 atIndex:WaveBufferIndexUniforms];

        [renderEncoder setFragmentTexture:_composeOverlayTexture
                                  atIndex:WaveTextureIndexSource];
        
        vector_float2 uvsMap;
        uvsMap[0] = _composeTargetTexture.width / _composeOverlayTexture.width;
        uvsMap[1] = _composeTargetTexture.height / _composeOverlayTexture.height;
        [renderEncoder setVertexBytes:&uvsMap
                               length:sizeof(vector_float2)
                              atIndex:WaveTextureIndexUVSMapping];

        [renderEncoder drawPrimitives:MTLPrimitiveTypeTriangleStrip
                          vertexStart:0
                          vertexCount:4];

        [renderEncoder endEncoding];
    }


    /// Delay getting the currentRenderPassDescriptor until we absolutely need it to avoid
    ///   holding onto the drawable and blocking the display pipeline any longer than necessar
    MTLRenderPassDescriptor* renderPassDescriptor = view.currentRenderPassDescriptor;

    if(renderPassDescriptor != nil) {
        /// Final pass rendering code: Display on screen.
        id<MTLRenderCommandEncoder> renderEncoder =
            [commandBuffer renderCommandEncoderWithDescriptor:renderPassDescriptor];
        renderEncoder.label = @"Wave Drawable Render Pass";

        [renderEncoder setRenderPipelineState:_drawState];

        // Use the "dry signal" to mix on top of our fading.
        [renderEncoder setFragmentTexture:_composeTargetTexture
                                  atIndex:WaveTextureIndexSource];

        [renderEncoder drawPrimitives:MTLPrimitiveTypeTriangleStrip
                          vertexStart:0
                          vertexCount:4];

        [renderEncoder endEncoding];
  
        [commandBuffer presentDrawable:view.currentDrawable];
    }

    [commandBuffer commit];
}

@end
