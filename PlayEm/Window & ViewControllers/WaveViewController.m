//
//  WaveViewController.m
//  PlayEm
//  Created by Till Toenshoff on 11/9/25.
//  Copyright © 2025 Till Toenshoff. All rights reserved.
//

#import "WaveViewController.h"

#import <Quartz/Quartz.h>
#import <CoreImage/CoreImage.h>
#import <CoreImage/CIFilterBuiltins.h>

#import "TrackList.h"
#import "MediaMetaData.h"

#import "WaveView.h"
#import "Defaults.h"
#import "../Sample/LazySample.h"
#import "TrackList.h"
#import "TimedMediaMetaData.h"
#import "TileView.h"
#import "../Sample/BeatTrackedSample.h"
#import "../Sample/VisualSample.h"
#import "../Sample/VisualPair.h"
#import "../Views/WaveScrollView.h"
#import "../NSImage+Resize.h"
#import "../CAShapeLayer+Path.h"

typedef enum : NSUInteger {
    NormalHandle = 0,
    HoverHandle = 1,
    PressedHandle,
    ActiveHandle
} TrackMarkHandleState;

static const size_t kHandleLayerIndex = 0;
static const size_t kFXLayerIndex = 1;
static const size_t kClippingHostLayerIndex = 2;
static const size_t kImageLayerIndex = 0;
static const size_t kTimeLayerIndex = 1;
static const size_t kTitleLayerIndex = 2;
static const size_t kArtistLayerIndex = 3;
static const size_t kReflectionLayerIndex = 4;

static const CGFloat kRegularImageViewOpacity = 0.5f;

extern NSString * const kTracklistControllerChangedActiveTrackNotification;


@interface FrameMarker : NSObject
@property (nonatomic, strong) NSNumber* frame;
@property (nonatomic, strong) NSValue* rect;

- (id)initWithFrame:(NSNumber*)frame rect:(NSValue*)rect;
@end

@interface WaveViewController()
@property (nonatomic, assign) BOOL userMomentum;
@property (nonatomic, assign) CGFloat head;
@property (nonatomic, strong) NSMutableArray* reusableViews;
@property (nonatomic, strong) NSMutableArray<CALayer*>* reusableLayers;
@property (strong, nonatomic) dispatch_queue_t imageQueue;

@property (weak, nonatomic) CALayer* previousLayer;
@property (weak, nonatomic) CALayer* draggingLayer;
@property (weak, nonatomic) CALayer* activeLayer;
@property (weak, nonatomic) CALayer* handleLayer;
@property (weak, nonatomic) CALayer* fxLayer;
@property (weak, nonatomic) CALayer* duckForLayer;

@property (assign, nonatomic) BOOL tracking;
@property (strong, nonatomic) NSMutableSet<FrameMarker*>* markTracking;
@property (strong, nonatomic) FrameMarker* trackingMarker;

@property (weak, nonatomic) TimedMediaMetaData* currentTrack;

@property (strong, nonatomic) NSArray<NSColor*>* handleColors;
@property (assign, nonatomic) float currentTempo;
@property (assign, nonatomic) BOOL duck;

@property (strong, nonatomic) NSFont* titleFont;
@property (strong, nonatomic) NSColor* titleColor;
@property (strong, nonatomic) NSFont* timeFont;
@property (strong, nonatomic) NSColor* timeColor;
@property (strong, nonatomic) NSFont* artistFont;
@property (strong, nonatomic) NSColor* artistColor;
@property (assign, nonatomic) CGSize imageSize;
@property (readonly, nonatomic) double framesPerPixel;
@property (assign, nonatomic) CGRect draggingRangeRect;

//@property (strong, nonatomic) CIFilter* vibranceFilter;


@end

NSString* kFrameOffsetLayerKey = @"frameOffset";
NSString* kFrameOffsetAreaKey = @"frameOffset";

const CGFloat kMarkerHandleWidth = 6.0f;

@implementation FrameMarker
{
}

- (id)initWithFrame:(NSNumber*)frame rect:(NSValue*)rect;
{
    self = [super init];
    if (self) {
        _frame = frame;
        _rect = rect;
    }
    return self;
}

@end

@implementation WaveViewController
{
}

- (id)init
{
    self = [super init];
    if (self) {
        _waveFillColor = [[Defaults sharedDefaults] regularBeamColor];
        _waveOutlineColor = [_waveFillColor colorWithAlphaComponent:0.2];
        _followTime = YES;
        _userMomentum = NO;
        _reusableViews = [NSMutableArray array];
        _reusableLayers = [NSMutableArray array];
        _tileWidth = 256.0;
        _currentTempo = 0.0;
        _frames = 0;
        dispatch_queue_attr_t attr = dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL, QOS_CLASS_USER_INITIATED, 0);
        _imageQueue = dispatch_queue_create("PlayEm.WaveViewImageQueue", attr);

        _markTracking = [NSMutableSet set];
        _duckForLayer = nil;
        _currentTrack = nil;
        
        _handleColors = @[ [NSColor tertiaryLabelColor],
                           [[Defaults sharedDefaults] regularFakeBeamColor],
                           [[Defaults sharedDefaults] lightFakeBeamColor],
                           [[Defaults sharedDefaults] lightFakeBeamColor]];
        
        _titleFont = [[Defaults sharedDefaults] smallFont];
        _titleColor = [[Defaults sharedDefaults] lightFakeBeamColor];
        _artistFont = [[Defaults sharedDefaults] smallFont];
        _artistColor = [[Defaults sharedDefaults] regularFakeBeamColor];
        _timeFont = [[Defaults sharedDefaults] smallFont];
        _timeColor = [[Defaults sharedDefaults] secondaryLabelColor];
        
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(activeTrackChanged:)
                                                     name:kTracklistControllerChangedActiveTrackNotification
                                                   object:nil];
        
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(beatEffect:)
                                                     name:kBeatTrackedSampleBeatNotification
                                                   object:nil];

    }
    return self;
}

- (void)loadView
{
    [super loadView];
    
    self.view = [[WaveView alloc] initWithFrame:NSZeroRect];
    //self.view.autoresizingMask = NSViewNotSizable;
    self.view.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    self.view.translatesAutoresizingMaskIntoConstraints = NO;
}

- (void)activeTrackChanged:(NSNotification*)notification
{
    WaveView* wv = (WaveView*)self.view;
    
    if (_activeLayer != nil) {
        CALayer* handleLayer = _activeLayer.sublayers[kHandleLayerIndex];
        CALayer* fxLayer = _activeLayer.sublayers[kFXLayerIndex];
        [handleLayer removeAllAnimations];
        [fxLayer removeAllAnimations];
        handleLayer.backgroundColor = _handleColors[NormalHandle].CGColor;
        fxLayer.opacity = 0.0f;
    }

    //NSLog(@"active track now %@", notification.object);
    _currentTrack = notification.object;
    _activeLayer = [self sublayerForFrame:_currentTrack.frame layers:wv.markLayer.sublayers];
    [self updateTrackDescriptions];
}

- (void)viewDidLayout
{
    [super viewDidLayout];

    if (self.view.enclosingScrollView != nil) {
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(willStartLiveScroll:)
                                                     name:NSScrollViewWillStartLiveScrollNotification
                                                   object:self.view.enclosingScrollView];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(didLiveScroll:)
                                                     name:NSScrollViewDidLiveScrollNotification
                                                   object:self.view.enclosingScrollView];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(didEndLiveScroll:)
                                                     name:NSScrollViewDidEndLiveScrollNotification
                                                   object:self.view.enclosingScrollView];
    }
    [self resetTracking];

    _imageSize = CGSizeMake(self.view.bounds.size.height - 2, self.view.bounds.size.height - 2);
}

- (void)setCurrentFrame:(unsigned long long)frame
{
    _currentFrame = frame;
    [self updateHeadPosition];
    [self updateTiles];
}

