//
//  ScopeRenderer.m
//  PlayEm
//
//  Created by Till Toenshoff on 10.05.20.
//  Copyright © 2020 Till Toenshoff. All rights reserved.
//
#import "ScopeRenderer.h"

#import <simd/simd.h>
#import <Accelerate/Accelerate.h>
#import <AVFoundation/AVFoundation.h>
#import <Cocoa/Cocoa.h>
#import <ModelIO/ModelIO.h>
#import <MetalPerformanceShaders/MetalPerformanceShaders.h>

#import "AudioController.h"
#import "AudioProcessing.h"
#import "GraphicsTools.h"
#import "LazySample.h"
#import "MatrixUtilities.h"

#import "ShaderTypes.h"
#import "ScopeShaderTypes.h"
#import "ScopeView.h"

#import "VisualSample.h"

static const NSUInteger kMaxBuffersInFlight = 3;
static const size_t kAlignedUniformsSize = (sizeof(ScopeUniforms) & ~0xFF) + 0x100;

//65536
//static const size_t kFrequencyDataScaleFactor = kFrequencyDataLength / kScaledFrequencyDataLength;

static const double kLevelDecreaseValue = 0.042;

@interface ScopeRenderer ()

@property (weak, nonatomic) AudioController* audio;
@property (weak, nonatomic) VisualSample* visual;

@property (strong, nonatomic) NSColor* color;
@property (strong, nonatomic) NSColor* fftColor;
@property (strong, nonatomic) NSColor* background;

@property (strong, nonatomic) NSMutableData* fftWindow;

@property (strong, nonatomic) NSMutableArray* blockSourceChannelData;
@property (strong, nonatomic) NSMutableData* blockFrequencyData;

@property (weak, nonatomic) id<ScopeRendererDelegate> delegate;

@property (strong, nonatomic) dispatch_queue_t renderQueue;

@end

@implementation ScopeRenderer
{
    // Texture to render to and then sample from.
    id<MTLTexture> _scopeTargetTexture;
    
    // Texture to render to and then sample from.
    id<MTLTexture> _scopeMSAATexture;
    
    // Texture to render to and then sample from.
    id<MTLTexture> _frequenciesTargetTexture;
    
    // Texture to render to and then sample from.
    id<MTLTexture> _frequenciesComposeTargetTexture;
    
    // Texture to render to and then sample from.
    id<MTLTexture> _lastFrequenciesTexture;
    
    // Texture to render to and then sample from.
    id<MTLTexture> _frequenciesMSAATexture;
    
    // Texture to compose onto and then sample from.
    id<MTLTexture> _composeTargetTexture;
    
    // Texture to compose onto and then sample from.
    id<MTLTexture> _postComposeTargetTexture;
    
    // Texture to store state in.
    id<MTLTexture> _lastTexture;
    
    // Texture to store state in.
    id<MTLTexture> _bufferTexture;
    
    // Render pass descriptor to draw the scope to a texture.
    MTLRenderPassDescriptor* _scopePass;
    // A pipeline object to render to the offscreen texture.
    id<MTLRenderPipelineState> _scopeState;
    
    // Render pass descriptor to draw the scope to a texture.
    MTLRenderPassDescriptor* _frequenciesPass;
    // A pipeline object to render to the offscreen texture.
    id<MTLRenderPipelineState> _frequenciesState;
    
    // Render pass descriptor to draw the scope to a texture.
    MTLRenderPassDescriptor* _frequenciesComposePass;
    // A pipeline object to render to the offscreen texture.
    id<MTLRenderPipelineState> _frequenciesComposeState;
    
    // Render pass descriptor to compose the last state with the scope pass results.
    MTLRenderPassDescriptor* _composePass;
    // A pipeline object to render to the offscreen texture.
    id<MTLRenderPipelineState> _composeState;
    
    // Render pass descriptor to compose the last state with the scope pass results.
    MTLRenderPassDescriptor* _postComposePass;
    // A pipeline object to render to the offscreen texture.
    id<MTLRenderPipelineState> _postComposeState;
    
    // Render pass descriptor to draw the texture to screen.
    MTLRenderPassDescriptor* _drawPass;
    // A pipeline object to render to screen.
    id<MTLRenderPipelineState> _drawState;
    
    float _lineWidth;
    float _frequencyLineWidth;
    float _frequencySpaceWidth;
    
    dispatch_semaphore_t _inFlightSemaphore;
    id <MTLDevice> _device;
    id <MTLCommandQueue> _commandQueue;
    
    id <MTLBuffer> _dynamicUniformBuffer;
    //id <MTLBuffer> _sampleUniformBuffer;
    id <MTLBuffer> _frequencyUniformBuffer;
    id <MTLBuffer> _linesUniformBuffer;
    
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
    
    size_t _frequencyStepping;
    
    size_t _alignedUSamplesSize;
    size_t _alignedUFrequenciesSize;
    size_t _alignedULinesSize;
    
    size_t _minTriggerOffset;
    
    uint8_t _uniformBufferIndex;
    
    void *_uniformBufferAddress;
    void *_sampleBufferAddress;
    void *_frequencyBufferAddress;
    void *_linesBufferAddress;
    
    matrix_float4x4 _projectionMatrix;
    matrix_float4x4 _feedbackProjectionMatrix;
    vector_float4 _feedbackColorFactor;
    
    float _rotation;
    //PolyNode* _scopeNodes;
    //ShaderLine* _frequencyLines;
    float _lineAspectRatio;
    
    // WORKLOAD DATA
    
    NSMutableArray<NSData*>* _sourceChannelData;
    float** _source;
    
    FFTSetup _fftSetup;
    vDSP_DFT_Setup _dctSetup;
    
    float* _logMap;
    
    NSSize _originalSize;   // Used while live resizing.
    NSSize _defaultSize;    // Sizes that match a good ratio as shader paramenters.
    
    CGFloat _newBlurSigma;
    BOOL _invalidateBlurSigma;

    CGSize _newBloomSize;
    BOOL _invalidateBloomSize;

    CGSize _newErodeSize;
    BOOL _invalidateErodeSize;
}

