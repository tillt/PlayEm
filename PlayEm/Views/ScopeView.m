//
//  ScopeView.m
//  PlayEm
//
//  Created by Till Toenshoff on 18.04.21.
//  Copyright © 2021 Till Toenshoff. All rights reserved.
//

#import "ScopeView.h"
#import "UIView+Visibility.h"

const double kControlPanelVisiblePhase = 10.0f;

@interface ScopeView ()
@property (strong, nonatomic) NSTimer *delayedHide;
@end

@implementation ScopeView
{
   
}

- (void)awakeFromNib
{
    [super awakeFromNib];
    
    self.preferredFramesPerSecond = 30.0f;
//    assert(_playPause);
//
//    self.playPause.wantsLayer = YES;
//    self.playPause.layer.cornerRadius = 5;
//    self.playPause.layer.masksToBounds = YES;
//    
//    //self.controlPanel.layer.cornerRadius = 8;
//    //self.controlPanel.layer.masksToBounds = YES;
//    self.controlPanel.material = NSVisualEffectMaterialMenu;
//    self.controlPanel.blendingMode = NSVisualEffectBlendingModeWithinWindow;
}


/*
- (void)initTrackingArea
{
    NSTrackingAreaOptions options = (NSTrackingActiveAlways | NSTrackingInVisibleRect |
                             NSTrackingMouseEnteredAndExited | NSTrackingMouseMoved);

    NSTrackingArea *area = [[NSTrackingArea alloc] initWithRect:self.bounds
                                                        options:options
                                                          owner:self
                                                       userInfo:nil];

    NSLog(@"initTrackingArea:%lf x %lf", self.bounds.size.width, self.bounds.size.height);
    
    [self addTrackingArea:area];
}

- (void)updateTrackingAreas
{
    [self initTrackingArea];
}

- (void)updatedControlPanel
{
    [self delayHide];
}

- (void)delayHide
{
    ScopeView* __weak weakSelf = self;
    double timerInterval = kControlPanelVisiblePhase;
    if (_delayedHide != nil) {
        [_delayedHide invalidate];
    }
    _delayedHide = [NSTimer scheduledTimerWithTimeInterval:timerInterval repeats:NO block:^(NSTimer *timer){
        [weakSelf.controlPanel setVisible:NO animated:YES];
    }];
}
 */

/*
- (void)mouseEntered:(NSEvent *)event
{
    if (![_controlPanel visible]) {
        [_controlPanel setVisible:YES animated:YES];
    }
    [self delayHide];
}

- (void)mouseMoved:(NSEvent *)event
{
    if (![_controlPanel visible]) {
        [_controlPanel setVisible:YES animated:YES];
    }
    [self delayHide];
}
*/
@end