- (void)resetTracking
{
    NSTrackingArea* trackingArea = [[NSTrackingArea alloc] initWithRect:self.view.bounds
                                                                options:(NSTrackingMouseEnteredAndExited | NSTrackingMouseMoved | NSTrackingActiveInKeyWindow | NSTrackingInVisibleRect | NSTrackingEnabledDuringMouseDrag)
                                                                  owner:self
                                                               userInfo:nil];
    
    [self.view addTrackingArea:trackingArea];
}

- (double)framesPerPixel
{
    return _frames / self.view.bounds.size.width;
}

- (void)setFrames:(unsigned long long)frames
{
    _frames = frames;
    _currentFrame = 0;

    // As the total amount of frames for this sample has changed, we will also need to reload
    // pretty much everything -- the beat layer is skipped here as it is highly likely not
    
    [self updateHeadPosition];
    [self updateTiles];
    [self updateWaveLayer];
    [self updateBeatMarkLayer];
}

- (void)setVisualSample:(VisualSample *)visualSample
{
    _visualSample = visualSample;
    [self updateHeadPosition];
    [self updateTiles];
    [self updateWaveLayer];
    [self updateBeatMarkLayer];
}

- (void)loadBeatsForTile:(TileView*)tile
{
    CALayer* rootLayer = tile.beatLayer;
    //[rootLayer.sublayers makeObjectsPerformSelector:@selector(removeFromSuperlayer)];
    NSArray<CALayer*>* goneLayers = [rootLayer.sublayers copy];
    [goneLayers makeObjectsPerformSelector:@selector(removeFromSuperlayer)];
    [rootLayer setNeedsDisplay];
    
    if (_frames == 0 || self.view == nil || _beatSample == nil || rootLayer.superlayer.frame.origin.x < 0) {
        return;
    }
    
    const CGFloat start = rootLayer.superlayer.frame.origin.x;
    const CGFloat width = rootLayer.frame.size.width;
    
    const unsigned long long frameOffset = floor(start * self.framesPerPixel);
    
    unsigned long long currentBeatIndex = [_beatSample firstBeatIndexAfterFrame:frameOffset];
    if (currentBeatIndex == ULONG_LONG_MAX) {
        //NSLog(@"beat buffer from frame %lld (screen %f) not yet available", frameOffset, start);
        return;
    }
    
    const unsigned long long beatCount = [_beatSample beatCount];
    assert(beatCount > 0 && beatCount != ULONG_LONG_MAX);
    
    while (currentBeatIndex < beatCount) {
        BeatEvent currentEvent;
        [_beatSample getBeat:&currentEvent
                          at:currentBeatIndex];
        
        currentBeatIndex++;
        
        const CGFloat x = floor((currentEvent.frame / self.framesPerPixel) - start);
        
        // We need to stop drawing when we reached the total width of our layer.
        if (x >= width) {
            break;
        }

        // Anything non beat related is not of interest here, we can skip it.
        if ((currentEvent.style & _beatMask) == 0) {
            continue;
        }
        
        CGColorRef color;
        CGFloat width;

        if ((currentEvent.style & BeatEventMaskMarkers) != 0) {
            color = [_markerColor CGColor];
            width = _markerWidth;
        } else if ((currentEvent.style & BeatEventStyleBar) == BeatEventStyleBar) {
            color = [_barColor CGColor];
            width = _barWidth;
        } else {
            color = [_beatColor CGColor];
            width = _beatWidth;
        }
        
        CALayer* beatmark = [CALayer layer];
        beatmark.drawsAsynchronously = YES;
        beatmark.backgroundColor = color;
        beatmark.frame = CGRectMake(x, 0, width, self.view.frame.size.height);
        [rootLayer addSublayer:beatmark];
    };
}

- (void)setTrackList:(TrackList *)trackList
{
    _trackList = trackList;
    assert(self.view.frame.size.width > 0);
    
    [self reloadTracklist];
}

- (void)setBeatSample:(BeatTrackedSample *)beatSample
{
    _beatSample = beatSample;
    assert(self.view.frame.size.width > 0);
    
    [self reloadTracklist];
}

- (void)reloadTracklist
{
    //[self updateChapterMarkLayer];
    [self reloadTrackDescriptions];
}

- (void)updateBeatMarkLayer
{
    for (TileView* tv in self.view.subviews) {
        [self loadBeatsForTile:tv];
    }
}

- (void)updateWaveLayer
{
    for (TileView* tv in self.view.subviews) {
        [tv.waveLayer setNeedsDisplay];
    }
}

- (void)setHead:(CGFloat)head
{
    _head = head;
    
    WaveScrollView* sv = (WaveScrollView*)self.view.enclosingScrollView;
    if (sv != nil) {
        [sv setHead:head];
    } else {
        WaveView* wv = (WaveView*)self.view;
        [wv setHead:head];
    }
}

- (CGFloat)calcHead
{
    if (_frames == 0LL) {
        return 0.0;
    }
    return floor(( _currentFrame * self.view.bounds.size.width) / _frames);
}

- (void)resize
{
    if (self.view.enclosingScrollView != nil) {
        [self.view.enclosingScrollView performSelector:@selector(resize)];
        return;
    } else {
        [self.view performSelector:@selector(resize)];
    }

    [self updateHeadPosition];
    [self updateTiles];
    [self updateWaveLayer];
    [self updateBeatMarkLayer];
    [self updateTrackDescriptions];
}

- (NSAttributedString*)textWithFont:(NSFont*)font color:(NSColor*)color width:(CGFloat)width text:(NSString*)text
{
    NSString *truncationString = @"...";

    assert(font != nil);
    assert(color != nil);
    assert(text != nil);
    assert(text.length > 0);
    assert(width > 0.0);

    // Create the attributes for the text
    NSMutableParagraphStyle *style = [[NSMutableParagraphStyle alloc] init];
    style.lineBreakMode = NSLineBreakByTruncatingTail;

    NSDictionary* attributes = @{   NSForegroundColorAttributeName:color,
                                    NSFontAttributeName:font,
                                    NSParagraphStyleAttributeName:style };

    CGFloat maxWidth = width - [truncationString sizeWithAttributes:attributes].width;

    NSAttributedString* attributedString = [[NSAttributedString alloc] initWithString:text attributes:attributes];

    // Measure the width of the string
    CGSize textSize = [attributedString size];

    // Check if the text exceeds the available width
    if (textSize.width > maxWidth) {
        // Start truncating by removing characters until it fits
        NSMutableString *truncatedText = [text mutableCopy];

        while ([truncatedText sizeWithAttributes:attributes].width > maxWidth - [truncationString sizeWithAttributes:attributes].width) {
            assert(truncatedText.length);
            [truncatedText deleteCharactersInRange:NSMakeRange(truncatedText.length - 1, 1)];
        };

        // Add the ellipsis
        [truncatedText appendString:truncationString];
        attributedString = [[NSAttributedString alloc] initWithString:truncatedText attributes:attributes];
    }

    return attributedString;
}

- (NSAttributedString*)textWithFont:(NSFont*)font color:(NSColor*)color text:(NSString*)text
{
    assert(font != nil);
    assert(color != nil);
    if (text == nil) {
        return [[NSAttributedString alloc] initWithString:@""];
    }

    // Create the attributes for the text
    //NSMutableParagraphStyle *style = [[NSMutableParagraphStyle alloc] init];
    //style.lineBreakMode = NSLineBreakByTruncatingTail;

    NSDictionary* attributes = @{   NSForegroundColorAttributeName:color,
                                    NSFontAttributeName:font};

    return [[NSAttributedString alloc] initWithString:text attributes:attributes];
}