-(nonnull instancetype)initWithMetalKitView:(nonnull MTKView *)view
                                      color:(NSColor*)color
                                      fftColor:(NSColor*)fftColor
                                 background:(NSColor*)background
                                   delegate:(id<ScopeRendererDelegate>)delegate
{
    self = [super init];
    if(self)
    {
        _sampleCount = 1000;
        _sampleStepping = 1;
        _frequencyStepping = 1;
        //_frequencyCount = 256;
        _color = color;
        _fftColor = fftColor;
        _msaaCount = 4;
        _background = background;
        _lineWidth = 0.0f;
        _lineAspectRatio = 0.0f;
        _frequencyLineWidth = 0.0f;
        _inFlightSemaphore = dispatch_semaphore_create(kMaxBuffersInFlight);

        _feedbackColorFactor = vector4(0.9588f, 0.90f, 0.37f, 1.0f);
        _feedbackProjectionMatrix = matrix4x4_scale(1.0f, 1.0f, 1.0f);

        _fftWindow = [[NSMutableData alloc] initWithCapacity:sizeof(float) * kWindowSamples];
        _fftSetup = initFFT();
        _dctSetup = initDCT();
        _logMap = initLogMap();
        
        _delegate = delegate;
        
        _originalSize = NSMakeSize(0.0f, 0.0f);
        _defaultSize = NSMakeSize(640.0, 480.0f);
        
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(scopeViewDidLiveResize:)
                                                     name:kScopeViewDidLiveResizeNotification
                                                   object:nil];
    
        [self loadMetalWithView:view];
        
        _commandQueue = [_device newCommandQueue];

        dispatch_queue_attr_t attr = dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL,
                                                                             QOS_CLASS_USER_INTERACTIVE,
                                                                             0);
        _renderQueue = dispatch_queue_create("PlayEm.RenderingQueue", attr);
    }

    return self;
}

- (void)dealloc
{
    vDSP_destroy_fftsetup(_fftSetup);
    destroyLogMap(_logMap);
}

float srgb_from_rgb(float c)
{
    if (isnan(c))
        c = 0.0;
    
    if (c > 1.0)
        c = 1.0;
    else if (c < 0.0)
        c = 0.0;
    else if (c < 0.0031308)
        c = 12.92 * c;
    else
        c = 1.055 * pow(c, 1.0/2.4) - 0.055;
    
    // Convert to integer scale: c = c * 255.0
    // Convert to integer: c = c + 0.5
    // Drop the decimal fraction. The remaining floating-point(integral) value
    // is converted directly to an integer.
    return c;
}

float rgb_from_srgb(float c)
{
    if (c <= 0.04045)
        c = c / 12.92;
    else
        c = pow((c + 0.055) / 1.055, 2.4);
    return c;
}

- (void)scopeViewDidLiveResize:(NSNotification *)notification
{
    @synchronized (self) {
        [self loadMetalWithView:notification.object];
    };
}

