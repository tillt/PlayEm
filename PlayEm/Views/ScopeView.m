//
//  ScopeView.m
//  PlayEm
//
//  Created by Till Toenshoff on 18.04.21.
//  Copyright © 2021 Till Toenshoff. All rights reserved.
//

#import "ScopeView.h"
#import "UIView+Visibility.h"

NSString * const kScopeViewDidLiveResizeNotification = @"ScopeViewDidLiveResizeNotification";
const double kControlPanelVisiblePhase = 10.0f;

@interface ScopeView ()
@property (strong, nonatomic) NSTimer *delayedHide;
@property (assign, nonatomic) CGRect oldFrame;
@end

@implementation ScopeView
{
   
}

- (nonnull instancetype)initWithFrame:(CGRect)frameRect device:(nullable id<MTLDevice>)device
{
    self = [super initWithFrame:frameRect device:device];
    if (self) {
        self.colorPixelFormat = MTLPixelFormatBGRA8Unorm;
        self.depthStencilPixelFormat = MTLPixelFormatInvalid;
        self.drawableSize = frameRect.size;
        self.autoresizingMask = NSViewHeightSizable | NSViewWidthSizable;
        self.autoResizeDrawable = YES;
        self.paused = NO;
        self.layer.opaque = YES;
    }
    return self;
}

- (void)viewWillStartLiveResize
{
    _oldFrame = self.frame;
    [super viewWillStartLiveResize];
}

- (void)viewDidEndLiveResize
{
    [super viewDidEndLiveResize];
    NSLog(@"viewDidEndLiveResize ScopeView");
    if (!CGRectEqualToRect(self.frame, _oldFrame)) {
        NSLog(@"ScopeView changed, inform it");
        [[NSNotificationCenter defaultCenter] postNotificationName:kScopeViewDidLiveResizeNotification
                                                            object:self];
    } else {
        NSLog(@"ScopeView didnt change");
    }
}


@end