- (CALayer*)trackLayer
{
    WaveView* wv = (WaveView*)self.view;
    CGRect frame = wv.markLayer.frame;
    CAGradientLayer* background = [CAGradientLayer new];
    CGSize imageSize = CGSizeMake(frame.size.height - 4.0, frame.size.height - 4.0);
    CGSize textSize = CGSizeMake(300.0, [[Defaults sharedDefaults] smallFontSize]);
    CGSize backgroundSize = CGSizeMake(imageSize.width + textSize.width + 8.0, frame.size.height);
    CGFloat artistFontSize = [[Defaults sharedDefaults] smallFontSize];
    CGFloat titleFontSize = [[Defaults sharedDefaults] smallFontSize];
    CGFloat timeFontSize = [[Defaults sharedDefaults] smallFontSize];
    CGFloat radius = 5.0;

    background.colors = @[(id)[[[Defaults sharedDefaults] regularFakeBeamColor] colorWithAlphaComponent:0.4].CGColor,
                          (id)[NSColor clearColor].CGColor,
                          (id)[NSColor clearColor].CGColor];

    CIFilter* bloom = [CIFilter filterWithName:@"CIBloom"];
    [bloom setDefaults];
    [bloom setValue: @(4.0f) forKey: @"inputRadius"];
    [bloom setValue: @(1.0f) forKey: @"inputIntensity"];

    background.borderWidth = 0.0;
    background.autoresizingMask = kCALayerWidthSizable | kCALayerHeightSizable;
    background.allowsEdgeAntialiasing = YES;
    background.shouldRasterize = YES;
    background.drawsAsynchronously = YES;
    background.rasterizationScale = wv.layer.contentsScale;
    background.contentsScale = [[NSScreen mainScreen] backingScaleFactor];
    background.masksToBounds = NO;
    background.frame = CGRectMake(0.0f, 0.0f, backgroundSize.width, backgroundSize.height);
    background.cornerRadius = radius;
    //background.borderColor = [[Defaults sharedDefaults] lightBeamColor].CGColor;
    //background.borderWidth = 0.5f;

    CALayer* handleLayer = [CALayer layer];
    handleLayer.autoresizingMask = kCALayerHeightSizable;
    handleLayer.allowsEdgeAntialiasing = YES;
    handleLayer.drawsAsynchronously = YES;
    handleLayer.contentsScale = [[NSScreen mainScreen] backingScaleFactor];
    handleLayer.backgroundColor = _handleColors[NormalHandle].CGColor;
    handleLayer.name = @"WaveMarkDescriptionHandleLayer";
    handleLayer.masksToBounds = NO;
    handleLayer.frame = CGRectMake(0.0f, 0.0f, kMarkerHandleWidth, backgroundSize.height);
    [background addSublayer:handleLayer];

    CALayer* fxLayer = [CALayer layer];
    fxLayer.zPosition = 10.0f;
    fxLayer.autoresizingMask = kCALayerNotSizable;
    fxLayer.allowsEdgeAntialiasing = YES;
    //fxLayer.shouldRasterize = YES;
    fxLayer.drawsAsynchronously = YES;
    //fxLayer.backgroundColor = [];
    fxLayer.rasterizationScale = wv.layer.contentsScale;
    fxLayer.contentsScale = [[NSScreen mainScreen] backingScaleFactor];
    //fxLayer.masksToBounds = YES;
    fxLayer.opacity = 0.0f;
    fxLayer.backgroundFilters = @[ bloom ];
    fxLayer.name = @"WaveMarkDescriptionFXLayer";
    fxLayer.frame = CGRectMake(-5.0, 0.0, kMarkerHandleWidth + 10.0, backgroundSize.height);
    fxLayer.mask = [CAShapeLayer MaskLayerFromRect:fxLayer.bounds];
    [background addSublayer:fxLayer];

    CALayer* clippedBackground = [CALayer layer];

    clippedBackground.magnificationFilter = kCAFilterLinear;
    clippedBackground.minificationFilter = kCAFilterLinear;
    clippedBackground.zPosition = 1.0f;
    clippedBackground.allowsEdgeAntialiasing = YES;
    clippedBackground.shouldRasterize = YES;
    clippedBackground.autoresizingMask = kCALayerWidthSizable | kCALayerHeightSizable;
    clippedBackground.opacity = 1.0f;
    clippedBackground.drawsAsynchronously = YES;
    clippedBackground.rasterizationScale = wv.layer.contentsScale;
    clippedBackground.contentsScale = [[NSScreen mainScreen] backingScaleFactor];
    clippedBackground.masksToBounds = YES;
    clippedBackground.frame = background.bounds;
    clippedBackground.name = @"WaveMarkDescriptionClippedBackgroundLayer";
    [background addSublayer:clippedBackground];
    
    CALayer* imageLayer = [CALayer layer];
    imageLayer.magnificationFilter = kCAFilterLinear;
    imageLayer.minificationFilter = kCAFilterLinear;
    imageLayer.autoresizingMask = kCALayerNotSizable;
    imageLayer.allowsEdgeAntialiasing = YES;
    //imageLayer.filters = @[_vibranceFilter];
    //imageLayer.shouldRasterize = YES;
    //imageLayer.compositingFilter = [CIFilter filterWithName:@"CILinearDodgeBlendMode"];
    imageLayer.drawsAsynchronously = YES;
    imageLayer.rasterizationScale = wv.layer.contentsScale;
    imageLayer.contentsScale = [[NSScreen mainScreen] backingScaleFactor];
    imageLayer.masksToBounds = YES;
    imageLayer.frame = CGRectMake(kMarkerHandleWidth, 2.0, imageSize.width, imageSize.height);
    imageLayer.name = @"WaveMarkDescriptionImageLayer";
    imageLayer.opacity = 1.0f;
    imageLayer.borderWidth = 1.0;
    imageLayer.borderColor = [NSColor blackColor].CGColor;
    [clippedBackground addSublayer:imageLayer];

    CGFloat x = kMarkerHandleWidth + imageSize.width + 2.0;
    
    CATextLayer* timeLayer = [CATextLayer layer];
    timeLayer.drawsAsynchronously = YES;
    timeLayer.autoresizingMask = kCALayerWidthSizable | kCALayerHeightSizable | kCALayerMaxXMargin;
    timeLayer.allowsEdgeAntialiasing = YES;
    timeLayer.wrapped = NO;
    timeLayer.name = @"WaveMarkDescriptionTimeLayer";
    timeLayer.contentsScale = [[NSScreen mainScreen] backingScaleFactor];
    timeLayer.frame = CGRectMake(x, titleFontSize + 4.0 + artistFontSize + 4.0, backgroundSize.width - x, timeFontSize + 4.0);

    [clippedBackground addSublayer:timeLayer];

    CATextLayer* titleLayer = [CATextLayer layer];
    titleLayer.drawsAsynchronously = YES;
    titleLayer.autoresizingMask = kCALayerWidthSizable | kCALayerHeightSizable | kCALayerMaxXMargin;
    titleLayer.allowsEdgeAntialiasing = YES;
    titleLayer.allowsFontSubpixelQuantization = YES;
    titleLayer.wrapped = NO;
    titleLayer.contentsScale = [[NSScreen mainScreen] backingScaleFactor];
    titleLayer.frame = CGRectMake(x, artistFontSize + 4.0, backgroundSize.width - x, titleFontSize + 4.0);
    titleLayer.name = @"WaveMarkDescriptionTitleLayer";
    [clippedBackground addSublayer:titleLayer];

    CATextLayer* artistLayer = [CATextLayer layer];
    artistLayer.drawsAsynchronously = YES;
    artistLayer.autoresizingMask = kCALayerWidthSizable | kCALayerHeightSizable | kCALayerMaxXMargin;
    artistLayer.allowsEdgeAntialiasing = YES;
    artistLayer.wrapped = NO;
    artistLayer.name = @"WaveMarkDescriptionArtistLayer";
    artistLayer.contentsScale = [[NSScreen mainScreen] backingScaleFactor];
    artistLayer.frame = CGRectMake(x, 0.0, backgroundSize.width - x, titleFontSize + 4.0);
    //artistLayer.constraints = @[ minXConstraint, minYConstraint, maxXConstraint, heightConstraint];
    [clippedBackground addSublayer:artistLayer];
    
//    CALayer* shinyLayer = [CALayer layer];
//    shinyLayer.zPosition = 131.0f;
//    shinyLayer.autoresizingMask = kCALayerNotSizable;
//    shinyLayer.allowsEdgeAntialiasing = YES;
//    shinyLayer.shouldRasterize = YES;
//    //shinyLayer.opacity = 1.0f;
//    shinyLayer.drawsAsynchronously = YES;
//    shinyLayer.backgroundColor = [[Defaults sharedDefaults] lightFakeBeamColor].CGColor;
//    shinyLayer.rasterizationScale = rootLayer.contentsScale;
//    shinyLayer.contentsScale = [[NSScreen mainScreen] backingScaleFactor];
//    shinyLayer.masksToBounds = YES;
//    shinyLayer.name = @"WaveMarkDescriptionShinyLayer";
//    shinyLayer.frame = CGRectMake(1.0f, 5.0f, 3.0f, backgroundSize.height - 10.0f);
//    [background addSublayer:shinyLayer];
    
    CALayer* reflectionLayer = [CALayer layer];
    reflectionLayer.magnificationFilter = kCAFilterLinear;
    reflectionLayer.minificationFilter = kCAFilterLinear;
    reflectionLayer.zPosition = 150.0f;
    NSImage* reflectionImage = [NSImage imageNamed:@"Reflection"];
    reflectionLayer.contents = reflectionImage;
    reflectionLayer.allowsEdgeAntialiasing = YES;
    reflectionLayer.shouldRasterize = YES;
    reflectionLayer.opacity = 0.0f;
    reflectionLayer.drawsAsynchronously = YES;
    reflectionLayer.rasterizationScale = wv.layer.contentsScale;
    reflectionLayer.contentsScale = [[NSScreen mainScreen] backingScaleFactor];
    reflectionLayer.masksToBounds = YES;
    reflectionLayer.frame = CGRectMake(0.0, 0.0, reflectionImage.size.width, background.frame.size.height);
    reflectionLayer.name = @"WaveMarkDescriptionReflectionLayer";
    [clippedBackground addSublayer:reflectionLayer];

    return background;
}