- (void)loadMetalWithView:(nonnull MTKView*)view;
{
    assert(view.frame.size.width * view.frame.size.height);
    NSError *error;

    _device = view.device;
    _originalSize.width = view.frame.size.width;
    _originalSize.height = view.frame.size.height;

    /// Load Metal state objects and initalize renderer dependent view properties.
    view.colorPixelFormat = MTLPixelFormatBGRA8Unorm;
    view.sampleCount = 1;
    view.clearColor = [GraphicsTools MetalClearColorFromColor:_background];
    view.framebufferOnly = YES;
    
    // Set up a texture for rendering to and sampling from
    MTLTextureDescriptor *texDescriptor = [MTLTextureDescriptor new];
    texDescriptor.textureType = MTLTextureType2D;
    texDescriptor.storageMode = MTLStorageModePrivate;
    texDescriptor.width = view.drawableSize.width;
    texDescriptor.height = view.drawableSize.height;
    texDescriptor.pixelFormat = MTLPixelFormatRGBA8Unorm;
    texDescriptor.usage = MTLTextureUsageRenderTarget | MTLTextureUsageShaderRead;
    texDescriptor.sampleCount = _msaaCount;
    texDescriptor.storageMode = MTLStorageModePrivate;
    texDescriptor.textureType = _msaaCount > 1 ? MTLTextureType2DMultisample : MTLTextureType2D;

    _scopeMSAATexture = [_device newTextureWithDescriptor:texDescriptor];
    _frequenciesMSAATexture = [_device newTextureWithDescriptor:texDescriptor];

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
    
    // Set up a render pass descriptor for the render pass to render into _scopeTargetTexture.

    texDescriptor.sampleCount = 1;
    texDescriptor.textureType = MTLTextureType2D;
    texDescriptor.usage = MTLTextureUsageShaderWrite | MTLTextureUsageShaderRead;
    
    _scopeTargetTexture = [_device newTextureWithDescriptor:texDescriptor];
    _frequenciesTargetTexture = [_device newTextureWithDescriptor:texDescriptor];
    
    // FIXME: MSAA count alternative code is rubbish -- currently only works with MSAA > 1

    _scopePass = [[MTLRenderPassDescriptor alloc] init];
    _scopePass.colorAttachments[0].texture = _scopeMSAATexture;
    _scopePass.colorAttachments[0].loadAction = MTLLoadActionClear;
    _scopePass.colorAttachments[0].clearColor = MTLClearColorMake(0.0, 0.0, 0.0, 0.0);
    _scopePass.colorAttachments[0].storeAction = _msaaCount > 1 ? MTLStoreActionMultisampleResolve : MTLStoreActionStore;
    _scopePass.colorAttachments[0].resolveTexture = _scopeTargetTexture;

    // Set up pipeline for rendering the scope to the offscreen texture. Reuse the
    // descriptor and change properties that differ.
    pipelineStateDescriptor.label = @"Offscreen Scope Render Pipeline";
    pipelineStateDescriptor.rasterSampleCount = _msaaCount;
    //pipelineStateDescriptor.vertexFunction = [defaultLibrary newFunctionWithName:@"scopeInstanceShader"];
    pipelineStateDescriptor.vertexFunction = [defaultLibrary newFunctionWithName:@"polySegmentInstanceShader"];
    pipelineStateDescriptor.fragmentFunction = [defaultLibrary newFunctionWithName:@"scopeFragmentShader"];
    pipelineStateDescriptor.colorAttachments[0].pixelFormat = _scopeTargetTexture.pixelFormat;
    pipelineStateDescriptor.colorAttachments[0].blendingEnabled = YES;
    pipelineStateDescriptor.colorAttachments[0].rgbBlendOperation = MTLBlendOperationAdd;
    pipelineStateDescriptor.colorAttachments[0].alphaBlendOperation = MTLBlendOperationAdd;
    pipelineStateDescriptor.colorAttachments[0].sourceRGBBlendFactor = MTLBlendFactorSourceAlpha;
    pipelineStateDescriptor.colorAttachments[0].sourceAlphaBlendFactor = MTLBlendFactorSourceAlpha;
    pipelineStateDescriptor.colorAttachments[0].destinationRGBBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
    pipelineStateDescriptor.colorAttachments[0].destinationAlphaBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
    _scopeState = [_device newRenderPipelineStateWithDescriptor:pipelineStateDescriptor error:&error];
    NSAssert(_scopeState, @"Failed to create pipeline state to render the scope to a texture: %@", error);

    _frequenciesPass = [[MTLRenderPassDescriptor alloc] init];
    _frequenciesPass.colorAttachments[0].texture = _frequenciesMSAATexture;
    _frequenciesPass.colorAttachments[0].loadAction = MTLLoadActionClear;
    _frequenciesPass.colorAttachments[0].clearColor = MTLClearColorMake(0.0, 0.0, 0.0, 0.0);
    _frequenciesPass.colorAttachments[0].storeAction = _msaaCount > 1 ? MTLStoreActionMultisampleResolve : MTLStoreActionStore;
    _frequenciesPass.colorAttachments[0].resolveTexture = _frequenciesTargetTexture;

    // Set up pipeline for rendering the frequencies to the offscreen texture.
    {
        pipelineStateDescriptor.label = @"Offscreen Frequencies Render Pipeline";
        pipelineStateDescriptor.vertexFunction = [defaultLibrary newFunctionWithName:@"frequenciesVertexShader"];
        pipelineStateDescriptor.fragmentFunction = [defaultLibrary newFunctionWithName:@"frequenciesFragmentShader"];
        pipelineStateDescriptor.colorAttachments[0].pixelFormat = _frequenciesTargetTexture.pixelFormat;
        _frequenciesState = [_device newRenderPipelineStateWithDescriptor:pipelineStateDescriptor error:&error];
        NSAssert(_scopeState, @"Failed to create pipeline state to render the frequencies to a texture: %@", error);
    }

    texDescriptor.usage = MTLTextureUsageShaderWrite | MTLTextureUsageShaderRead | MTLTextureUsageRenderTarget;

    // Set up a render pass descriptor for the render pass to render into _composeTargetTexture.
    _composeTargetTexture = [_device newTextureWithDescriptor:texDescriptor];

    _composePass = [[MTLRenderPassDescriptor alloc] init];
    _composePass.colorAttachments[0].texture = _composeTargetTexture;
    _composePass.colorAttachments[0].loadAction = MTLLoadActionClear;
    _composePass.colorAttachments[0].clearColor = MTLClearColorMake(0.0, 0.0, 0.0, 0.0);
    _composePass.colorAttachments[0].storeAction = MTLStoreActionStore;

    // Set up pipeline for rendering to the offscreen texture.
    {
        pipelineStateDescriptor.label = @"Offscreen Compose Render Pipeline";
        pipelineStateDescriptor.rasterSampleCount = 1;
        pipelineStateDescriptor.vertexFunction = [defaultLibrary newFunctionWithName:@"projectTexture"];
        pipelineStateDescriptor.fragmentFunction = [defaultLibrary newFunctionWithName:@"composeFragmentShader"];
        pipelineStateDescriptor.colorAttachments[0].pixelFormat = _composeTargetTexture.pixelFormat;
        pipelineStateDescriptor.colorAttachments[0].sourceRGBBlendFactor = MTLBlendFactorOne;
        pipelineStateDescriptor.colorAttachments[0].sourceAlphaBlendFactor = MTLBlendFactorSourceAlpha;
        pipelineStateDescriptor.colorAttachments[0].destinationRGBBlendFactor = MTLBlendFactorOne;
        _composeState = [_device newRenderPipelineStateWithDescriptor:pipelineStateDescriptor error:&error];
        NSAssert(_composeState, @"Failed to create pipeline state to compose to a texture: %@", error);
    }

    // Set up a render pass descriptor for the render pass to render into _frequenciesComposeTargetTexture.
    _frequenciesComposeTargetTexture = [_device newTextureWithDescriptor:texDescriptor];

    _frequenciesComposePass = [[MTLRenderPassDescriptor alloc] init];
    _frequenciesComposePass.colorAttachments[0].texture = _frequenciesComposeTargetTexture;
    _frequenciesComposePass.colorAttachments[0].loadAction = MTLLoadActionClear;
    _frequenciesComposePass.colorAttachments[0].clearColor = MTLClearColorMake(0.0, 0.0, 0.0, 0.0);
    _frequenciesComposePass.colorAttachments[0].storeAction = MTLStoreActionStore;

    // Set up pipeline for rendering to the offscreen texture.
    {
        pipelineStateDescriptor.label = @"Offscreen Frequencies Compose Render Pipeline";
        pipelineStateDescriptor.rasterSampleCount = 1;
        pipelineStateDescriptor.vertexFunction = [defaultLibrary newFunctionWithName:@"projectTexture"];
        pipelineStateDescriptor.fragmentFunction = [defaultLibrary newFunctionWithName:@"composeFragmentShader"];
        pipelineStateDescriptor.colorAttachments[0].pixelFormat = _frequenciesComposeTargetTexture.pixelFormat;
        pipelineStateDescriptor.colorAttachments[0].blendingEnabled = YES;
        pipelineStateDescriptor.colorAttachments[0].sourceRGBBlendFactor = MTLBlendFactorOne;
        pipelineStateDescriptor.colorAttachments[0].sourceAlphaBlendFactor = MTLBlendFactorSourceAlpha;
        pipelineStateDescriptor.colorAttachments[0].destinationRGBBlendFactor = MTLBlendFactorOne;
        _frequenciesComposeState = [_device newRenderPipelineStateWithDescriptor:pipelineStateDescriptor error:&error];
        NSAssert(_composeState, @"Failed to create pipeline state to compose to a texture: %@", error);
    }

    _postComposeTargetTexture = [_device newTextureWithDescriptor:texDescriptor];

    _postComposePass = [[MTLRenderPassDescriptor alloc] init];
    _postComposePass.colorAttachments[0].texture = _postComposeTargetTexture;
    _postComposePass.colorAttachments[0].loadAction = MTLLoadActionClear;
    _postComposePass.colorAttachments[0].clearColor = MTLClearColorMake(0.0, 0.0, 0.0, 0.0);
    _postComposePass.colorAttachments[0].storeAction = MTLStoreActionStore;

    // Set up pipeline for rendering to the offscreen texture.
    {
        MTLRenderPipelineDescriptor *pipelineStateDescriptor = [[MTLRenderPipelineDescriptor alloc] init];
        pipelineStateDescriptor.label = @"Offscreen Post-Compose Render Pipeline";
        pipelineStateDescriptor.rasterSampleCount = 1;
        pipelineStateDescriptor.vertexFunction = [defaultLibrary newFunctionWithName:@"projectTexture"];
        pipelineStateDescriptor.fragmentFunction = [defaultLibrary newFunctionWithName:@"composeFragmentShader"];
        pipelineStateDescriptor.colorAttachments[0].pixelFormat = _postComposeTargetTexture.pixelFormat;
        pipelineStateDescriptor.colorAttachments[0].blendingEnabled = YES;
        pipelineStateDescriptor.colorAttachments[0].rgbBlendOperation = MTLBlendOperationAdd;
        pipelineStateDescriptor.colorAttachments[0].alphaBlendOperation = MTLBlendOperationAdd;
        pipelineStateDescriptor.colorAttachments[0].sourceRGBBlendFactor = MTLBlendFactorOne;
        pipelineStateDescriptor.colorAttachments[0].sourceAlphaBlendFactor = MTLBlendFactorSourceAlpha;
        pipelineStateDescriptor.colorAttachments[0].destinationRGBBlendFactor = MTLBlendFactorOne;
        pipelineStateDescriptor.colorAttachments[0].destinationAlphaBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
        _postComposeState = [_device newRenderPipelineStateWithDescriptor:pipelineStateDescriptor error:&error];
        NSAssert(_composeState, @"Failed to create pipeline state to post-compose to a texture: %@", error);
    }

    // Create offscreen textures for:
    // - last results for feedback
    // - previous results for feedback
    // - last frequencies
    texDescriptor.usage = MTLTextureUsageShaderWrite | MTLTextureUsageShaderRead;
    _lastTexture = [_device newTextureWithDescriptor:texDescriptor];
    _bufferTexture = [_device newTextureWithDescriptor:texDescriptor];
    _lastFrequenciesTexture = [_device newTextureWithDescriptor:texDescriptor];

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

    /*
    _alignedUSamplesSize = ((_sampleCount * sizeof(float)) & ~0xFF) + 0x100;
    NSUInteger sampleBufferSize = _alignedUSamplesSize * kMaxBuffersInFlight;
    _sampleUniformBuffer = [_device newBufferWithLength:sampleBufferSize
                                                options:MTLResourceStorageModeShared];
    _sampleUniformBuffer.label = @"SampleBuffer";
     */

    _alignedUFrequenciesSize = ((kFrequencyDataLength * sizeof(float)) & ~0xFF) + 0x100;
    NSUInteger frequencyBufferSize = _alignedUFrequenciesSize * kMaxBuffersInFlight;
    _frequencyUniformBuffer = [_device newBufferWithLength:frequencyBufferSize
                                                   options:MTLResourceStorageModeShared];
    _frequencyUniformBuffer.label = @"FrequenciesBuffer";
    
    [self _updateMeshWithLevel:1.000f];
}

