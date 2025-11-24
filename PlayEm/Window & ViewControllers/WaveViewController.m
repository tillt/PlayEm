//
//  WaveViewController.m
//  PlayEm
//  Created by Till Toenshoff on 11/9/25.
//  Copyright © 2025 Till Toenshoff. All rights reserved.
//

#import "WaveViewController.h"
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

@interface WaveViewController()

@property (nonatomic, assign) BOOL userMomentum;
@property (nonatomic, assign) CGFloat head;
@property (nonatomic, strong) NSMutableArray* reusableViews;
@property (nonatomic, strong) NSMutableArray<CALayer*>* reusableLayers;
@property (strong, nonatomic) dispatch_queue_t imageQueue;

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
        
        dispatch_queue_attr_t attr = dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL, QOS_CLASS_USER_INITIATED, 0);
        _imageQueue = dispatch_queue_create("PlayEm.WaveViewImageQueue", attr);

        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(willStartLiveScroll:)
                                                     name:NSScrollViewWillStartLiveScrollNotification
                                                   object:nil];
        [[NSNotificationCenter defaultCenter]
         addObserver:self
         selector:@selector(didLiveScroll:)
         name:NSScrollViewDidLiveScrollNotification
         object:nil];
        [[NSNotificationCenter defaultCenter]
         addObserver:self
         selector:@selector(didEndLiveScroll:)
         name:NSScrollViewDidEndLiveScrollNotification
         object:nil];
    }
    return self;
}

- (void)loadView
{
    [super loadView];
    
    self.view = [[WaveView alloc] initWithFrame:NSZeroRect];
    self.view.autoresizingMask = NSViewNotSizable;
    self.view.translatesAutoresizingMaskIntoConstraints = YES;
}

- (void)setCurrentFrame:(unsigned long long)frame
{
    if (_frames == 0LL) {
        return;
    }
    _currentFrame = frame;
    [self updateScrollingState];
    [self updateTiles];
}

- (void)resetTracking
{
    NSTrackingArea *trackingArea = [[NSTrackingArea alloc] initWithRect:[self.view bounds]
        options: (NSTrackingMouseEnteredAndExited | NSTrackingMouseMoved |  NSTrackingActiveAlways | NSTrackingInVisibleRect)
        owner:self userInfo:nil];
    [self.view addTrackingArea:trackingArea];
}

- (void)setFrames:(unsigned long long)frames
{
    _frames = frames;
    _currentFrame = 0;
    [self updateScrollingState];
    [self updateTiles];
    [self updateMarkLayer];
}

- (void)setVisualSample:(VisualSample *)visualSample
{
    if (_visualSample == visualSample) {
        return;
    }
    _visualSample = visualSample;
    [self invalidateTiles];
    [self invalidateBeats];
}

- (void)loadMarkLayer:(CALayer*)rootLayer
{
    [rootLayer.sublayers makeObjectsPerformSelector:@selector(removeFromSuperlayer)];
    [rootLayer setNeedsDisplay];
    
    if (_frames == 0 || self.view == nil || _trackList == nil || rootLayer.superlayer.frame.origin.x < 0) {
        return;
    }
    
    const double framesPerPixel = _frames / self.view.frame.size.width;
    
    const CGFloat start = rootLayer.superlayer.frame.origin.x;
    const CGFloat width = rootLayer.frame.size.width;
    
    const unsigned long long frameOffset = floor(start * framesPerPixel);
    
    TrackListIterator* iter = nil;
    unsigned long long nextTrackFrame = [_trackList firstTrackFrame:&iter];
    
    while (nextTrackFrame != ULONG_LONG_MAX) {
        // A mark before our tile start frame needs to get skipped.
        if (frameOffset < nextTrackFrame) {
            const CGFloat x = floor((nextTrackFrame / framesPerPixel) - start);
            // We need to stop drawing when we reached the total width of our layer.
            if (x >= width) {
                break;
            }
            CALayer* markLayer = [CALayer layer];
            markLayer.drawsAsynchronously = YES;
            markLayer.backgroundColor = [_markerColor CGColor];
            markLayer.frame = CGRectMake(x, 0, _markerWidth, self.view.frame.size.height);
            [rootLayer addSublayer:markLayer];
        }
        
        nextTrackFrame = [_trackList nextTrackFrame:iter];
    };
}

