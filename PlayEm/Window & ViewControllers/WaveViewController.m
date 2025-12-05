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
#import "WaveView.h"
#import "Defaults.h"
#import "../Sample/LazySample.h"
#import "TrackList.h"
#import "IdentifiedTrack.h"
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

@property (assign, nonatomic) BOOL tracking;
@property (strong, nonatomic) NSMutableSet<FrameMarker*>* markTracking;
@property (strong, nonatomic) FrameMarker* trackingMarker;

@property (weak, nonatomic) IdentifiedTrack* currentTrack;

@property (strong, nonatomic) NSArray<NSColor*>* handleColors;
@property (assign, nonatomic) float currentTempo;

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
        
        dispatch_queue_attr_t attr = dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL, QOS_CLASS_USER_INITIATED, 0);
        _imageQueue = dispatch_queue_create("PlayEm.WaveViewImageQueue", attr);

        _markTracking = [NSMutableSet set];
        
        _currentTrack = nil;
        
        _handleColors = @[ [NSColor secondaryLabelColor],
                           [[Defaults sharedDefaults] regularFakeBeamColor],
                           [[Defaults sharedDefaults] lightFakeBeamColor],
                           [[Defaults sharedDefaults] lightFakeBeamColor]];
        
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
        CALayer* handleLayer = _activeLayer.sublayers[0];
        CALayer* fxLayer = _activeLayer.sublayers[5];
        [handleLayer removeAllAnimations];
        [fxLayer removeAllAnimations];
        handleLayer.backgroundColor = _handleColors[NormalHandle].CGColor;
        fxLayer.opacity = 0.0f;
    }

    NSLog(@"active track now %@", notification.object);
    _currentTrack = notification.object;
    _activeLayer = [self sublayerForFrame:_currentTrack.frame layers:wv.markLayer.sublayers];
    [self updateTrackDescriptions];
}