- (void)_updateMeshWithLevel:(float)level
{
    assert(_linesUniformBuffer != nil);
    const float range = level * 2.0f;
       
    PolyNode* node = (PolyNode*)(_linesUniformBuffer.contents);
    size_t nodeCount = (_sampleCount + (_sampleStepping - 1)) / _sampleStepping;

    for (size_t i = 0; i < nodeCount; i++) {
        node[i].position.x = MIN((((i * _sampleStepping) * range) / _sampleCount) - level, level);
        node[i].position.y = 0.0f;
    }
}

- (void)_updateDynamicBufferState
{
    ///
    /// Update the state of our uniform buffers before rendering
    ///

    _uniformBufferIndex = (_uniformBufferIndex + 1) % kMaxBuffersInFlight;

    _uniformBufferOffset = kAlignedUniformsSize * _uniformBufferIndex;
    _uniformBufferAddress = ((uint8_t *)_dynamicUniformBuffer.contents) + _uniformBufferOffset;

    _frequencyBufferOffset = (uint32_t)_alignedUFrequenciesSize * _uniformBufferIndex;
    _frequencyBufferAddress = ((uint8_t *)_frequencyUniformBuffer.contents) + _frequencyBufferOffset;
}

- (void)play:(nonnull AudioController *)audio visual:(nonnull VisualSample *)visual scope:(nonnull MTKView *)scope
{
    NSLog(@"renderer starting...");
    _sourceChannelData = [NSMutableArray array];
    for (size_t channelIndex = 0; channelIndex < visual.sample.channels; channelIndex++) {
        NSData* data = [NSMutableData dataWithLength:MAX(_sampleCount, kWindowSamples) * sizeof(float)];
        [_sourceChannelData addObject:data];
    }
    _blockSourceChannelData = [NSMutableArray array];
    for (size_t channelIndex = 0; channelIndex < visual.sample.channels; channelIndex++) {
        NSData* data = [NSMutableData dataWithLength:MAX(_sampleCount, kWindowSamples) * sizeof(float)];
        [_blockSourceChannelData addObject:data];
    }

    _audio = audio;
    _visual = visual;
    _minTriggerOffset = 0;

    //scope.paused = NO;
}

