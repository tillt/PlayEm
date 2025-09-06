//
//  TiledScrollView.m
//  PlayEm
//
//  Created by Till Toenshoff on 05.12.20.
//  Copyright © 2020 Till Toenshoff. All rights reserved.
//

#import <QuartzCore/QuartzCore.h>

#import "TiledScrollView.h"
#import "TileView.h"
#import "Scroller.h"
#import "Defaults.h"

@interface TiledScrollView () // Private
@property (nonatomic, strong) NSMutableArray* reusableViews;
- (void)updateTiles;
@end

@implementation TiledScrollView

- (nonnull instancetype)initWithFrame:(CGRect)frameRect
{
    self = [super initWithFrame:frameRect];
    if (self) {
        self.automaticallyAdjustsContentInsets = NO;
        self.contentInsets = NSEdgeInsetsMake(0.0, 0.0, 0.0, 0.0);
        self.backgroundColor = [[Defaults sharedDefaults] backColor];

        self.allowsMagnification = NO;
        
        Scroller* scroller = [Scroller new];
        scroller.color = [NSColor redColor];
        self.horizontalScroller = scroller;
        
        self.tileSize = NSMakeSize(frameRect.size.width, 20.0f);
        self.horizontal = NO;

        self.wantsLayer = YES;
        self.layer = [self makeBackingLayer];
        self.layerContentsRedrawPolicy = NSViewLayerContentsRedrawOnSetNeedsDisplay;
        self.layer.masksToBounds = NO;
        self.layer.backgroundColor = [self.backgroundColor CGColor];

        [[NSNotificationCenter defaultCenter]
           addObserver:self
              selector:@selector(WillStartLiveScroll:)
                  name:NSScrollViewWillStartLiveScrollNotification
                object:self];
        [[NSNotificationCenter defaultCenter]
           addObserver:self
              selector:@selector(DidLiveScroll:)
                  name:NSScrollViewDidLiveScrollNotification
                object:self];
        [[NSNotificationCenter defaultCenter]
           addObserver:self
              selector:@selector(DidEndLiveScroll:)
                  name:NSScrollViewDidEndLiveScrollNotification
                object:self];
    }
    return self;
}

- (void)viewDidMoveToSuperview
{
    [super viewDidMoveToSuperview];

    [self updateTiles];
}

- (void)WillStartLiveScroll:(NSNotification*)notification
{
}

- (void)DidLiveScroll:(NSNotification*)notification
{
}

- (void)DidEndLiveScroll:(NSNotification*)notification
{
}

- (NSMutableArray*)reusableViews
{
    if (_reusableViews == nil) {
        _reusableViews = [NSMutableArray array];
    }
    return _reusableViews;
}

- (void)reflectScrolledClipView:(NSClipView *)view
{
    [super reflectScrolledClipView:view];
    [self updateTiles];
}

- (TileView*)createTile
{
    TileView* view = [[TileView alloc] initWithFrame:NSZeroRect];
    view.layer.delegate = _layerDelegate;
    return view;
}

/**
 Should get called whenever the visible tiles could possibly be outdated.
 */
- (void)updateTiles
{
    NSMutableArray* reusableViews = self.reusableViews;
    NSRect documentVisibleRect = self.documentVisibleRect;

    // Lie to get the last tile invisilbe, always. That way we wont regularly
    // see updates of the right most tile when the scrolling follows playback.
    if (_horizontal) {
        documentVisibleRect.size.width += _tileSize.width;
    } else {
        documentVisibleRect.size.height += _tileSize.height;
    }

    const CGFloat xMin = floor(NSMinX(documentVisibleRect) / _tileSize.width) * _tileSize.width;
    const CGFloat xMax = xMin + (ceil((NSMaxX(documentVisibleRect) - xMin) / _tileSize.width) * _tileSize.width);
    const CGFloat yMin = floor(NSMinY(documentVisibleRect) / _tileSize.height) * _tileSize.height;
    //const CGFloat yMax = ceil((NSMaxY(documentVisibleRect) - yMin) / _tileSize.height) * _tileSize.height;
    const CGFloat yMax = yMin + (ceil((NSMaxY(documentVisibleRect) - yMin) / _tileSize.height) * _tileSize.height);

    // Figure out the tile frames we would need to get full coverage and add them to
    // the to-do list.
    NSMutableSet* neededTileFrames = [NSMutableSet set];
    for (CGFloat x = xMin; x < xMax; x += _tileSize.width) {
        for (CGFloat y = yMin; y < yMax; y += _tileSize.height) {
            NSRect rect = NSMakeRect(x, y, _tileSize.width, _tileSize.height);
            [neededTileFrames addObject:[NSValue valueWithRect:rect]];
        }
    }
    
    assert(self.documentView != nil);

    // See if we already have subviews that cover these needed frames.
    for (NSView* subview in [[self.documentView subviews] copy]) {
        NSValue* frameRectVal = [NSValue valueWithRect:subview.frame];
        // If we don't need this one any more.
        if (![neededTileFrames containsObject:frameRectVal]) {
            // Then recycle it.
            [reusableViews addObject:subview];
            [subview removeFromSuperview];
        } else {
            // Take this frame rect off the to-do list.
            [neededTileFrames removeObject:frameRectVal];
        }
    }

    // Add needed tiles from the to-do list.
    for (NSValue* neededFrame in neededTileFrames) {
        TileView* view = [reusableViews lastObject];
        [reusableViews removeLastObject];

        // Create one if we did not find a reusable one.
        if (view == nil) {
            view = [self createTile];
        }
        [self.documentView addSubview:view];

        
        // Place it and install it.
        view.frame = [neededFrame rectValue];
        view.layer.frame = [neededFrame rectValue];
        NSLog(@"adding layer %@ %f,%f,%f,%f", view.layer, view.layer.frame.origin.x, view.layer.frame.origin.y, view.layer.frame.size.width, view.layer.frame.size.height );

        assert(view.layer);
        [view.layer setNeedsDisplay];
    }
}

@end