- (void)resolveImageForURL:(NSURL*)url callback:(void (^)(NSImage*))callback
{
    dispatch_async(_imageQueue, ^{
        NSImage* image = [[NSImage alloc] initWithContentsOfURL:url];
        dispatch_async(dispatch_get_main_queue(), ^{
            callback(image);
        });
    });
}

- (void)reloadTrackDescriptions
{
    WaveView* wv = (WaveView*)self.view;
    NSArray<CALayer*>* goneLayers = [wv.markLayer.sublayers copy];
    [goneLayers makeObjectsPerformSelector:@selector(removeFromSuperlayer)];
    _markTracking = [NSMutableSet set];
    [self updateTrackDescriptions];
}

- (void)updateTrackDescriptions
{
    WaveView* wv = (WaveView*)self.view;
    
    if (_frames == 0 || _trackList == nil) {
        return;
    }
    if (self.view.enclosingScrollView != nil) {
        return;
    }

    NSRect documentVisibleRect = NSMakeRect(0.0, 0.0, self.view.bounds.size.width, self.view.bounds.size.height);
    
    const CGFloat xMin = documentVisibleRect.origin.x;
    const CGFloat width = documentVisibleRect.size.width;
    const CGFloat backgroundWidth = 300.0 + _imageSize.width + 12.0;
    const unsigned long long frameOffset = floor((xMin - backgroundWidth) * self.framesPerPixel);
    
    TrackListIterator* iter = nil;
    NSMutableSet* neededTrackFrames = [NSMutableSet set];

    //
    // Go through our tracklist starting from the screen-offset and add all the
    // frame-offsets we find until we reach the end of the screen.
    //
    unsigned long long nextTrackFrame = [_trackList firstTrackFrame:&iter];
    while (nextTrackFrame != ULONG_LONG_MAX) {
        if (frameOffset <= nextTrackFrame) {
            const CGFloat x = floor((nextTrackFrame / self.framesPerPixel) - xMin);
            if (x >= width) {
                break;
            }
            [neededTrackFrames addObject:[NSNumber numberWithUnsignedLongLong:nextTrackFrame]];
        }
        nextTrackFrame = [_trackList nextTrackFrame:iter];
    };

    NSArray<NSNumber*>* trackFrames = [[neededTrackFrames allObjects] sortedArrayUsingSelector:@selector(compare:)];

    //
    // See if we already have sublayers that cover these needed track frame offsets.
    //
    NSArray<CALayer*>* layers = [[wv.markLayer sublayers] copy];
    for (CALayer* layer in layers) {
        NSNumber* keyNumber = [layer valueForKey:kFrameOffsetLayerKey];
        assert(keyNumber);
        // If we don't need this one anymore.
        if (![neededTrackFrames containsObject:keyNumber]) {
            // Then recycle it.
            [_reusableLayers addObject:layer];
            [layer removeFromSuperlayer];
        } else {
            // Take this track frame offset off the to-do list - we already got it covered.
            [neededTrackFrames removeObject:keyNumber];
        }
    }

    //
    // Add needed tiles from the to-do list.
    //
    for (NSNumber* neededFrame in neededTrackFrames) {
        // Try to get a reusable background first.
        CALayer* background = [self.reusableLayers lastObject];
        [_reusableLayers removeLastObject];
        
        // Create one if we did not find a reusable one.
        if (background == nil) {
            background = [self trackLayer];
            [wv.markLayer addSublayer:background];
        }

        // Tag the background layer with the track frame offset.
        [background setValue:neededFrame forKey:kFrameOffsetLayerKey];
        
        //
        // Initialize the display elements with track data.
        //
        CALayer* imageLayer = background.sublayers[kClippingHostLayerIndex].sublayers[kImageLayerIndex];
        CATextLayer* timeLayer = background.sublayers[kClippingHostLayerIndex].sublayers[kTimeLayerIndex];
        CATextLayer* titleLayer = background.sublayers[kClippingHostLayerIndex].sublayers[kTitleLayerIndex];
        CATextLayer* artistLayer = background.sublayers[kClippingHostLayerIndex].sublayers[kArtistLayerIndex];
        
        background.name = [neededFrame stringValue];

        TimedMediaMetaData* track = [_trackList trackAtFrame:[neededFrame unsignedLongLongValue]];

        NSImage* image = nil;
        if (track.meta.artwork != nil) {
            image = [NSImage resizedImageWithData:track.meta.artwork
                                     size:imageLayer.frame.size];
        } else {
            image = [NSImage resizedImage:[NSImage imageNamed:@"UnknownSong"]
                                     size:imageLayer.frame.size];
            if (track.meta.artworkLocation != nil) {
                // We can try to resolve the artwork image from the URL.
                [self resolveImageForURL:track.meta.artworkLocation callback:^(NSImage* image){
                    [track.meta setArtworkFromImage:image];
                    imageLayer.contents = image;
                }];
            }
        }

        imageLayer.contents = image;
        
        
        NSAttributedString* title = [self textWithFont:_titleFont
                                                 color:_titleColor
                                                  text:track.meta.title != nil ? track.meta.title : @""];
        titleLayer.string = title;
        
        NSAttributedString* artist = [self textWithFont:_artistFont
                                                  color:_artistColor
                                                   text:track.meta.artist != nil ? track.meta.artist : @""];
        artistLayer.string = artist;
        
        NSAttributedString* time = [self textWithFont:_timeFont
                                                color:_timeColor
                                                 text:[_delegate stringFromFrame:[track.frame unsignedLongLongValue]]];
        timeLayer.string = time;
    }

    //
    // Position all tiles -- we need to do this continuously to fake scrolling.
    //
    if (trackFrames.count > 0) {
        for (size_t i = 0; i < trackFrames.count; i++) {
            NSNumber* next = nil;
            NSNumber* current = trackFrames[i];
            if (trackFrames.count > 1 && i < trackFrames.count - 1) {
                next = trackFrames[i + 1];
            }

            BOOL active = current == _currentTrack.frame;

            CGFloat x = [self trackMarkOffsetWithFrameOffset:[current unsignedLongLongValue]] - xMin;
            CALayer* currentLayer = [self sublayerForFrame:current layers:wv.markLayer.sublayers];
            assert(currentLayer);
            // We position using the layout manager to allow for constraint based layout.
            CAConstraint* minXConstraint = [CAConstraint constraintWithAttribute:kCAConstraintMinX relativeTo:@"superlayer" attribute:kCAConstraintMinX offset:x];
            CAConstraint* minYConstraint = [CAConstraint constraintWithAttribute:kCAConstraintMinY relativeTo:@"superlayer" attribute:kCAConstraintMinY];
            CAConstraint* maxXConstraint = nil;
            if (next != nil) {
                maxXConstraint = [CAConstraint constraintWithAttribute:kCAConstraintMaxX relativeTo:[next stringValue] attribute:kCAConstraintMinX offset:-2.0f];
            } else {
                maxXConstraint = [CAConstraint constraintWithAttribute:kCAConstraintMaxX relativeTo:@"superlayer" attribute:kCAConstraintMaxX];
            }
            CAConstraint* maxYConstraint = [CAConstraint constraintWithAttribute:kCAConstraintMaxY relativeTo:@"superlayer" attribute:kCAConstraintMaxY];
            [currentLayer setConstraints:@[ minXConstraint, maxXConstraint, minYConstraint , maxYConstraint ]];

            // Render handle bar coordinates and store in our map.
            NSRect rect = NSMakeRect(x, 0.0, kMarkerHandleWidth, wv.frame.size.height);
            NSValue* rectValue = [NSValue valueWithRect:rect];
            FrameMarker* marker = [[FrameMarker alloc] initWithFrame:current rect:rectValue];
            [_markTracking addObject:marker];

            CALayer* fxLayer = currentLayer.sublayers[kFXLayerIndex];
            CALayer* handleLayer = currentLayer.sublayers[kHandleLayerIndex];
            fxLayer.opacity = active ? 1.0f : 0.0f;
            handleLayer.backgroundColor = active ? _handleColors[ActiveHandle].CGColor : _handleColors[NormalHandle].CGColor;
            if (active) {
                _activeLayer = currentLayer;
            }
            currentLayer.sublayers[kClippingHostLayerIndex].sublayers[kImageLayerIndex].opacity = kRegularImageViewOpacity;
            //currentLayer.sublayers[kClippingHostLayerIndex].sublayers[kImageLayerIndex].filters = @[ _vibranceFilter ];
        }
        [wv.markLayer setNeedsLayout];
        [wv.markLayer layoutIfNeeded];
    }
}

