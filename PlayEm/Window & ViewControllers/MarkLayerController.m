//
//  MarkLayerController.m
//  PlayEm
//
//  Created by Till Toenshoff on 11/9/25.
//  Copyright © 2025 Till Toenshoff. All rights reserved.
//

#import "MarkLayerController.h"
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

@interface MarkLayerController()

@property (nonatomic, assign) BOOL followTime;
@property (nonatomic, assign) BOOL userMomentum;
@property (nonatomic, assign) CGFloat head;
@property (nonatomic, strong) NSMutableArray* reusableViews;

@end

@implementation MarkLayerController
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
        
        _tileWidth = 256.0;
        
        [[NSNotificationCenter defaultCenter]
           addObserver:self
              selector:@selector(willStartLiveScroll:)
                  name:NSScrollViewWillStartLiveScrollNotification
                object:self];
        [[NSNotificationCenter defaultCenter]
           addObserver:self
              selector:@selector(didLiveScroll:)
                  name:NSScrollViewDidLiveScrollNotification
                object:self];
        [[NSNotificationCenter defaultCenter]
           addObserver:self
              selector:@selector(didEndLiveScroll:)
                  name:NSScrollViewDidEndLiveScrollNotification
                object:self];
    }
    return self;
}

- (NSMutableArray*)reusableViews
{
    if (_reusableViews == nil) {
        _reusableViews = [NSMutableArray array];
    }
    return _reusableViews;
}


- (void)loadView
{
    [super loadView];

    self.view = [[WaveView alloc] initWithFrame:NSZeroRect];
    self.view.autoresizingMask = NSViewNotSizable;
    self.view.translatesAutoresizingMaskIntoConstraints = YES;
}

/**
 Asserts that the playhead is properly positioned horizontally using a core animation
 transaction.
 
 Use with great care and avoid nested animation transactions - those are very expensive.
 */

- (void)setCurrentFrame:(unsigned long long)frame
{
    if (_currentFrame == frame) {
        return;
    }
    if (_frames == 0LL) {
        return;
    }
    _currentFrame = frame;
    [self updateTiles];
    [self updateScrollingState];
}

- (void)setFrames:(unsigned long long)frames
{
    if (_frames == frames) {
        return;
    }
    _frames = frames;
    self.currentFrame = 0;
    [self invalidateTiles];
    [self invalidateBeats];
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
    [CATransaction commit];
}

- (void)setHead:(CGFloat)head
{
    if (_head == head) {
        return;
    }
    _head = head;
    
    WaveView* wv = (WaveView*)self.view;
    [wv setHead:head];

    WaveScrollView* sv = (WaveScrollView*)self.view.enclosingScrollView;
    if (sv != nil) {
        [sv setHead:head];
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

- (void)userInitiatedScrolling
{
    _userMomentum = YES;
    _followTime = NO;
}

- (void)userEndsScrolling
{
    _userMomentum = NO;
}

- (void)rightMouseDown:(NSEvent*)event
{
    _followTime = YES;
    [self updateScrollingState];
}

- (CGFloat)calcHead
{
    if (_frames == 0LL) {
        return 0.0;
    }
    return floor(( _currentFrame * self.view.bounds.size.width) / _frames);
}

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
    }

    self.head = head;

    [CATransaction commit];
}

- (void)resize
{
    [self.view performSelector:@selector(resize)];

    [self invalidateTiles];
    [self invalidateBeats];
    [self invalidateMarks];
    [self updateHeadPositionTransaction];
}

- (void)willStartLiveScroll:(NSNotification*)notification
{
    [self updateHeadPositionTransaction];
}

- (void)didLiveScroll:(NSNotification*)notification
{
    [self updateHeadPositionTransaction];
}

- (void)didEndLiveScroll:(NSNotification*)notification
{
    [self updateHeadPositionTransaction];
}

//- (void)updateTiles
//{
//    [self.view.subviews makeObjectsPerformSelector:@selector(removeFromSuperview)];
//    
//    NSSize tileSize = { _tileWidth, self.view.bounds.size.height };
//    NSRect documentVisibleRect = NSMakeRect(0.0, 0.0, self.view.bounds.size.width, self.view.bounds.size.height);
//    const CGFloat xMin = floor(NSMinX(documentVisibleRect) / tileSize.width) * tileSize.width;
//    const CGFloat xMax = xMin + (floor((NSMaxX(documentVisibleRect) - xMin) / tileSize.width) * tileSize.width);
//    const CGFloat yMin = floor(NSMinY(documentVisibleRect) / tileSize.height) * tileSize.height;
//    const CGFloat yMax = ceil((NSMaxY(documentVisibleRect) - yMin) / tileSize.height) * tileSize.height;
//    
//    for (CGFloat x = xMin; x < xMax; x += tileSize.width) {
//        for (CGFloat y = yMin; y < yMax; y += tileSize.height) {
//            NSRect rect = NSMakeRect(x, y, tileSize.width, tileSize.height);
//            TileView* v = [[TileView alloc] initWithFrame:rect waveLayerDelegate:self];
//            v.tileTag = x / tileSize.width;
//            [self.view addSubview:v];
//            [self updateTileView:v];
//        }
//    }
//}


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

- (void)updateTiles
{
    NSSize tileSize = { _tileWidth, self.view.bounds.size.height };
    
    NSRect documentVisibleRect = NSMakeRect(0.0, 0.0, self.view.bounds.size.width, self.view.bounds.size.height);
    if (self.view.enclosingScrollView != nil) {
        documentVisibleRect = self.view.enclosingScrollView.documentVisibleRect;
        // Lie to get the last tile invisilbe, always. That way we wont regularly
        // see updates of the right most tile when the scrolling follows playback.
        documentVisibleRect.size.width += tileSize.width;
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
            view = [[TileView alloc] initWithFrame:NSZeroRect
                                 waveLayerDelegate:self];
        }
        
        // Place it and install it.
        view.frame = [neededFrame rectValue];
        [self.view addSubview:view];
      
        [self loadBeatLayer:view.beatLayer];
        [self loadMarkLayer:view.markLayer];
    }
}
@end