- (void)loadBeatLayer:(CALayer*)rootLayer
{
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
        NSLog(@"beat buffer from frame %lld (screen %f) not yet available", frameOffset, start);
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
        
        CALayer* beatLayer = [CALayer layer];
        beatLayer.drawsAsynchronously = YES;
        beatLayer.backgroundColor = color;
        beatLayer.frame = CGRectMake(x, 0, width, self.view.frame.size.height);
        [rootLayer addSublayer:beatLayer];
    };
}

- (void)setTrackList:(TrackList *)trackList
{
    if (trackList  == _trackList) {
        return;
    }
    _trackList = trackList;
    assert(self.view.frame.size.width > 0);
    
    [self invalidateMarks];
    [self updateMarkLayer];
}

- (void)setBeatSample:(BeatTrackedSample *)beatSample
{
    if (beatSample == _beatSample) {
        return;
    }
    _beatSample = beatSample;
    assert(self.view.frame.size.width > 0);
    
    [self invalidateBeats];
}

- (void)updateHeadPositionTransaction
{
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    self.head = [self calcHead];
    [self updateMarkLayer];
    [CATransaction commit];
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

    [self invalidateTiles];
    [self invalidateBeats];
    [self invalidateMarks];
    [self updateHeadPositionTransaction];
}

- (void)invalidateMarks
{
    for (TileView* tv in self.view.subviews) {
        [self loadMarkLayer:tv.markLayer];
    }
}

- (void)invalidateBeats
{
    for (TileView* tv in self.view.subviews) {
        [self loadBeatLayer:tv.beatLayer];
    }
}