- (void)stop:(MTKView *)scope
{
    NSLog(@"renderer stopping.");
    //scope.paused = YES;
}

- (void)updateVolumeLevelDisplay:(double)maxValue 
{
    // Use a logarithmic scale as that is much closer to what we perceive. Neatly fake
    // ourselves into the slope.
    float logval = log10f(10.0 + (maxValue * 100.0f)) - 1.0f;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.level.doubleValue < logval) {
            self.level.doubleValue = logval;
        } else {
            self.level.doubleValue -= MIN(self.level.doubleValue, kLevelDecreaseValue);
        }
    });
}

- (void)_updateEngine
{
    /// Update any engine state before encoding rendering commands to our drawable
    ///
    //static float _rotation = 0.0;
   
    ScopeUniforms* uniforms = (ScopeUniforms*)_uniformBufferAddress;

    //float* buffer = (float*)_sampleBufferAddress;

    //vector_float3 rotationAxis = {0, 0, 1};
    //matrix_float4x4 feedbackMatrix = matrix4x4_rotation(M_PI_2 + _rotation, rotationAxis);

    uniforms->lineWidth = _lineWidth;
    uniforms->projectionMatrix = _projectionMatrix;
    uniforms->sampleCount = (uint32_t)_sampleCount;
    uniforms->lineAspectRatio = _lineAspectRatio;
    uniforms->sampleStepping = (uint32_t)_sampleStepping;
    uniforms->frequencyStepping = (uint32_t)_frequencyStepping;
    uniforms->frequenciesCount = (uint32_t)kScaledFrequencyDataLength;
    uniforms->feedback.matrix = _feedbackProjectionMatrix;
    uniforms->feedback.colorFactor = _feedbackColorFactor;
    uniforms->color = [GraphicsTools ShaderColorFromColor:_color];
    uniforms->fftColor = [GraphicsTools ShaderColorFromColor:_fftColor];
    uniforms->frequencyLineWidth = _frequencyLineWidth;
    uniforms->frequencySpaceWidth = _frequencySpaceWidth;

    matrix_float4x4 modelMatrix = matrix4x4_identity();
    matrix_float4x4 viewMatrix = matrix4x4_identity();
    
    //vector_float3 rotationAxis = {0, 0, 1};
    //matrix_float4x4 modelMatrix = matrix4x4_rotation(_rotation, rotationAxis);
    //_rotation += 0.01;
    
    uniforms->modelViewMatrix = matrix_multiply(viewMatrix, modelMatrix);
    
    if (_visual == nil) {
        return;
    }

    /// Determine scope trigger offset
    
    size_t offset=0;

    size_t bestZeroCrossingOffset = 0;
    size_t bestPositiveStreakLength = 0;

    size_t zeroCrossingOffset;
    size_t positiveStreakLength;

    float data;
    float last;

    const size_t sampleFrames = _visual.sample.frames;
    const size_t channels = _visual.sample.channels;
    
    // Fetches sample pointers from `_sourceChannelData`
    float* sourceChannels[channels];
    for (int channelIndex=0; channelIndex < channels; channelIndex++) {
        NSData* data = _sourceChannelData[channelIndex];
        sourceChannels[channelIndex] = (float*)data.bytes;
    }

    dispatch_async(_renderQueue, ^{
        const size_t frame = self.currentFrame;

        /// Copy FFT data.
        if (frame >= 0) {
            float* window = self.fftWindow.mutableBytes;
            
            // We try to offset around the current head -- meaning the FFT window shall
            // start half its size before the head and end with half its size ahead.
            // This may not be a great strategy from a scientific angle - it is a straight-
            // forward thing to do.
            unsigned long long f = frame > (kWindowSamples / 2) ? frame - (kWindowSamples / 2) : 0;
            
            float* sourceChannels[channels];
            for (int channelIndex=0; channelIndex < channels; channelIndex++) {
                NSMutableData* data = self.blockSourceChannelData[channelIndex];
                sourceChannels[channelIndex] = data.mutableBytes;
            }
            
            // Gather up to one window full of mono sound data.
            size_t samplesToGo = [self.visual.sample rawSampleFromFrameOffset:f
                                                                       frames:kWindowSamples
                                                                      outputs:sourceChannels];
            
            for (size_t i = 0; i < samplesToGo; i++) {
                float data = 0;
                for (size_t channelIndex = 0; channelIndex < channels; channelIndex++) {
                    data += sourceChannels[channelIndex][i];
                }
                data /= channels;
                ++f;
                window[i] = data;
                if (f > sampleFrames) {
                    break;
                }
            }
            
            uint8_t bufferIndex = (self->_uniformBufferIndex + 1) % kMaxBuffersInFlight;
            uint32_t frequencyBufferOffset = (uint32_t)self->_alignedUFrequenciesSize * bufferIndex;
            void* frequencyBufferAddress = ((uint8_t *)self->_frequencyUniformBuffer.contents) + frequencyBufferOffset;

            performFFT(self->_fftSetup, window, kWindowSamples, frequencyBufferAddress);
            logscaleFFT(self->_logMap, frequencyBufferAddress);
            
//            performMel(_dctSetup, window, kWindowSamples, frequencyBufferAddress);
        }
    });

    
    size_t previousAttemptAt = -1;
    while (bestPositiveStreakLength == 0) {
        previousAttemptAt = offset;
        offset = self.currentFrame;

        if (offset < 0) {
            break;
        }
        
        if (offset == previousAttemptAt) {
            break;
        }
        
        if (offset > sampleFrames) {
            break;
        }

        _minTriggerOffset = offset;

        unsigned long long f = offset;

        bestPositiveStreakLength = 0;
        bestZeroCrossingOffset = f;

        positiveStreakLength = 0;
        zeroCrossingOffset = f;
        
        last = 1.0f;
        
        BOOL triggered = NO;
        
        // This may block for a loooooong time!
        unsigned long long framesReceived = [_visual.sample rawSampleFromFrameOffset:f
                                                                              frames:_sampleCount
                                                                             outputs:sourceChannels];

        size_t framesToGo = framesReceived;
       
        // Collect zero crossings and weight them by positive streak length.
        for (size_t i = 0; i < framesToGo; i++) {
            data = 0;
            for (size_t channelIndex = 0; channelIndex < channels; channelIndex++) {
                data += sourceChannels[channelIndex][i];
            }
            data /= channels;
            
            if (!triggered) {
                // Try to detect an upwards zero crossing.
                if (f >= _minTriggerOffset &&      // Prevent triggering before a minimum offset.
                    (data > 0.0f && last <= 0.0f)) {
                    zeroCrossingOffset = f;
                    positiveStreakLength = 0;
                    triggered = YES;
                }
            }

            last = data;

            if (triggered) {
                if (data >= 0.0f) {
                    ++positiveStreakLength;
                    if (positiveStreakLength > bestPositiveStreakLength) {
                        bestPositiveStreakLength = positiveStreakLength;
                        bestZeroCrossingOffset = zeroCrossingOffset;
                    }
                } else {
                    triggered = NO;
                }
            }
            
            ++f;
            
            // Did we run over the end of the total sample already?
            if (f >= sampleFrames) {
                f = _minTriggerOffset;
            }
        }
    };
    
    /// Copy scope lines.
    
    unsigned long long f = bestZeroCrossingOffset;
    _minTriggerOffset = bestZeroCrossingOffset + 1;
    unsigned long long framesReceived = [_visual.sample rawSampleFromFrameOffset:f
                                                                          frames:_sampleCount
                                                                         outputs:sourceChannels];

    size_t samplesToGo = framesReceived;
    size_t i = 0;
    
    // We are exploiting the traversal over the displayed samples by adding the level
    // meter feeding.
    double meterValue = 0.0;
    double maxValue = 0.0;

    PolyNode* node = _linesBufferAddress;
    for (; i < samplesToGo; i++) {
        data = 0.0f;
        for (size_t channelIndex = 0; channelIndex < channels; channelIndex++) {
            data += sourceChannels[channelIndex][i];
        }
        data /= channels;

        meterValue = data * data;
        if (meterValue > maxValue) {
            maxValue = meterValue;
        }

        // Initialize the line node Y value with the sample.
        node[i].position[1] = data;

        ++f;
        if (f >= _audio.sample.frames) {
            f = _minTriggerOffset;
        }
    }
    // Make sure any remaining node is reset to silence level.
    for (;i < _sampleCount;i++) {
        node[i].position[1] = 0.0;
    }

    [self updateVolumeLevelDisplay:maxValue];
}