- (void)updateTiles
{
    NSSize tileSize = { _tileWidth, self.view.bounds.size.height };
    //_markTracking = [NSMutableSet set];
    
    NSRect documentVisibleRect;
    if (self.view.enclosingScrollView != nil) {
        documentVisibleRect = self.view.enclosingScrollView.documentVisibleRect;
        // Lie to get the last tile invisilbe, always. That way we wont regularly
        // see updates of the right most tile when the scrolling follows playback.
        documentVisibleRect.size.width += tileSize.width;
    } else {
        documentVisibleRect = NSMakeRect(0.0, 0.0, self.view.bounds.size.width, self.view.bounds.size.height);
    }
    
    const CGFloat xMin = floor(NSMinX(documentVisibleRect) / tileSize.width) * tileSize.width;
    const CGFloat xMax = xMin + (ceil((NSMaxX(documentVisibleRect) - xMin) / tileSize.width) * tileSize.width);
    const CGFloat yMin = floor(NSMinY(documentVisibleRect) / tileSize.height) * tileSize.height;
    const CGFloat yMax = ceil((NSMaxY(documentVisibleRect) - yMin) / tileSize.height) * tileSize.height;
    
    // Figure out the tile frames we would need to get full coverage and add them to
    // the to-do list.
    NSMutableSet* neededTileFrames = [NSMutableSet set];
    for (CGFloat x = xMin; x < xMax; x += tileSize.width) {
        for (CGFloat y = yMin; y < yMax; y += tileSize.height) {
            NSRect rect = NSMakeRect(x, y, tileSize.width, tileSize.height);
            [neededTileFrames addObject:[NSValue valueWithRect:rect]];
        }
    }
    
    // See if we already have subviews that cover these needed frames.
    NSArray<TileView*>* screenTiles = [[self.view subviews] copy];
    
    for (TileView* subview in screenTiles) {
        //        assert(subview.frame.size.width < 512);
        NSValue* frameRectVal = [NSValue valueWithRect:subview.frame];
        // If we don't need this one any more.
        if (![neededTileFrames containsObject:frameRectVal]) {
            // Then recycle it.
            [_reusableViews addObject:subview];
            [subview removeFromSuperview];
        } else {
            // Take this frame rect off the to-do list.
            [neededTileFrames removeObject:frameRectVal];
        }
    }
    
    // Add needed tiles from the to-do list.
    for (NSValue* neededFrame in neededTileFrames) {
        TileView* view = [self.reusableViews lastObject];
        [_reusableViews removeLastObject];
        
        // Create one if we did not find a reusable one.
        if (nil == view) {
            view = [[TileView alloc] initWithFrame:NSZeroRect waveLayerDelegate:self];
        }
        
        // Place it and install it.
        view.frame = [neededFrame rectValue];
        [self.view addSubview:view];
        
        [view.waveLayer setNeedsDisplay];

        [self loadBeatsForTile:view];
        //[self loadMarksForTile:view];
    }
}

# pragma mark - Wave CALayer delegate

// FIXME: Assert we cant solve this better using some variant of a CAShapeLayer. Right now this custom layer drawing is hooked into the screen asking for refresh.
// FIXME: If we used a CAShapeLayer d that way we would have a lot more control over the process as we determine what to put onto the layer the moment we composite the screen and not the moment the screen asks for our refresh.
- (void)drawLayer:(CALayer*)layer inContext:(CGContextRef)context
{
    if (_visualSample == nil || layer.superlayer.frame.origin.x < 0) {
        return;
    }
    
    assert(layer.frame.size.width < 512);
    
    /*
     We try to fetch visual data first;
     - when that fails, we draw a box and trigger a task preparing visual data
     - when that works, we draw it
     */
    CGContextSetAllowsAntialiasing(context, YES);
    CGContextSetShouldAntialias(context, YES);
    
    const unsigned long int start = layer.superlayer.frame.origin.x;
    unsigned long int samplePairCount = layer.bounds.size.width + 1;
    //    NSLog(@"drawing tile starting at %ld", start);
    
    // Try to get visual sample data for this layer tile.
    NSData* buffer = [_visualSample visualsFromOrigin:start];
    
    if (buffer == nil) {
        // We didnt find any visual data - lets make sure we get some in the near future...
        CGContextSetFillColorWithColor(context, _waveFillColor.CGColor);
        CGContextFillRect(context, layer.bounds);
        
        if (start >= _visualSample.width) {
            return;
        }
        
        [_visualSample prepareVisualsFromOrigin:start
                                          pairs:samplePairCount
                                         window:_offsetBlock()
                                          total:_widthBlock()
                                       callback:^(void){
            dispatch_async(dispatch_get_main_queue(), ^{
                [layer setNeedsDisplay];
            });
        }];
        return;
    }
    
    VisualPair* data = (VisualPair*)buffer.bytes;
    
    if (buffer.length / sizeof(VisualPair) < samplePairCount) {
        // We might have gotten less data than requested, accomodate.
        samplePairCount = buffer.length / sizeof(VisualPair);
    }
    
    CGFloat mid = floor(layer.bounds.size.height / 2.0);
    assert(mid > 0.01);
    CGFloat tops[samplePairCount];
    CGFloat bottoms[samplePairCount];
    
    for (unsigned int sampleIndex = 0; sampleIndex < samplePairCount; sampleIndex++) {
        //assert(data[sampleIndex].negativeAverage != NAN);
        assert(!isnan(data[sampleIndex].negativeAverage));
        CGFloat top = (mid + ((data[sampleIndex].negativeAverage * layer.bounds.size.height) / 2.0)) - 2.0;
        assert(!isnan(top));
        assert(!isnan(data[sampleIndex].positiveAverage));
        CGFloat bottom = (mid + ((data[sampleIndex].positiveAverage * layer.bounds.size.height) / 2.0)) + 2.0;
        assert(!isnan(bottom));
        tops[sampleIndex] = top;
        bottoms[sampleIndex] = bottom;
    }
    
    //    CGContextSetFillColorWithColor(context, [[NSColor blueColor] CGColor]);
    //    CGContextFillRect(context, layer.frame);
    
    CGContextSetFillColorWithColor(context, _waveFillColor.CGColor);
    
    CGContextSetLineCap(context, kCGLineCapRound);
    CGContextSetLineJoin(context, kCGLineJoinRound);
    
    CGFloat lineWidth = 4.0;
    CGFloat aliasingWidth = 2.0;
    CGFloat outlineWidth = 4.0;
    
    // Draw aliasing curve.
    CGContextSetLineWidth(context, lineWidth + outlineWidth + aliasingWidth);
    CGContextSetStrokeColorWithColor(context, [[_waveFillColor colorWithAlphaComponent:0.45f] CGColor]);
    for (unsigned int sampleIndex = 0; sampleIndex < samplePairCount; sampleIndex++) {
        CGContextMoveToPoint(context, sampleIndex, tops[sampleIndex]);
        CGContextAddLineToPoint(context, sampleIndex, bottoms[sampleIndex]);
    }
    CGContextStrokePath(context);
    
    // Draw outline curve.
    CGContextSetLineWidth(context, lineWidth + outlineWidth);
    CGContextSetStrokeColorWithColor(context, _waveOutlineColor.CGColor);
    for (unsigned int sampleIndex = 0; sampleIndex < samplePairCount; sampleIndex++) {
        CGContextMoveToPoint(context, sampleIndex, tops[sampleIndex]);
        CGContextAddLineToPoint(context, sampleIndex, bottoms[sampleIndex]);
    }
    CGContextStrokePath(context);
    
    // Draw fill curve.
    CGContextSetLineWidth(context, lineWidth);
    CGContextSetStrokeColorWithColor(context, _waveFillColor.CGColor);
    for (unsigned int sampleIndex = 0; sampleIndex < samplePairCount; sampleIndex++) {
        CGContextMoveToPoint(context, sampleIndex, tops[sampleIndex]);
        CGContextAddLineToPoint(context, sampleIndex, bottoms[sampleIndex]);
    }
    CGContextStrokePath(context);
}