- (void)invalidateTiles
{
    for (TileView* tv in self.view.subviews) {
        [tv.waveLayer setNeedsDisplay];
    }
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

- (CATextLayer*)textLayerWithFont:(NSFont*)font color:(NSColor*)color width:(CGFloat)width text:(NSString*)text
{
    CATextLayer* textLayer = [CATextLayer layer];
    textLayer.drawsAsynchronously = YES;
    textLayer.allowsEdgeAntialiasing = YES;
    textLayer.wrapped = NO;
    textLayer.anchorPoint = CGPointMake(0.0,0.0);
    textLayer.contentsScale = [[NSScreen mainScreen] backingScaleFactor];
    textLayer.string = [self textWithFont:font color:color width:width text:text];
    textLayer.frame = CGRectMake(0.0, 0.0, width, 1.0f);
    return textLayer;
}

- (CALayer*)trackLayerWithStyle:(NSString*)style hostingLayer:(CALayer*)rootLayer
{
    CALayer* background = [CALayer new];
    CGSize imageSize = CGSizeMake(48.0, 48.0);
    CGSize textSize = CGSizeMake(300.0, [[Defaults sharedDefaults] largeFontSize]);
    CGSize backgroundSize = CGSizeMake(imageSize.width + textSize.width, imageSize.height);
    CGFloat artistFontSize = 0;
    CGFloat titleFontSize = 0;
    CGFloat radius = 7.0;
    CGFloat border = 2.0;
    if ([style isEqualToString:@"big"]) {
        imageSize = CGSizeMake(48.0, 48.0);
        textSize = CGSizeMake(300.0, [[Defaults sharedDefaults] largeFontSize]);
        backgroundSize = CGSizeMake(imageSize.width + textSize.width + 8.0, imageSize.height);
        artistFontSize = [[Defaults sharedDefaults] normalFontSize];
        radius = 7.0;
        titleFontSize = [[Defaults sharedDefaults] largeFontSize];
        border = 2.0;
    } else {
        imageSize = CGSizeMake(24.0, 24.0);
        textSize = CGSizeMake(300.0, [[Defaults sharedDefaults] smallFontSize]);
        backgroundSize = CGSizeMake(imageSize.width + textSize.width + 8.0, imageSize.height);
        titleFontSize = [[Defaults sharedDefaults] smallFontSize];
        artistFontSize = 0;
        radius = 5.0;
        border = 1.0;
    }
    background.backgroundColor = [[Defaults sharedDefaults] backColor].CGColor;
    background.zPosition = 100.0f;
    background.autoresizingMask = kCALayerWidthSizable | kCALayerHeightSizable;
    background.allowsEdgeAntialiasing = YES;
    background.shouldRasterize = YES;
    background.drawsAsynchronously = YES;
    background.rasterizationScale = rootLayer.contentsScale;
    background.contentsScale = [[NSScreen mainScreen] backingScaleFactor];
    background.masksToBounds = YES;
    background.frame = CGRectMake(0, 0.0, backgroundSize.width, backgroundSize.height);
    background.anchorPoint = CGPointZero;
    background.cornerRadius = radius;
    background.borderWidth = 2.0;
    background.borderColor = [[Defaults sharedDefaults] regularFakeBeamColor].CGColor;

    CALayer* imageLayer = [CALayer layer];
    imageLayer.magnificationFilter = kCAFilterLinear;
    imageLayer.minificationFilter = kCAFilterLinear;
    imageLayer.zPosition = 100.0f;
    imageLayer.autoresizingMask = kCALayerNotSizable;
    imageLayer.allowsEdgeAntialiasing = YES;
    imageLayer.shouldRasterize = YES;
    imageLayer.drawsAsynchronously = YES;
    imageLayer.rasterizationScale = rootLayer.contentsScale;
    imageLayer.contentsScale = [[NSScreen mainScreen] backingScaleFactor];
    imageLayer.masksToBounds = YES;
    imageLayer.frame = CGRectMake(0.0, 0.0, imageSize.width, imageSize.height);
    imageLayer.cornerRadius = radius;
    imageLayer.borderWidth = 2.0;
    imageLayer.borderColor = [NSColor blackColor].CGColor;
    [background addSublayer:imageLayer];
    
    CATextLayer* titleLayer = [CATextLayer layer];
    titleLayer.drawsAsynchronously = YES;
    titleLayer.allowsEdgeAntialiasing = YES;
    titleLayer.wrapped = NO;
    titleLayer.anchorPoint = CGPointMake(0.0,0.0);
    titleLayer.contentsScale = [[NSScreen mainScreen] backingScaleFactor];
    titleLayer.frame = CGRectMake(imageSize.width + 4.0, 4.0, textSize.width, titleFontSize + 4.0);
    [background addSublayer:titleLayer];

    if (artistFontSize > 0) {
        CATextLayer* artistLayer = [CATextLayer layer];
        artistLayer.drawsAsynchronously = YES;
        artistLayer.allowsEdgeAntialiasing = YES;
        artistLayer.wrapped = NO;
        artistLayer.anchorPoint = CGPointMake(0.0,0.0);
        artistLayer.contentsScale = [[NSScreen mainScreen] backingScaleFactor];
        artistLayer.frame = CGRectMake(imageSize.width + 4.0, titleFontSize + 8.0, textSize.width, artistFontSize + 4.0);
        [background addSublayer:artistLayer];
    }

    return background;
}

- (void)mouseEntered:(NSEvent*)event
{
    if (self.view.enclosingScrollView != nil) {
        return;
    }
}

- (void)mouseExited:(NSEvent *)event
{
    if (self.view.enclosingScrollView != nil) {
        return;
    }
    WaveView* wv = (WaveView*)self.view;
    for (CALayer* background in wv.markLayer.sublayers) {
        background.opacity = 0.0f;
    }
}

- (void)mouseMoved:(NSEvent*)event
{
    if (self.view.enclosingScrollView != nil) {
        return;
    }
    NSPoint mouseScreen = [NSEvent mouseLocation];
    NSPoint mouseWindow = [self.view.window convertPointFromScreen:mouseScreen];
    NSPoint mouseView = [self.view convertPoint:mouseWindow fromView:nil];
    
    WaveView* wv = (WaveView*)self.view;
    for (CALayer* background in wv.markLayer.sublayers) {
        if (NSPointInRect(mouseView, background.frame)) {
            background.opacity = 1.0f;
        } else {
            background.opacity = 0.0f;
        }
    }
}

- (void)updateMarkLayer
{
    NSString* style = @"big";
    
    NSString* kFrameOffsetLayerKey = @"frameOffset";
    WaveView* wv = (WaveView*)self.view;
    
    if (_frames == 0 || _trackList == nil) {
        return;
    }
    const double framesPerPixel = _frames / self.view.bounds.size.width;


    CGFloat textWidth = 200.0f;
    NSFont* titleFont = [[Defaults sharedDefaults] largeFont];
    NSColor* titleColor = [[Defaults sharedDefaults] lightFakeBeamColor];
    NSFont* artistFont = [[Defaults sharedDefaults] normalFont];
    NSColor* artistColor = [[Defaults sharedDefaults] secondaryLabelColor];
    CGSize imageSize = CGSizeMake(48.0, 48.0);
    CGFloat xOffset = 2.0f;
    CGFloat yOffset = 2.0f;
    CGFloat opacity = 1.0f;
    //CGSize imageSize = CGSizeMake(self.view.bounds.size.height / 2.0, self.view.bounds.size.height / 2.0);
    NSRect documentVisibleRect;
    if (self.view.enclosingScrollView != nil) {
        documentVisibleRect = self.view.enclosingScrollView.documentVisibleRect;
        style = @"big";
        opacity = 1.0;
        textWidth = 200.0f;
        imageSize = CGSizeMake(48.0, 48.0);
        titleFont = [[Defaults sharedDefaults] largeFont];
        titleColor = [[Defaults sharedDefaults] lightFakeBeamColor];
        artistFont = [[Defaults sharedDefaults] normalFont];
        artistColor = [[Defaults sharedDefaults] secondaryLabelColor];
        xOffset = 0.0f;
        //yOffset = self.view.frame.size.height - (imageSize.height + 4.0);
        yOffset = 0.0;
    } else {
        documentVisibleRect = NSMakeRect(0.0, 0.0, self.view.bounds.size.width, self.view.bounds.size.height);
        style = @"small";
        opacity = 0.0;
        imageSize = CGSizeMake(24.0, 24.0);
        textWidth = 300.0f;
        titleFont = [[Defaults sharedDefaults] smallFont];
        titleColor = [[Defaults sharedDefaults] lightFakeBeamColor];
        artistFont = [[Defaults sharedDefaults] normalFont];
        artistColor = [[Defaults sharedDefaults] secondaryLabelColor];
        xOffset = 2.0f;
        yOffset = 2.0f;
    }
    
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

    //
    // See if we already have sublayers that cover these needed track frame offsets.
    //
    NSArray<CALayer*>* layers = [[wv.markLayer sublayers] copy];
    for (CALayer* layer in layers) {
        NSNumber* keyNumber = [layer valueForKey:kFrameOffsetLayerKey];
        // If we don't need this one any more.
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
        CALayer* background = [self.reusableLayers lastObject];
        [_reusableLayers removeLastObject];

        CALayer* imageLayer = nil;
        CATextLayer* titleLayer = nil;
        CATextLayer* artistLayer = nil;
        
        // Create one if we did not find a reusable one.
        if (nil == background) {
            background = [self trackLayerWithStyle:style hostingLayer:wv.markLayer];
            [wv.markLayer addSublayer:background];
        }

        imageLayer = background.sublayers.count > 0 ? background.sublayers[0] : nil;
        titleLayer = background.sublayers.count > 1 ? background.sublayers[1] : nil;
        artistLayer = background.sublayers.count > 2 ? background.sublayers[2] : nil;

        [background setValue:neededFrame forKey:kFrameOffsetLayerKey];

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
        
        assert(track.title);
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
        background.opacity = opacity;
    }

    //
    // Position all tiles -- we need to do this continuously to fake scrolling.
    //
    for (CALayer* layer in wv.markLayer.sublayers) {
        NSNumber* frameOffset = [layer valueForKey:kFrameOffsetLayerKey];
        CGFloat x = ((float)[frameOffset unsignedLongLongValue] / framesPerPixel) - xMin;
        layer.position = CGPointMake(x + xOffset, yOffset);
    }
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

- (void)updateTiles
{
    NSSize tileSize = { _tileWidth, self.view.bounds.size.height };
    
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
    
    //assert(self.documentView != nil);
    
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
        
//        [view.layer setNeedsDisplay];
        [view.waveLayer setNeedsDisplay];

        [self loadBeatLayer:view.beatLayer];
        [self loadMarkLayer:view.markLayer];
    }
}

#pragma mark - Scroll View Notifications

- (void)updateScrollingState
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
        [self updateMarkLayer];
    }
    
    self.head = head;

    [CATransaction commit];
}

- (void)rightMouseDown:(NSEvent*)event
{
    _followTime = YES;

    [self updateScrollingState];
    [self updateTiles];
}

- (void)willStartLiveScroll:(NSNotification*)notification
{
    _userMomentum = YES;
    _followTime = NO;

    [self updateScrollingState];
    [self updateTiles];
}

- (void)didLiveScroll:(NSNotification*)notification
{
    [self updateScrollingState];
    [self updateTiles];
}

- (void)didEndLiveScroll:(NSNotification*)notification
{
    _userMomentum = NO;

    [self updateScrollingState];
    [self updateTiles];
}

@end