#pragma mark - MTKViewDelegate

- (void)mtkView:(nonnull MTKView *)view drawableSizeWillChange:(CGSize)size
{
    /// Respond to drawable size or orientation changes here
    ///
    ///
    const float widthFactor = size.width / _originalSize.width;
    const float heightFactor = size.height / _originalSize.height;
    
    _lineAspectRatio = size.height / size.width;
    
    const float linePoints = 3.0f;
    _lineWidth = linePoints / size.height;

    const float frequencyLineWidth = size.width / kScaledFrequencyDataLength;

    const float spaceWidth = frequencyLineWidth / 5.0;
    _frequencySpaceWidth = spaceWidth / size.width;
    _frequencyLineWidth = (frequencyLineWidth - spaceWidth) / size.width;
    
    float sigma = ScaleWithOriginalFrame(0.7f, _defaultSize.width, size.width);
    if (sigma != _newBlurSigma) {
        _newBlurSigma = sigma;
        _invalidateBlurSigma = YES;
    }

    CGSize erodeSize = NSMakeSize((((ceil(ScaleWithOriginalFrame(linePoints, _defaultSize.height, _defaultSize.height + (size.height/30) ))) / 2) * 2) + 1, 
                                  (((ceil(ScaleWithOriginalFrame(linePoints, _defaultSize.height, _defaultSize.height + (size.height/30) ))) / 2) * 2) + 1);
    if (!CGSizeEqualToSize(_newErodeSize, erodeSize)) {
        _newErodeSize = erodeSize;
        _invalidateErodeSize = YES;
    }

    CGSize bloomSize = NSMakeSize(((((int)ceil(ScaleWithOriginalFrame(17.0f, _defaultSize.height, _defaultSize.height + (size.height/30) ))) / 2) * 2) + 1, 
                                  ((((int)ceil(ScaleWithOriginalFrame(17.0f, _defaultSize.height, _defaultSize.height + (size.height/30) ))) / 2) * 2) + 1);
    if (!CGSizeEqualToSize(_newBloomSize, bloomSize)) {
        _newBloomSize = bloomSize;
        _invalidateBloomSize = YES;
    }

    _projectionMatrix = matrix_orthographic(-size.width, size.width, size.height, -size.height, 0, 0);
    _projectionMatrix = matrix_multiply(matrix4x4_scale(1.0f, _lineAspectRatio, 0.0), _projectionMatrix);
    _projectionMatrix = matrix_multiply(matrix4x4_scale(widthFactor, heightFactor, 0.0), _projectionMatrix);
}