# pragma mark - Mouse Handling

- (FrameMarker*)frameMarkForLocation:(NSPoint)location
{
    for (FrameMarker* marker in _markTracking) {
        NSRect rect = [marker.rect rectValue];
        if (NSPointInRect(location, rect)) {
            return marker;
        }
    }
    return nil;
}

- (CALayer*)sublayerForFrame:(NSNumber*)frame layers:(NSArray<CALayer*>*)layers
{
    NSPredicate* predicate = [NSPredicate predicateWithFormat:@"SELF.frameOffset == %@", frame];
    NSArray<CALayer*>* filtered = [layers filteredArrayUsingPredicate:predicate];
    if (filtered.count != 1) {
        return nil;
    }
    return filtered[0];
}

- (void)animateTrackMark:(CALayer*)background
{
    CALayer* fxLayer = background.sublayers[kFXLayerIndex];
    CALayer* handleLayer = background.sublayers[kHandleLayerIndex];
    const float beatsPerCycle = 4.0f;
    
    CABasicAnimation* animation = [CABasicAnimation animationWithKeyPath:@"opacity"];
    animation.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseIn];
    animation.fillMode = kCAFillModeForwards;
    animation.removedOnCompletion = YES;
    NSAssert(_currentTempo > 0.0, @"current tempo set to zero, that should never happen");
    animation.duration = 0.5 * beatsPerCycle * 60.0f / _currentTempo;
    animation.fromValue = @(0.0);
    animation.toValue = @(1.0);
    animation.repeatCount = 1;
    [fxLayer addAnimation:animation forKey:@"beat"];
    
    animation = [CABasicAnimation animationWithKeyPath:@"backgroundColor"];
    animation.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseIn];
    animation.fillMode = kCAFillModeForwards;
    animation.removedOnCompletion = NO;
    animation.duration = beatsPerCycle * 60.0f / _currentTempo;
    animation.toValue = (id)_handleColors[HoverHandle].CGColor;
    animation.fromValue = (id)_handleColors[ActiveHandle].CGColor;
    animation.repeatCount = 1;
    [handleLayer addAnimation:animation forKey:@"beat"];
    
    handleLayer.backgroundColor = _handleColors[ActiveHandle].CGColor;
    fxLayer.opacity = 0.0f;
}

- (void)beatEffect:(NSNotification*)notification
{
    WaveView* wv = (WaveView*)self.view;

    NSDictionary* dict = notification.object;

    NSNumber* tempo = dict[kBeatNotificationKeyTempo];
    float value = [tempo floatValue];
    if (value > 0.0) {
        if (value != _currentTempo) {
            _currentTempo = value;
        }
    }

    const unsigned long long beatIndex = [dict[kBeatNotificationKeyBeat] unsignedLongLongValue];

    // Switch state every second beat.
    if (beatIndex % 4 == 1) {
        [self animateTrackMark:_activeLayer];
    }
}

- (CGFloat)trackMarkOffsetWithFrameOffset:(unsigned long long)frame
{
    assert(_frames);
    return (frame / self.framesPerPixel) - 2.0;
}

- (void)dragMark:(NSPoint)location
{
    assert(_draggingLayer);

    unsigned long long newFrame = (location.x - (kMarkerHandleWidth / 2.0)) * self.framesPerPixel;
   
    CGFloat x = [self trackMarkOffsetWithFrameOffset:newFrame];

    [CATransaction begin];
    [CATransaction setDisableActions:YES];

    // Patch the constraints to now have a new left-side (minX) constraint.
    CAConstraint* minXConstraint = [CAConstraint constraintWithAttribute:kCAConstraintMinX
                                                              relativeTo:@"superlayer"
                                                               attribute:kCAConstraintMinX
                                                                  offset:x];
    _draggingLayer.constraints = @[ minXConstraint,
                                    _draggingLayer.constraints[1],
                                    _draggingLayer.constraints[2],
                                    _draggingLayer.constraints[3]];

    WaveView* wv = (WaveView*)self.view;
    CATextLayer* timeLayer = _draggingLayer.sublayers[kClippingHostLayerIndex].sublayers[kTimeLayerIndex];

    NSFont* timeFont = [[Defaults sharedDefaults] smallFont];
    NSColor* timeColor = [[Defaults sharedDefaults] regularFakeBeamColor];

    NSAttributedString* time = [self textWithFont:timeFont
                                            color:timeColor
                                             text:[_delegate stringFromFrame:newFrame]];
    timeLayer.string = time;
    
    [wv.markLayer setNeedsLayout];
    [wv.markLayer layoutIfNeeded];

    [CATransaction commit];
}

- (void)duckImageOn:(CALayer*)background forwards:(BOOL)forwards
{
    CALayer* image = background.sublayers[kClippingHostLayerIndex].sublayers[kImageLayerIndex];
    CATextLayer* time = background.sublayers[kClippingHostLayerIndex].sublayers[kTimeLayerIndex];
    CATextLayer* title = background.sublayers[kClippingHostLayerIndex].sublayers[kTitleLayerIndex];
    CATextLayer* artist = background.sublayers[kClippingHostLayerIndex].sublayers[kArtistLayerIndex];

    image.opacity = forwards ? 0.0f : kRegularImageViewOpacity;
    //image.filters = forwards ? nil : @[ _vibranceFilter ];
    title.opacity = forwards ? 0.0f : 1.0f;
    artist.opacity = forwards ? 0.0f : 1.0f;

    CGFloat x = forwards ? kMarkerHandleWidth + 2.0 : image.frame.size.width + kMarkerHandleWidth + 2.0;

    time.frame = CGRectMake(x, time.frame.origin.y, background.bounds.size.width - x, time.frame.size.height);
    title.frame = CGRectMake(x, title.frame.origin.y, background.bounds.size.width - x, title.frame.size.height);
    artist.frame = CGRectMake(x, artist.frame.origin.y, background.bounds.size.width - x, artist.frame.size.height);
}