- (void)viewDidLayout
{
    [super viewDidLayout];
    
    

//    [[NSNotificationCenter defaultCenter] addObserver:self
//                                             selector:@selector(didUpdateTrackingAreas:)
//                                                 name:NSScrollViewWillStartLiveScrollNotification
//                                               object:nil];

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

//- (void)loadMarksForTile:(TileView*)tv
//{
//    CALayer* rootLayer = tv.markLayer;
//    
//    // Remove possibly existing marks for a clean start on this tile.
//    [rootLayer.sublayers makeObjectsPerformSelector:@selector(removeFromSuperlayer)];
//    [rootLayer setNeedsDisplay];
//    
//    NSArray<NSTrackingArea*>* oldTracking = [tv.trackingAreas copy];
//    for (NSTrackingArea* trackingArea in oldTracking) {
//        [tv removeTrackingArea:trackingArea];
//    }
//
//    if (_frames == 0 || self.view == nil || _trackList == nil || rootLayer.superlayer.frame.origin.x < 0) {
//        return;
//    }
//    
//    const double framesPerPixel = _frames / self.view.frame.size.width;
//    
//    const CGFloat start = rootLayer.superlayer.frame.origin.x;
//    const CGFloat width = rootLayer.frame.size.width;
//    
//    const unsigned long long frameOffset = floor(start * framesPerPixel);
//    
//    TrackListIterator* iter = nil;
//    unsigned long long nextTrackFrame = [_trackList firstTrackFrame:&iter];
//    
//    while (nextTrackFrame != ULONG_LONG_MAX) {
//        // A mark before our tile start frame needs to get skipped.
//        if (frameOffset < nextTrackFrame) {
//            const CGFloat x = (nextTrackFrame / framesPerPixel) - start;
//            // We need to stop drawing when we reached the total width of our layer.
//            if (x >= width) {
//                break;
//            }
//            
//            NSNumber* markFrame = [NSNumber numberWithUnsignedLongLong:nextTrackFrame];
//
//            // Add the track mark layer.
//            CALayer* trackmark = [CALayer layer];
//            trackmark.drawsAsynchronously = YES;
//            trackmark.backgroundColor = [_markerColor CGColor];
//            trackmark.frame = CGRectMake(x, 0, _markerWidth, self.view.frame.size.height);
//            [trackmark setValue:markFrame forKey:kFrameOffsetLayerKey];
//            [rootLayer addSublayer:trackmark];
//            
//            NSRect trackingRect = NSMakeRect(floor(tv.frame.origin.x + trackmark.frame.origin.x - 2.0),
//                                             trackmark.frame.origin.y,
//                                             ceil(trackmark.frame.size.width + 4.0),
//                                             trackmark.frame.size.height);
//            NSValue* rectValue = [NSValue valueWithRect:trackingRect];
//            FrameMarker* marker = [[FrameMarker alloc] initWithFrame:markFrame rect:rectValue];
//            [_markTracking addObject:marker];
//        }
//                
//        nextTrackFrame = [_trackList nextTrackFrame:iter];
//    };
//}

- (void)loadBeatsForTile:(TileView*)tile
{
    CALayer* rootLayer = tile.beatLayer;
    [rootLayer.sublayers makeObjectsPerformSelector:@selector(removeFromSuperlayer)];
    [rootLayer setNeedsDisplay];
    
    if (_frames == 0 || self.view == nil || _beatSample == nil || rootLayer.superlayer.frame.origin.x < 0) {
        return;
    }
    
    const double framesPerPixel = _frames / self.view.frame.size.width;
    
    const CGFloat start = rootLayer.superlayer.frame.origin.x;
    const CGFloat width = rootLayer.frame.size.width;
    
    const unsigned long long frameOffset = floor(start * framesPerPixel);
    
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
        
        const CGFloat x = floor((currentEvent.frame / framesPerPixel) - start);
        
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

//- (void)updateChapterMarkLayer
//{
//    _markTracking = [NSMutableSet set];
//
//    for (TileView* tv in self.view.subviews) {
//        [self loadMarksForTile:tv];
//    }
//}

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

//- (CATextLayer*)textLayerWithFont:(NSFont*)font color:(NSColor*)color width:(CGFloat)width text:(NSString*)text
//{
//    CATextLayer* textLayer = [CATextLayer layer];
//    textLayer.drawsAsynchronously = YES;
//    textLayer.allowsEdgeAntialiasing = YES;
//    textLayer.wrapped = NO;
//    textLayer.anchorPoint = CGPointMake(0.0,0.0);
//    textLayer.contentsScale = [[NSScreen mainScreen] backingScaleFactor];
//    textLayer.font = font;
//    textLayer.fontSize = []
//    textLayer.string = [self textWithFont:font color:color width:width text:text];
//    textLayer.frame = CGRectMake(0.0, 0.0, width, 1.0f);
//    return textLayer;
//}

/*
- (void)resizeTrackDescription:(CALayer*)background size:(CGSize)size
{
    background.frame = CGRectMake(background.frame.origin.x,
                                  background.frame.origin.y,
                                  size.width,
                                  size.height);

    CATextLayer* titleLayer = background.sublayers[1];
    CATextLayer* artistLayer = background.sublayers[2];

    NSAttributedString* title = [self textWithFont:titleFont
                                             color:titleColor
                                             width:textWidth
                                              text:track.title];
    CGSize titleSize = [title size];
    titleLayer.string = title;
    
    CGSize artistSize = CGSizeZero;
    if (artistLayer != nil) {
        assert(track.artist);
        NSAttributedString* artist = [self textWithFont:artistFont
                                                  color:artistColor
                                                  width:textWidth
                                                   text:track.artist];
        artistLayer.string = artist;
        artistSize = [artist size];
    }

    CGFloat maxWidth = titleSize.width;
    if (artistSize.width > maxWidth) {
        maxWidth = artistSize.width;
    }
    
    CGFloat actualLabelWidth = maxWidth > textWidth ? textWidth : maxWidth;
    //textWidth = maxWidth;
    CGSize backgroundSize = CGSizeMake(imageSize.width + 12.0 + actualLabelWidth, imageSize.height);
    background.bounds = CGRectMake(0.0, 0.0, backgroundSize.width, backgroundSize.height);

    
}
*/

- (CALayer*)trackLayerWithStyle:(NSString*)style hostingLayer:(CALayer*)rootLayer
{
    CAGradientLayer* background = [CAGradientLayer new];
    CGSize imageSize = CGSizeMake(48.0, 48.0);
    CGSize textSize = CGSizeMake(300.0, [[Defaults sharedDefaults] largeFontSize]);
    CGSize backgroundSize = CGSizeMake(imageSize.width + textSize.width, imageSize.height);
    CGFloat artistFontSize = 0;
    CGFloat titleFontSize = 0;
    CGFloat timeFontSize = 0;
    CGFloat radius = 7.0;
    CGFloat border = 2.0;

    if ([style isEqualToString:@"big"]) {
        background.colors = @[(id)[NSColor clearColor].CGColor,
                              (id)[NSColor clearColor].CGColor,
                              (id)[[[Defaults sharedDefaults] regularFakeBeamColor] colorWithAlphaComponent:0.4].CGColor];
        imageSize = CGSizeMake(self.view.bounds.size.height, self.view.bounds.size.height);
        textSize = CGSizeMake(300.0, [[Defaults sharedDefaults] largeFontSize]);
        backgroundSize = CGSizeMake(imageSize.width + textSize.width + 8.0, imageSize.height);
        radius = 7.0;
        titleFontSize = [[Defaults sharedDefaults] largeFontSize];
        artistFontSize = [[Defaults sharedDefaults] normalFontSize];
        timeFontSize = [[Defaults sharedDefaults] smallFontSize];
        border = 2.0;
    } else {
        background.colors = @[(id)[[[Defaults sharedDefaults] regularFakeBeamColor] colorWithAlphaComponent:0.4].CGColor,
                                                                (id)[NSColor clearColor].CGColor,
                              (id)[NSColor clearColor].CGColor];
        imageSize = CGSizeMake(rootLayer.frame.size.height - 4.0, rootLayer.frame.size.height - 4.0);
        textSize = CGSizeMake(300.0, [[Defaults sharedDefaults] smallFontSize]);
        backgroundSize = CGSizeMake(imageSize.width + textSize.width + 8.0, rootLayer.frame.size.height);
        titleFontSize = [[Defaults sharedDefaults] smallFontSize];
        artistFontSize = [[Defaults sharedDefaults] smallFontSize];
        timeFontSize = [[Defaults sharedDefaults] smallFontSize];
        radius = 5.0;
        border = 1.0;
    }

    CIFilter* bloom = [CIFilter filterWithName:@"CIBloom"];
    [bloom setDefaults];
    [bloom setValue: @(4.0f) forKey: @"inputRadius"];
    [bloom setValue: @(1.0f) forKey: @"inputIntensity"];

    background.borderWidth = 0.0;
    background.zPosition = 111.0f;
    background.autoresizingMask = kCALayerWidthSizable | kCALayerHeightSizable;
    background.allowsEdgeAntialiasing = YES;
    background.shouldRasterize = YES;
    background.drawsAsynchronously = YES;
    background.rasterizationScale = rootLayer.contentsScale;
    background.contentsScale = [[NSScreen mainScreen] backingScaleFactor];
    background.masksToBounds = NO;
    background.frame = CGRectMake(0.0f, 0.0f, backgroundSize.width, backgroundSize.height);
    background.cornerRadius = radius;
    background.borderColor = [[Defaults sharedDefaults] lightBeamColor].CGColor;
    background.borderWidth = 0.5f;
    //background.mask = [CAShapeLayer MaskLayerFromRect:background.bounds];

    CALayer* handleLayer = [CALayer layer];
    handleLayer.zPosition = 130.0f;
    handleLayer.autoresizingMask = kCALayerHeightSizable;
    handleLayer.allowsEdgeAntialiasing = YES;
    handleLayer.drawsAsynchronously = YES;
    handleLayer.contentsScale = [[NSScreen mainScreen] backingScaleFactor];
    handleLayer.backgroundColor = _handleColors[NormalHandle].CGColor;
    handleLayer.name = @"WaveMarkDescriptionHandleLayer";
    handleLayer.masksToBounds = NO;
    handleLayer.frame = CGRectMake(0.0f, 0.0f, kMarkerHandleWidth, backgroundSize.height);
    [background addSublayer:handleLayer];
    
    CALayer* imageLayer = [CALayer layer];
    imageLayer.magnificationFilter = kCAFilterLinear;
    imageLayer.minificationFilter = kCAFilterLinear;
    imageLayer.zPosition = 129.0f;
    imageLayer.autoresizingMask = kCALayerNotSizable;
    imageLayer.allowsEdgeAntialiasing = YES;
    imageLayer.shouldRasterize = YES;
    imageLayer.drawsAsynchronously = YES;
    imageLayer.rasterizationScale = rootLayer.contentsScale;
    imageLayer.contentsScale = [[NSScreen mainScreen] backingScaleFactor];
    imageLayer.masksToBounds = YES;
    imageLayer.frame = CGRectMake(kMarkerHandleWidth, 2.0, imageSize.width, imageSize.height);
    imageLayer.name = @"WaveMarkDescriptionImageLayer";
    imageLayer.borderWidth = 1.0;
    imageLayer.borderColor = [NSColor blackColor].CGColor;
    [background addSublayer:imageLayer];

    CAConstraint* minXConstraint = [CAConstraint constraintWithAttribute:kCAConstraintMinX
                                                              relativeTo:imageLayer.name
                                                               attribute:kCAConstraintMaxX
                                                                  offset:4.0];
    CAConstraint* maxXConstraint = [CAConstraint constraintWithAttribute:kCAConstraintWidth
                                                              relativeTo:@"superlayer"
                                                               attribute:kCAConstraintWidth];
    CAConstraint* minYConstraint = [CAConstraint constraintWithAttribute:kCAConstraintMaxY
                                                              relativeTo:@"superlayer"
                                                               attribute:kCAConstraintMaxY
                                                                  offset:0.0];
    CAConstraint* heightConstraint = [CAConstraint constraintWithAttribute:kCAConstraintHeight
                                                                relativeTo:@"superlayer"
                                                                 attribute:kCAConstraintHeight
                                                                     scale:0.3
                                                                    offset:0.0];
    CGFloat x = kMarkerHandleWidth + imageSize.width + 2.0;
    
    CATextLayer* timeLayer = [CATextLayer layer];
    timeLayer.drawsAsynchronously = YES;
    timeLayer.autoresizingMask = kCALayerWidthSizable | kCALayerHeightSizable;
    timeLayer.allowsEdgeAntialiasing = YES;
    timeLayer.wrapped = NO;
    timeLayer.name = @"WaveMarkDescriptionTimeLayer";
    timeLayer.contentsScale = [[NSScreen mainScreen] backingScaleFactor];
    timeLayer.frame = CGRectMake(x, titleFontSize + 4.0 + artistFontSize + 4.0, backgroundSize.width - x, timeFontSize + 4.0);

    [background addSublayer:timeLayer];

    minYConstraint = [CAConstraint constraintWithAttribute:kCAConstraintMaxY
                                                relativeTo:timeLayer.name
                                                 attribute:kCAConstraintMinY];

    CATextLayer* titleLayer = [CATextLayer layer];
    titleLayer.drawsAsynchronously = YES;
    titleLayer.autoresizingMask = kCALayerWidthSizable | kCALayerHeightSizable;
    titleLayer.allowsEdgeAntialiasing = YES;
    titleLayer.allowsFontSubpixelQuantization = YES;
    titleLayer.wrapped = NO;
    titleLayer.contentsScale = [[NSScreen mainScreen] backingScaleFactor];
    titleLayer.frame = CGRectMake(x, artistFontSize + 4.0, backgroundSize.width - x, titleFontSize + 4.0);
    titleLayer.name = @"WaveMarkDescriptionTitleLayer";
    [background addSublayer:titleLayer];

    CATextLayer* artistLayer = [CATextLayer layer];
    artistLayer.drawsAsynchronously = YES;
    artistLayer.autoresizingMask = kCALayerWidthSizable | kCALayerHeightSizable;
    artistLayer.allowsEdgeAntialiasing = YES;
    artistLayer.wrapped = NO;
    artistLayer.name = @"WaveMarkDescriptionArtistLayer";
    artistLayer.contentsScale = [[NSScreen mainScreen] backingScaleFactor];
    artistLayer.frame = CGRectMake(x, 0.0, backgroundSize.width - x, titleFontSize + 4.0);
    artistLayer.constraints = @[ minXConstraint, minYConstraint, maxXConstraint, heightConstraint];
    [background addSublayer:artistLayer];
    
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

    CALayer* fxLayer = [CALayer layer];
    fxLayer.zPosition = 131.0f;
    fxLayer.autoresizingMask = kCALayerNotSizable;
    fxLayer.allowsEdgeAntialiasing = YES;
    //fxLayer.shouldRasterize = YES;
    fxLayer.drawsAsynchronously = YES;
    //fxLayer.backgroundColor = [];
    fxLayer.rasterizationScale = rootLayer.contentsScale;
    fxLayer.contentsScale = [[NSScreen mainScreen] backingScaleFactor];
    //fxLayer.masksToBounds = YES;
    fxLayer.opacity = 0.0f;
    fxLayer.backgroundFilters = @[ bloom ];
    fxLayer.name = @"WaveMarkDescriptionFXLayer";
    fxLayer.frame = CGRectMake(-5.0, 0.0, kMarkerHandleWidth + 10.0, backgroundSize.height);
    fxLayer.mask = [CAShapeLayer MaskLayerFromRect:fxLayer.bounds];
    [background addSublayer:fxLayer];

    CALayer* reflectionHostLayer = [CALayer layer];

    reflectionHostLayer.magnificationFilter = kCAFilterLinear;
    reflectionHostLayer.minificationFilter = kCAFilterLinear;
    reflectionHostLayer.zPosition = 150.0f;
    reflectionHostLayer.allowsEdgeAntialiasing = YES;
    reflectionHostLayer.shouldRasterize = YES;
    reflectionHostLayer.autoresizingMask = kCALayerWidthSizable | kCALayerHeightSizable;
    reflectionHostLayer.opacity = 1.0f;
    reflectionHostLayer.drawsAsynchronously = YES;
    reflectionHostLayer.rasterizationScale = rootLayer.contentsScale;
    reflectionHostLayer.contentsScale = [[NSScreen mainScreen] backingScaleFactor];
    reflectionHostLayer.masksToBounds = YES;
    reflectionHostLayer.frame = background.bounds;
    reflectionHostLayer.name = @"WaveMarkDescriptionReflectionHostLayer";
    [background addSublayer:reflectionHostLayer];
    
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
    reflectionLayer.rasterizationScale = rootLayer.contentsScale;
    reflectionLayer.contentsScale = [[NSScreen mainScreen] backingScaleFactor];
    reflectionLayer.masksToBounds = YES;
    reflectionLayer.frame = CGRectMake(0.0, 0.0, reflectionImage.size.width, rootLayer.frame.size.height);
    reflectionLayer.name = @"WaveMarkDescriptionReflectionLayer";
    [reflectionHostLayer addSublayer:reflectionLayer];

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
    [wv.markLayer.sublayers makeObjectsPerformSelector:@selector(removeFromSuperlayer)];
    _markTracking = [NSMutableSet set];
    [self updateTrackDescriptions];
}

- (void)updateTrackDescriptions
{
    WaveView* wv = (WaveView*)self.view;
    
    if (_frames == 0 || _trackList == nil) {
        return;
    }
    const double framesPerPixel = _frames / self.view.bounds.size.width;
    
    if (self.view.enclosingScrollView != nil) {
        return;
    }

    CGFloat textWidth = 200.0f;
    NSFont* titleFont = [[Defaults sharedDefaults] largeFont];
    NSColor* titleColor = [[Defaults sharedDefaults] lightFakeBeamColor];
    NSFont* timeFont = [[Defaults sharedDefaults] largeFont];
    NSColor* timeColor = [[Defaults sharedDefaults] lightFakeBeamColor];
    NSFont* artistFont = [[Defaults sharedDefaults] normalFont];
    NSColor* artistColor = [[Defaults sharedDefaults] secondaryLabelColor];
    CGSize imageSize = CGSizeMake(48.0, 48.0);
    CGFloat xOffset = 2.0f;
    CGFloat yOffset = 2.0f;
    CGFloat opacity = 1.0f;
    BOOL usesLayout = NO;
    //CGSize imageSize = CGSizeMake(self.view.bounds.size.height / 2.0, self.view.bounds.size.height / 2.0);
    NSRect documentVisibleRect;
    documentVisibleRect = NSMakeRect(0.0, 0.0, self.view.bounds.size.width, self.view.bounds.size.height);
    opacity = 1.0;
    usesLayout = YES;
    imageSize = CGSizeMake(self.view.bounds.size.height - 2, self.view.bounds.size.height - 2);
    timeFont = [[Defaults sharedDefaults] smallFont];
    timeColor = [[Defaults sharedDefaults] regularFakeBeamColor];
    textWidth = 300.0f;
    titleFont = [[Defaults sharedDefaults] smallFont];
    titleColor = [[Defaults sharedDefaults] lightFakeBeamColor];
    artistFont = [[Defaults sharedDefaults] smallFont];
    artistColor = [[Defaults sharedDefaults] secondaryLabelColor];
    xOffset = 2.0f;
    
    const CGFloat xMin = documentVisibleRect.origin.x;
    const CGFloat width = documentVisibleRect.size.width;
    const CGFloat backgroundWidth = textWidth + imageSize.width + 12;
    const unsigned long long frameOffset = floor((xMin - backgroundWidth) * framesPerPixel);
    
    TrackListIterator* iter = nil;
    NSMutableSet* neededTrackFrames = [NSMutableSet set];

    //
    // Go through our tracklist starting from the screen-offset and add all the
    // frame-offsets we find until we reach the end of the screen.
    //
    unsigned long long nextTrackFrame = [_trackList firstTrackFrame:&iter];
    while (nextTrackFrame != ULONG_LONG_MAX) {
        if (frameOffset < nextTrackFrame) {
            const CGFloat x = floor((nextTrackFrame / framesPerPixel) - xMin);
            if (x >= width) {
                break;
            }
            [neededTrackFrames addObject:[NSNumber numberWithUnsignedLongLong:nextTrackFrame]];
        }
        nextTrackFrame = [_trackList nextTrackFrame:iter];
    };

    NSArray<NSNumber*>* trackFrames = nil;
    if (usesLayout) {
        trackFrames = [[neededTrackFrames allObjects] sortedArrayUsingSelector:@selector(compare:)];
    }

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
            background = [self trackLayerWithStyle:@"small" hostingLayer:wv.markLayer];
            [wv.markLayer addSublayer:background];
        }

        // Tag the background layer with the track frame offset.
        [background setValue:neededFrame forKey:kFrameOffsetLayerKey];
        
        //
        // Initialize the display elements with track data.
        //
        assert(background.sublayers.count == 7);
        CALayer* imageLayer = background.sublayers[1];
        CATextLayer* timeLayer = background.sublayers[2];
        CATextLayer* titleLayer = background.sublayers[3];
        CATextLayer* artistLayer = background.sublayers[4];
        
        background.name = [neededFrame stringValue];

        IdentifiedTrack* track = [_trackList trackAtFrame:[neededFrame unsignedLongLongValue]];

        NSImage* image = nil;
        if (track.artwork != nil) {
            image = [NSImage resizedImage:track.artwork
                                     size:imageLayer.frame.size];
        } else {
            image = [NSImage resizedImage:[NSImage imageNamed:@"UnknownSong"]
                                     size:imageLayer.frame.size];
            if (track.imageURL != nil) {
                // We can try to resolve the artwork image from the URL.
                [self resolveImageForURL:track.imageURL callback:^(NSImage* image){
                    track.artwork = image;
                    imageLayer.contents = image;
                }];
            }
        }

        imageLayer.contents = image;
        
        if (usesLayout) {
            assert(track.title);
            NSAttributedString* title = [self textWithFont:titleFont
                                                     color:titleColor
                                                      text:track.title];
            titleLayer.string = title;
            
            assert(track.artist);
            NSAttributedString* artist = [self textWithFont:artistFont
                                                      color:artistColor
                                                       text:track.artist];
            artistLayer.string = artist;
            
            NSAttributedString* time = [self textWithFont:timeFont
                                                    color:timeColor
                                                     text:[_delegate stringFromFrame:[track.frame unsignedLongLongValue]]];
            timeLayer.string = time;
        } else {
            assert(track.title);
            NSAttributedString* title = [self textWithFont:titleFont
                                                     color:titleColor
                                                     width:textWidth
                                                      text:track.title];
            CGSize titleSize = [title size];
            titleLayer.string = title;
            
            assert(track.artist);
            NSAttributedString* artist = [self textWithFont:artistFont
                                                      color:artistColor
                                                      width:textWidth
                                                       text:track.artist];
            CGSize artistSize = [artist size];
            artistLayer.string = artist;

            NSAttributedString* time = [self textWithFont:timeFont
                                                    color:timeColor
                                                     text:[_delegate stringFromFrame:[track.frame unsignedLongLongValue]]];
            CGSize timeSize = [time size];
            timeLayer.string = time;
           
            CGFloat maxWidth = titleSize.width;
            if (artistSize.width > maxWidth) {
                maxWidth = artistSize.width;
            }
            if (timeSize.width > maxWidth) {
                maxWidth = timeSize.width;
            }

            CGFloat actualLabelWidth = maxWidth > textWidth ? maxWidth : textWidth;
            CGSize backgroundSize = CGSizeMake(imageSize.width + 12.0 + actualLabelWidth, imageSize.height);
            background.bounds = CGRectMake(0.0, 0.0, backgroundSize.width, backgroundSize.height);
        }
    }

    //
    // Position all tiles -- we need to do this continuously to fake scrolling.
    //
    if (usesLayout && trackFrames.count > 0) {
        for (size_t i = 0; i < trackFrames.count; i++) {
            NSNumber* next = nil;
            NSNumber* current = trackFrames[i];
            if (trackFrames.count > 1 && i < trackFrames.count - 1) {
                next = trackFrames[i + 1];
            }

            BOOL active = current == _currentTrack.frame;

            CGFloat x = ((float)[current unsignedLongLongValue] / framesPerPixel) - xMin;
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

            CALayer* fxLayer = currentLayer.sublayers[5];
            CALayer* handleLayer = currentLayer.sublayers[0];
            fxLayer.opacity = active ? 1.0f : 0.0f;
            handleLayer.backgroundColor = active ? _handleColors[ActiveHandle].CGColor : _handleColors[NormalHandle].CGColor;
            if (active) {
                _activeLayer = currentLayer;
            }
        }
        [wv.markLayer setNeedsLayout];
        [wv.markLayer layoutIfNeeded];

//        for (NSNumber* frame in trackFrames) {
//            CALayer* layer = [self sublayerForFrame:frame layers:wv.markLayer.sublayers];
//            layer.mask = [CAShapeLayer MaskLayerFromRect:layer.bounds];
//        }
    } else {
        for (CALayer* currentLayer in wv.markLayer.sublayers) {
            NSNumber* frameOffset = [currentLayer valueForKey:kFrameOffsetLayerKey];
            CGFloat x = ((float)[frameOffset unsignedLongLongValue] / framesPerPixel) - xMin;
            currentLayer.position = CGPointMake(x + xOffset, yOffset);
        }
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
    CALayer* fxLayer = background.sublayers[5];
    CALayer* handleLayer = background.sublayers[0];
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

- (void)dragMark:(NSPoint)location
{
    assert(_draggingLayer);

    const double framesPerPixel = _frames / self.view.bounds.size.width;
    unsigned long long newFrame = (location.x - (kMarkerHandleWidth / 2.0)) * framesPerPixel;
    CGFloat x = newFrame / framesPerPixel;

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
    CATextLayer* timeLayer = _draggingLayer.sublayers[2];

    NSFont* timeFont = [[Defaults sharedDefaults] smallFont];
    NSColor* timeColor = [[Defaults sharedDefaults] regularFakeBeamColor];

    NSAttributedString* time = [self textWithFont:timeFont
                                            color:timeColor
                                             text:[_delegate stringFromFrame:newFrame]];
    timeLayer.string = time;
    
    [wv.markLayer setNeedsLayout];
    [wv.markLayer layoutIfNeeded];

//    _previousLayer.mask = [CAShapeLayer MaskLayerFromRect:_previousLayer.bounds];
//    _draggingLayer.mask = [CAShapeLayer MaskLayerFromRect:_draggingLayer.bounds];

    [CATransaction commit];
}

- (void)duckImageOn:(CALayer*)background forwards:(BOOL)forwards
{
    CALayer* image = background.sublayers[1];
    CATextLayer* time = background.sublayers[2];
    CATextLayer* title = background.sublayers[3];
    CATextLayer* artist = background.sublayers[4];
    
    CGFloat x = forwards ? kMarkerHandleWidth + 2.0 : image.frame.size.width + kMarkerHandleWidth + 2.0;
    CGFloat opacity = forwards ? 0.0f : 1.0f;

    image.opacity = opacity;

    time.frame = CGRectMake(x, time.frame.origin.y, background.bounds.size.width - x, time.frame.size.height);
    title.frame = CGRectMake(x, title.frame.origin.y, background.bounds.size.width - x, title.frame.size.height);
    title.opacity = opacity;
    artist.frame = CGRectMake(x, artist.frame.origin.y, background.bounds.size.width - x, artist.frame.size.height);
    artist.opacity = opacity;
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

    assert(background.sublayers.count > 5);
    CALayer* hostLayer = background.sublayers[6];
    assert(hostLayer.sublayers.count > 0);
    CALayer* layer = hostLayer.sublayers[0];

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

- (void)cursorUpdate:(NSEvent*)event
{
    // We need to make sure nothing changes the cursor in our view - thus we override the
    // handler but do not pass down the event. That way our cursor can be controlled
    // exclusively during the mouseMove handler.
    //
    // We cant use this handler as it appears to get called only sporadically, depending
    // on other screen activities -- entirely enigmatic but the result is only moveMove gets
    // reliable called and that is where we do our cursor updates.
    //
    // Without this override, some other stuff trashes our cursor updates -- i have no idea
    // what that was.
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
        handleLayer = markerBackgroundLayer.sublayers[0];
        fxLayer = markerBackgroundLayer.sublayers[5];
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

    [super mouseExited:event];
}

- (void)mouseDown:(NSEvent*)event
{
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
    
    const double framesPerPixel = _frames / self.view.bounds.size.width;
    unsigned long long oldFrame = [_trackingMarker.frame unsignedLongLongValue];
    unsigned long long newFrame = (location.x - (kMarkerHandleWidth / 2.0)) * framesPerPixel;

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

    if (!_tracking || _trackingMarker == nil || _draggingLayer == nil) {
        unsigned long long newFrame = (_visualSample.sample.frames * location.x ) / self.view.frame.size.width;
        [_delegate seekToFrame:newFrame];
    }
    if (_draggingLayer != nil) {
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