- (void)_updateShaderParameters
{
    if (_invalidateBlurSigma) {
        _blur = [[MPSImageGaussianBlur alloc] initWithDevice:_device sigma:_newBlurSigma];
        _blur.edgeMode = MPSImageEdgeModeClamp;
        _invalidateBlurSigma = NO;
    }
    if (_invalidateErodeSize) {
        _erode = [[MPSImageAreaMin alloc] initWithDevice:_device kernelWidth:_newErodeSize.width kernelHeight:_newErodeSize.height];
        _invalidateErodeSize = NO;
    }
    if (_invalidateBloomSize) {
        _bloom = [[MPSImageBox alloc] initWithDevice:_device kernelWidth:_newBloomSize.width kernelHeight:_newBloomSize.height];
        _invalidateBloomSize = NO;
    }
}

- (void)drawInMTKView:(nonnull MTKView *)view
{
    ///
    /// Per frame updates here
    ///

    @synchronized (self) {
        dispatch_semaphore_wait(_inFlightSemaphore, DISPATCH_TIME_FOREVER);
        
        id <MTLCommandBuffer> commandBuffer = [_commandQueue commandBuffer];
        commandBuffer.label = @"Scope Command Buffer";
        
        __block dispatch_semaphore_t block_sema = _inFlightSemaphore;
        [commandBuffer addCompletedHandler:^(id<MTLCommandBuffer> buffer) {
            dispatch_semaphore_signal(block_sema);
        }];
        
        [self _updateShaderParameters];
        [self _updateDynamicBufferState];
        [self _updateEngine];
        
        {
            /// First pass rendering code: Drawing the scope line.
            
            id<MTLRenderCommandEncoder> renderEncoder = [commandBuffer renderCommandEncoderWithDescriptor:_scopePass];
            
            renderEncoder.label = @"Scope Texture Render Pass";
            
            [renderEncoder setFrontFacingWinding:MTLWindingCounterClockwise];
            [renderEncoder setCullMode:MTLCullModeFront];
            [renderEncoder setRenderPipelineState:_scopeState];
            
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
        
        {
            [_bloom encodeToCommandBuffer:commandBuffer
                            sourceTexture:_scopeTargetTexture
                       destinationTexture:_bufferTexture];
        }
        
        {
            /// Third pass rendering code: Drawing the frequency pattern
            
            id<MTLRenderCommandEncoder> renderEncoder = [commandBuffer renderCommandEncoderWithDescriptor:_frequenciesPass];
            
            renderEncoder.label = @"Frequency Texture Render Pass";
            
            [renderEncoder setFrontFacingWinding:MTLWindingCounterClockwise];
            [renderEncoder setCullMode:MTLCullModeBack];
            [renderEncoder setRenderPipelineState:_frequenciesState];
            
            [renderEncoder setVertexBuffer:_dynamicUniformBuffer
                                    offset:_uniformBufferOffset
                                   atIndex:BufferIndexUniforms];
            
            [renderEncoder setFragmentBuffer:_dynamicUniformBuffer
                                      offset:_uniformBufferOffset
                                     atIndex:BufferIndexUniforms];
            
            [renderEncoder setVertexBuffer:_frequencyUniformBuffer
                                    offset:_frequencyBufferOffset
                                   atIndex:BufferIndexFrequencies];
            
            [renderEncoder drawPrimitives:MTLPrimitiveTypeTriangleStrip
                              vertexStart:0
                              vertexCount:4 * (kScaledFrequencyDataLength + (_frequencyStepping - 1))/ _frequencyStepping];
            [renderEncoder endEncoding];
        }
        
        {
            /// Fourth pass rendering code:  Scope compose with last scope
            
            id<MTLRenderCommandEncoder> renderEncoder = [commandBuffer renderCommandEncoderWithDescriptor:_composePass];
            
            renderEncoder.label = @"Scope Compose Texture Render Pass";
            
            [renderEncoder setRenderPipelineState:_composeState];
            
            // Set the offscreen texture with the bloomed scope as the source texture.
            [renderEncoder setFragmentTexture:_bufferTexture atIndex:TextureIndexScope];
            
            // Set the offscreen texture from the last scope round as the source texture.
            [renderEncoder setFragmentTexture:_lastTexture atIndex:TextureIndexLast];
            
            [renderEncoder setFragmentBuffer:_dynamicUniformBuffer
                                      offset:_uniformBufferOffset
                                     atIndex:BufferIndexUniforms];
            
            // Draw quad with rendered texture.
            [renderEncoder drawPrimitives:MTLPrimitiveTypeTriangleStrip
                              vertexStart:0
                              vertexCount:4];
            
            [renderEncoder endEncoding];
        }
        
        {
            /// Fifth pass rendering code: Scope with last scope bloom again
            [_bloom encodeToCommandBuffer:commandBuffer
                            sourceTexture:_composeTargetTexture
                       destinationTexture:_bufferTexture];
            
            /// Sixths pass rendering code: Scope with last scope erode to reduce artefact creep
            [_erode encodeToCommandBuffer:commandBuffer
                            sourceTexture:_bufferTexture
                       destinationTexture:_lastTexture];
        }
        
        {
            /// Sevenths pass rendering code: Frequency and last frequencies composing
            
            id<MTLRenderCommandEncoder> renderEncoder = [commandBuffer renderCommandEncoderWithDescriptor:_frequenciesComposePass];
            
            renderEncoder.label = @"Frequency Compose Texture Render Pass";
            
            [renderEncoder setRenderPipelineState:_frequenciesComposeState];
            
            // Set the offscreen texture as the source texture.
            [renderEncoder setFragmentTexture:_frequenciesTargetTexture atIndex:TextureIndexScope];
            
            // Set the offscreen texture as the source texture.
            [renderEncoder setFragmentTexture:_lastFrequenciesTexture atIndex:TextureIndexLast];
            
            [renderEncoder setFragmentBuffer:_dynamicUniformBuffer
                                      offset:_uniformBufferOffset
                                     atIndex:BufferIndexUniforms];
            
            // Draw quad with rendered texture.
            [renderEncoder drawPrimitives:MTLPrimitiveTypeTriangleStrip
                              vertexStart:0
                              vertexCount:4];
            
            [renderEncoder endEncoding];
        }
        
        {
            /// Eigths pass rendering code: Frequency and last frequencies blur.
            [_blur encodeToCommandBuffer:commandBuffer
                           sourceTexture:_frequenciesComposeTargetTexture
                      destinationTexture:_lastFrequenciesTexture];
        }
        
        {
            /// Nineth pass rendering code: Compose scope and frequencies
            
            id<MTLRenderCommandEncoder> renderEncoder = [commandBuffer renderCommandEncoderWithDescriptor:_postComposePass];
            
            renderEncoder.label = @"Scope and Frequencies Compose Texture Render Pass";
            
            [renderEncoder setRenderPipelineState:_postComposeState];
            
            // Source is the last frequencies texture with feedback.
            [renderEncoder setFragmentTexture:_lastFrequenciesTexture atIndex:TextureIndexScope];
            
            // Source is the last scope texture with feedback.
            [renderEncoder setFragmentTexture:_lastTexture atIndex:TextureIndexLast];
            
            [renderEncoder setFragmentBuffer:_dynamicUniformBuffer
                                      offset:_uniformBufferOffset
                                     atIndex:BufferIndexUniforms];
            
            // Draw quad with rendered texture.
            [renderEncoder drawPrimitives:MTLPrimitiveTypeTriangleStrip
                              vertexStart:0
                              vertexCount:4];
            
            [renderEncoder endEncoding];
        }
        
        
        /// Delay getting the currentRenderPassDescriptor until we absolutely need it to avoid
        ///   holding onto the drawable and blocking the display pipeline any longer than necessar
        ///
        MTLRenderPassDescriptor* renderPassDescriptor = view.currentRenderPassDescriptor;
        
        if(renderPassDescriptor != nil) {
            /// Final pass rendering code: Display on screen.
            id<MTLRenderCommandEncoder> renderEncoder =
            [commandBuffer renderCommandEncoderWithDescriptor:renderPassDescriptor];
            renderEncoder.label = @"Drawable Render Pass";
            
            [renderEncoder setRenderPipelineState:_drawState];
            
            // Use the "dry signal" to mix on top of our fading.
            [renderEncoder setFragmentTexture:_scopeTargetTexture atIndex:TextureIndexScope];
            
            // offscreen texture
            [renderEncoder setFragmentTexture:_postComposeTargetTexture atIndex:TextureIndexCompose];
            
            // Draw quad with rendered texture.
            [renderEncoder drawPrimitives:MTLPrimitiveTypeTriangleStrip
                              vertexStart:0
                              vertexCount:4];
            
            [renderEncoder endEncoding];
            [commandBuffer presentDrawable:view.currentDrawable afterMinimumDuration:1.0 / 200.0];
        }
        
        [commandBuffer commit];
    }
}

@end