- (CALayer*)sublayerForLocation:(NSPoint)location layers:(NSArray<CALayer*>*)layers
{
    for (CALayer* layer in layers) {
        if (NSPointInRect(location, layer.frame)) {
            return layer;
        }
    }
    return nil;
}

- (void)reflectionWithLayer:(CALayer*)background forwards:(BOOL)forwards
{
    WaveView* wv = (WaveView*)self.view;

    CALayer* layer = background.sublayers[kClippingHostLayerIndex].sublayers[kReflectionLayerIndex];

    CABasicAnimation* animation = [CABasicAnimation animationWithKeyPath:@"transform.translation.x"];
    if (forwards) {
        animation.fromValue = @(0);
        animation.toValue = @(_draggingLayer.frame.size.width + layer.frame.size.width) ;
    } else {
        animation.toValue = @(0);
        animation.fromValue = @(_draggingLayer.frame.size.width + layer.frame.size.width) ;
    }
    animation.repeatCount = 1;
    animation.autoreverses = NO;
    animation.duration = wv.frame.size.width / 1630.0f;
    animation.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionLinear];
    animation.fillMode = kCAFillModeForwards;
    animation.removedOnCompletion = YES;
    [layer addAnimation:animation forKey:@"glossyReflection"];
    
    animation = [CABasicAnimation animationWithKeyPath:@"opacity"];
    if (forwards) {
        animation.fromValue = @(1.0);
        animation.toValue = @(0.2f);
    } else {
        animation.toValue = @(1.0);
        animation.fromValue = @(0.0f);
    }
    animation.repeatCount = 1;
    animation.autoreverses = NO;
    animation.duration = wv.frame.size.width / 1400.0f;
    animation.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionLinear];
    animation.fillMode = kCAFillModeForwards;
    animation.removedOnCompletion = YES;
    [layer addAnimation:animation forKey:@"shiny"];
    
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    layer.opacity = 0.0f;
    layer.position = CGPointMake(-(layer.frame.size.width) / 2.0f, layer.position.y);
    [CATransaction commit];
}

/// Updates screen cursor
///
/// - Parameter event: system event
///
/// We need to make sure nothing changes the cursor in our view - thus we override the handler but do not pass down the
/// event. That way our cursor can be controlled exclusively during the mouseMove handler.
///
/// We cant use this handler as it appears to get called only sporadically, depending on other screen activities -- entirely
/// enigmatic but the result is only moveMove gets reliable called and that is where we do our cursor updates.
///
/// Without this override, some other stuff trashes our cursor updates -- i have no idea what that was.
- (void)cursorUpdate:(NSEvent*)event
{
}

- (CGFloat)idealWidthForTrack:(TimedMediaMetaData*)track
{
    CGFloat width = 0.0f;

    NSAttributedString* title = [self textWithFont:_titleFont
                                             color:_titleColor
                                              text:track.meta.title != nil ? track.meta.title : @""];
    
    NSAttributedString* artist = [self textWithFont:_artistFont
                                              color:_artistColor
                                               text:track.meta.artist != nil ? track.meta.artist : @""];
    
    NSAttributedString* time = [self textWithFont:_timeFont
                                            color:_timeColor
                                             text:[_delegate stringFromFrame:[track.frame unsignedLongLongValue]]];
    width = title.size.width;
    if (artist.size.width > width) {
        width = artist.size.width;
    }
    if (time.size.width > width) {
        width = time.size.width;
    }

    return ceilf(width + self.view.bounds.size.height + kMarkerHandleWidth + 8.0);
}

- (void)duckStackAfter:(CALayer*)popularMarker
{
    WaveView* wv = (WaveView*)self.view;
    NSArray<CALayer*>* orderedLayers = [wv.markLayer.sublayers sortedArrayUsingComparator:^NSComparisonResult(id  _Nonnull obj1, id  _Nonnull obj2) {
        NSNumber* frame1 = [obj1 valueForKey:kFrameOffsetLayerKey];
        NSNumber* frame2 = [obj2 valueForKey:kFrameOffsetLayerKey];
        return [frame1 compare:frame2];
    }];
    
    NSNumber* popularFrameOffset = [popularMarker valueForKey:kFrameOffsetLayerKey];
    TimedMediaMetaData* track = [_trackList trackAtFrame:[popularFrameOffset unsignedLongLongValue]];
    assert(track);

    CGFloat neededWidth = [self idealWidthForTrack:track];

    // Shortcut if the marker already has enough room.
    if (popularMarker.bounds.size.width >= neededWidth) {
        return;
    }
    CGFloat x = neededWidth + popularMarker.frame.origin.x;

    for (CALayer* layer in orderedLayers) {
        if (layer == popularMarker) {
            continue;
        }
        if (layer.frame.origin.x < popularMarker.frame.origin.x) {
            continue;
        }
        // Did we reach the right side of things?
        if (layer.frame.origin.x > x) {
            break;
        }
        // Patch the constraints to now have a new left-side (minX) constraint.
        CAConstraint* minXConstraint = [CAConstraint constraintWithAttribute:kCAConstraintMinX
                                                                  relativeTo:@"superlayer"
                                                                   attribute:kCAConstraintMinX
                                                                      offset:x];
        assert(layer.constraints.count == 4);
        layer.constraints = @[ minXConstraint,
                               layer.constraints[1],
                               layer.constraints[2],
                               layer.constraints[3]];
        x += 20.0;
    }
    [wv.markLayer setNeedsLayout];
    [wv.markLayer layoutIfNeeded];
}

- (void)mouseMoved:(NSEvent*)event
{
    if (self.view.enclosingScrollView != nil) {
        [super mouseMoved:event];
        return;
    }
    WaveView* wv = (WaveView*)self.view;

    NSPoint locationInWindow = [event locationInWindow];
    NSPoint location = [self.view convertPoint:locationInWindow fromView:nil];
    
    FrameMarker* marker = [self frameMarkForLocation:location];
    CALayer* markerBackgroundLayer = nil;
    CALayer* handleLayer = nil;
    CALayer* fxLayer = nil;

    if (marker == nil) {
        // We now didnt find any marker under the cursor - lets see if we are on any background.
        markerBackgroundLayer = [self sublayerForLocation:location layers:wv.markLayer.sublayers];
    } else {
        markerBackgroundLayer = [self sublayerForFrame:marker.frame layers:wv.markLayer.sublayers];
        assert(markerBackgroundLayer);
        handleLayer = markerBackgroundLayer.sublayers[kHandleLayerIndex];
        fxLayer = markerBackgroundLayer.sublayers[kFXLayerIndex];
        _previousLayer = [self sublayerForLocation:NSMakePoint(markerBackgroundLayer.frame.origin.x - 4.0f, location.y) layers:wv.markLayer.sublayers];
    }

    _trackingMarker = marker;

    if (handleLayer != _handleLayer) {
        if (_handleLayer != nil) {
            NSNumber* frameOffset = [_draggingLayer valueForKey:kFrameOffsetLayerKey];
            BOOL active = _currentTrack != nil && [frameOffset isEqualToNumber:_currentTrack.frame];
            _handleLayer.backgroundColor = active ? _handleColors[ActiveHandle].CGColor : _handleColors[NormalHandle].CGColor;
            _fxLayer.opacity = active ? 1.0f : 0.0f;
        }
    }

    if (handleLayer != nil) {
        handleLayer.backgroundColor = _handleColors[HoverHandle].CGColor;
        fxLayer.opacity = 0.0f;

        // Did we freshly enter that handle area?
        if (_handleLayer == nil) {
            [[NSCursor resizeLeftRightCursor] set];
        }
        [self duckImageOn:markerBackgroundLayer forwards:YES];
    } else {
        [self duckImageOn:_draggingLayer forwards:NO];
        [[NSCursor arrowCursor] set];
    }

    if (_duckForLayer != markerBackgroundLayer) {
        [self updateTrackDescriptions];
    }

    // Are we above a description?
    if (markerBackgroundLayer != nil) {
        // Highlight by making the image layer entirely opaque,unless we are on top of a marker.
        markerBackgroundLayer.sublayers[kClippingHostLayerIndex].sublayers[kImageLayerIndex].opacity = marker == nil ? 1.0f : 0.0f;
        //markerBackgroundLayer.sublayers[kClippingHostLayerIndex].sublayers[kImageLayerIndex].filters = nil;

        [self duckStackAfter:markerBackgroundLayer];
        _duckForLayer = markerBackgroundLayer;
    }

    _draggingLayer = markerBackgroundLayer;
    _handleLayer = handleLayer;
    _fxLayer = fxLayer;
    
    [super mouseMoved:event];
}

- (void)mouseExited:(NSEvent*)event
{
    if (!_tracking) {
        _handleLayer.backgroundColor = _handleColors[NormalHandle].CGColor;
        [self duckImageOn:_draggingLayer forwards:NO];
        [[NSCursor arrowCursor] set];
    }

    if (_duckForLayer) {
        [self updateTrackDescriptions];
    }

    [super mouseExited:event];
}

- (CGRect)rangeRectForMarker:(FrameMarker*)popularMarker
{
    if (_markTracking.count < 2) {
        return  CGRectZero;
    }

    NSArray<NSNumber*>* trackFrames = [_trackList.frames sortedArrayUsingSelector:@selector(compare:)];
    NSUInteger index = [trackFrames indexOfObject:popularMarker.frame];
    assert(index != NSNotFound);

    NSNumber* left = nil;
    NSNumber* right = nil;

    if (index > 0) {
        left = trackFrames[index - 1];
    }
    if (trackFrames.count > 0 && index < trackFrames.count - 1) {
        right = trackFrames[index + 1];
    }

    CGFloat start = 0.0;
    if (left != nil) {
        start = [self trackMarkOffsetWithFrameOffset:[left unsignedLongLongValue]];
    }
    CGFloat end = self.view.frame.size.width;
    if (right != nil) {
        end = [self trackMarkOffsetWithFrameOffset:[right unsignedLongLongValue]];
    }

    return CGRectMake((start + 12.0), 0.0f, (end - 4.0) - (start + 12.0), 1.0f);
}

- (void)mouseDown:(NSEvent*)event
{
    // We now are tracking depending on if we have a marker below the cursor.
    _tracking = _trackingMarker != nil;

    WaveView* wv = (WaveView*)self.view;
    NSPoint locationInWindow = [event locationInWindow];
    NSPoint location = [self.view convertPoint:locationInWindow fromView:nil];

    if (!_tracking) {
        _draggingLayer = nil;
        unsigned long long newFrame = (_visualSample.sample.frames * location.x ) / self.view.frame.size.width;
        [_delegate seekToFrame:newFrame];
    } else {
        CALayer* background = [self sublayerForLocation:location layers:wv.markLayer.sublayers];
        if (background != nil && _draggingLayer != background) {
            _draggingLayer = background;
            _handleLayer = background.sublayers[0];
            _fxLayer = background.sublayers[6];
        }
        _draggingRangeRect = [self rangeRectForMarker:_trackingMarker];
        _handleLayer.backgroundColor = _handleColors[PressedHandle].CGColor;
        _fxLayer.opacity = 1.0;
        [self reflectionWithLayer:background forwards:YES];
    }

    [super mouseDown:event];
}

- (void)mouseUp:(NSEvent *)event
{
    if (_frames == 0 || _trackList == nil) {
        [super mouseUp:event];
        return;
    }
    
    if (!_tracking || _trackingMarker == nil || _draggingLayer == nil) {
        [super mouseUp:event];
        return;
    }
    
    NSPoint locationInWindow = [event locationInWindow];
    NSPoint location = [self.view convertPoint:locationInWindow fromView:nil];
    
    unsigned long long oldFrame = [_trackingMarker.frame unsignedLongLongValue];
    unsigned long long newFrame = (location.x - (kMarkerHandleWidth / 2.0)) * self.framesPerPixel;

    if (newFrame == oldFrame) {
        NSLog(@"track frame didnt change, skip updates");
        [super mouseUp:event];
        return;
    }

    [self dragMark:location];
    
    _tracking = NO;

    [_delegate moveTrackAtFrame:oldFrame toFrame:newFrame];

    // Fake a mouse move event to assert that the cursor gets recognized above the handle
    // right away.
    [self mouseMoved:event];
}

- (void)mouseDragged:(NSEvent*)event
{
    if (_frames == 0) {
        [super mouseDragged:event];
        return;
    }

    NSPoint locationInWindow = [event locationInWindow];
    NSPoint location = [self.view convertPoint:locationInWindow fromView:nil];
    if (location.x < self.view.frame.origin.x) {
        location.x = self.view.frame.origin.x;
    }
    if (location.x > self.view.frame.origin.x + self.view.frame.size.width - 1.0) {
        location.x = self.view.frame.origin.x + self.view.frame.size.width - 1.0;
    }

    if (!_tracking || _trackingMarker == nil || _draggingLayer == nil) {
        unsigned long long newFrame = (_visualSample.sample.frames * location.x ) / self.view.frame.size.width;
        [_delegate seekToFrame:newFrame];
    }
    if (_draggingLayer != nil) {
        // Assert we dont cross another marker.
        if (location.x < _draggingRangeRect.origin.x) {
            location.x = _draggingRangeRect.origin.x;
        }
        if (location.x > _draggingRangeRect.origin.x + _draggingRangeRect.size.width) {
            location.x = _draggingRangeRect.origin.x + _draggingRangeRect.size.width;
        }
        // Visually drag the marker.
        [self dragMark:location];
    }

    [super mouseDragged:event];
}

- (void)rightMouseDown:(NSEvent*)event
{
    if (self.view.enclosingScrollView != nil) {
        _followTime = YES;
    } else {
        WaveView* wv = (WaveView*)self.view;
        NSPoint locationInWindow = [event locationInWindow];
        NSPoint location = [self.view convertPoint:locationInWindow fromView:nil];
        CALayer* background = [self sublayerForLocation:location layers:wv.markLayer.sublayers];
        if (background != nil) {
            NSNumber* frameOffset = [background valueForKey:kFrameOffsetLayerKey];
            assert(frameOffset);
            [_delegate seekToFrame:[frameOffset unsignedLongLongValue]];
            [self reflectionWithLayer:background forwards:YES];
        }
    }
    [self updateHeadPosition];
    [self updateTiles];
}

#pragma mark - Scroll View Notifications

- (void)updateHeadPosition
{
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    
    CGFloat head = [self calcHead];
    
    if (self.view.enclosingScrollView != nil) {
        if (_followTime) {
            CGPoint pointVisible = CGPointMake(self.view.enclosingScrollView.bounds.origin.x + floor(head - (self.view.enclosingScrollView.bounds.size.width / 2.0)),
                                               self.view.enclosingScrollView.bounds.origin.y + floor(self.view.enclosingScrollView.bounds.size.height / 2.0));
            
            [self.view scrollPoint:pointVisible];
        } else {
            // If the user has just requested some scrolling, do not interfere but wait
            // as long as that state is up.
            if (!_userMomentum) {
                // If the head came back into the middle of the screen, snap back to following
                // time with the scrollview.
                const CGFloat delta = 1.0f;
                CGFloat visibleCenter = self.view.enclosingScrollView.documentVisibleRect.origin.x + (self.view.enclosingScrollView.documentVisibleRect.size.width / 2.0f);
                if (visibleCenter - delta <= head && visibleCenter + delta >= head) {
                    _followTime = YES;
                }
            }
        }
        // There is no real scrolling for the track descriptions, we fake that by continuously
        // updating the layer positions.
        [self updateTrackDescriptions];
    }
    
    self.head = head;

    [CATransaction commit];
}

- (void)willStartLiveScroll:(NSNotification*)notification
{
    _userMomentum = YES;
    _followTime = NO;

    [self updateHeadPosition];
    [self updateTiles];
}

- (void)didLiveScroll:(NSNotification*)notification
{
    [self updateHeadPosition];
    [self updateTiles];
}

- (void)didEndLiveScroll:(NSNotification*)notification
{
    _userMomentum = NO;

    [self updateHeadPosition];
    [self updateTiles];
}


@end
