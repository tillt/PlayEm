//
//  ControlPanelController.m
//  PlayEm
//
//  Created by Till Toenshoff on 27.11.22.
//  Copyright © 2022 Till Toenshoff. All rights reserved.
//
#import <CoreImage/CoreImage.h>

#import "ControlPanelController.h"
#import "ScrollingTextView.h"
#import "Defaults.h"
#import "NSBezierPath+CGPath.h"
#import "CAShapeLayer+Path.h"
#import "LevelIndicatorCell.h"
#import "../Views/IdentificationCoverView.h"
#import "MediaMetaData.h"
#import "BeatEvent.h"

NSString * const kBPMDefault = @"--- BPM";
NSString * const kKeyDefault = @"---";

static const NSTimeInterval kBeatEffectRampUp = 0.05f;
static const NSTimeInterval kBeatEffectRampDown = 0.5f;

extern NSString * const kAudioControllerChangedPlaybackStateNotification;
extern NSString * const kPlaybackStateStarted;
extern NSString * const kPlaybackStateEnded;
extern NSString * const kPlaybackStatePaused;
extern NSString * const kPlaybackStatePlaying;

@interface ControlPanelController ()
@property (strong, nonatomic) ScrollingTextView* titleView;
@property (strong, nonatomic) ScrollingTextView* albumArtistView;
@property (strong, nonatomic) IdentificationCoverView* coverButton;
@property (weak, nonatomic) id<ControlPanelControllerDelegate> delegate;
@end

@implementation ControlPanelController

- (id)initWithDelegate:(id<ControlPanelControllerDelegate>)delegate
{
    self = [super init];
    if (self) {
        _delegate = delegate;
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(audioControllerChangedPlaybackState:) name:kAudioControllerChangedPlaybackStateNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(beatEffect:) name:kBeatTrackedSampleBeatNotification object:nil];
    }
    return self;
}

- (void)audioControllerChangedPlaybackState:(NSNotification*)notification
{
    NSString* state = notification.object;
    if ([state isEqualToString:kPlaybackStateEnded]) {
        [_coverButton stopAnimating];
    } else if ([state isEqualToString:kPlaybackStatePaused]) {
        [_coverButton pauseAnimating];
    } else if ([state isEqualToString:kPlaybackStatePlaying]) {
        [_coverButton startAnimating];
    }
}

- (BOOL)automaticallyAdjustsSize
{
    return YES;
}

- (void)loadView
{
    NSLog(@"loadView");
    
    const CGFloat playPauseButtonY = 5.0;
    const CGFloat playPauseButtonWidth = 35.0;
    
    const CGFloat volumeSliderY = 10.0;
    
    const CGFloat controlPanelWidth = 826.0;
    const CGFloat controlPanelHeight = 56.0;

    const CGFloat timeLabelWidth = 152.0;
    const CGFloat timeLabelHeight = 16.0;

    const CGFloat coverButtonX = 2.0;
    const CGFloat coverButtonY = 1.0;

    const CGFloat keyLabelWidth = 60.0f;

    const CGFloat bpmLabelWidth = 60.0f;
    const CGFloat bpmLabelHeight = 16.0f;
    
    const CGFloat beatIndicatorWidth = 16.0f;
    const CGFloat beatIndicatorHeight = 16.0f;
    
    const CGFloat sliderWidth = 100.0;
    const CGFloat sliderHeight = 20.0;
    const CGFloat levelHeight = 17.0;
    
    const CGFloat scrollingTextViewWidth = 320.0;
    const CGFloat scrollingTextViewHeight = 32.0;
    const CGFloat loopButtonWidth = 32;
    
    const CGFloat largeSymbolFontSize = 21.0;
    const CGFloat regularSymbolFontSize = 13.0;
   
    const CGFloat loopButtonY = playPauseButtonY + floor((largeSymbolFontSize -
                                                          regularSymbolFontSize) / 2.0);

    NSVisualEffectView* fxView = [[NSVisualEffectView alloc] initWithFrame:NSMakeRect(0.0, 0.0, controlPanelWidth, controlPanelHeight)];
    fxView.material = NSVisualEffectMaterialSheet;
    self.view = fxView;
    self.view.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;

    CIFilter* lowBloomFilter = [CIFilter filterWithName:@"CIBloom"];
    [lowBloomFilter setDefaults];
    [lowBloomFilter setValue: [NSNumber numberWithFloat:3.0] forKey: @"inputRadius"];
    [lowBloomFilter setValue: [NSNumber numberWithFloat:1.0] forKey: @"inputIntensity"];
    
    CIFilter* titleBloomFilter = [CIFilter filterWithName:@"CIBloom"];
    [titleBloomFilter setDefaults];
    [titleBloomFilter setValue: [NSNumber numberWithFloat:4.5] forKey: @"inputRadius"];
    [titleBloomFilter setValue: [NSNumber numberWithFloat:1.0] forKey: @"inputIntensity"];

    CIFilter* intenseBloomFilter = [CIFilter filterWithName:@"CIBloom"];
    [intenseBloomFilter setDefaults];
    [intenseBloomFilter setValue: [NSNumber numberWithFloat:7.0] forKey: @"inputRadius"];
    [intenseBloomFilter setValue: [NSNumber numberWithFloat:1.5] forKey: @"inputIntensity"];

    _zoomBlur = [CIFilter filterWithName:@"CIZoomBlur"];
    [_zoomBlur setDefaults];
    [_zoomBlur setValue: [NSNumber numberWithFloat:0.5] forKey: @"inputAmount"];
   
//    _coverButton = [RadarButton buttonWithImage:[NSImage imageNamed:@"UnknownSong"]
//                                         target:_delegate
//                                         action:@selector(showInfoForCurrentSong:)];
    
    const CGFloat coverButtonWidth = self.view.frame.size.height - 4.0;
    _coverButton = [[IdentificationCoverView alloc] initWithFrame:NSMakeRect(coverButtonX,
                                                                             coverButtonY,
                                                                             coverButtonWidth,
                                                                             coverButtonWidth)];
    NSClickGestureRecognizer* recognizer = [[NSClickGestureRecognizer alloc] initWithTarget:_delegate action:@selector(showInfoForCurrentSong:)];
    recognizer.numberOfClicksRequired = 1;
    [_coverButton addGestureRecognizer:recognizer];
    
    //    _coverButton.bezelStyle = NSBezelStyleTexturedSquare;
//    _coverButton.imagePosition = NSImageOnly;
    //_coverButton.imageScaling = NSImageScaleProportionallyUpOrDown;
//    [_coverButton setButtonType: NSButtonTypeMomentaryPushIn];
    _coverButton.layer.cornerRadius = 3;
    _coverButton.layer.masksToBounds = YES;
    [self.view addSubview:_coverButton];
   
//    CALayer* layer = [CALayer new];
//    layer.compositingFilter = @[ _zoomBlur, intenseBloomFilter ];
//    layer.frame = NSInsetRect(_coverButton.layer.bounds, -10.0, -10.0);
//    layer.masksToBounds = NO;
//    layer.mask = [CAShapeLayer MaskLayerFromRect:layer.frame];
//    [_coverButton.layer addSublayer:layer];
    
    _titleView = [[ScrollingTextView alloc] initWithFrame:NSMakeRect(coverButtonX + coverButtonWidth + 2.0,
                                                                     self.view.frame.size.height - (scrollingTextViewHeight + 5.0),
                                                                     scrollingTextViewWidth,
                                                                     scrollingTextViewHeight)];
    _titleView.textColor = [[Defaults sharedDefaults] lightFakeBeamColor];
    _titleView.font = [NSFont systemFontOfSize:scrollingTextViewHeight - 5.0];
    [self.view addSubview:_titleView];

    CALayer* layer = [CALayer new];
    layer.backgroundFilters = @[ titleBloomFilter ];
    layer.frame = NSInsetRect(_titleView.bounds, -16, -16);
    layer.masksToBounds = NO;
    layer.mask = [CAShapeLayer MaskLayerFromRect:layer.bounds];
    [_titleView.layer addSublayer:layer];
    
    _albumArtistView = [[ScrollingTextView alloc] initWithFrame:NSMakeRect(_titleView.frame.origin.x,
                                                                           _titleView.frame.origin.y - (scrollingTextViewHeight - 14.0),
                                                                           scrollingTextViewWidth,
                                                                           scrollingTextViewHeight - 12.0f)];
    _albumArtistView.textColor = [[Defaults sharedDefaults] regularFakeBeamColor];
    _albumArtistView.font = [NSFont systemFontOfSize:_albumArtistView.frame.size.height - 5.0];
    [self.view addSubview:_albumArtistView];

    layer = [CALayer new];
    layer.backgroundFilters = @[ lowBloomFilter ];
    layer.frame = NSInsetRect(_albumArtistView.bounds, -16, -16);
    layer.masksToBounds = NO;
    layer.mask = [CAShapeLayer MaskLayerFromRect:layer.bounds];
    [_albumArtistView.layer addSublayer:layer];
    
    _playPause = [NSButton buttonWithTitle:@"􀊄" target:_delegate action:@selector(togglePause:)];
    _playPause.frame = NSMakeRect(_titleView.frame.origin.x + scrollingTextViewWidth + 70.0f,
                                  playPauseButtonY,
                                  playPauseButtonWidth,
                                  largeSymbolFontSize + 2.0);
    _playPause.bordered = NO;
    _playPause.alternateTitle = @"􀊆";
    [_playPause setButtonType: NSButtonTypeToggle];
    _playPause.bezelStyle = NSBezelStyleTexturedRounded;
    _playPause.font = [NSFont systemFontOfSize:largeSymbolFontSize];
    [self.view addSubview:_playPause];

    _loop = [NSButton buttonWithTitle:@"􀊞" target:nil action:nil];
    _loop.frame = NSMakeRect(_playPause.frame.origin.x + _playPause.frame.size.width,
                             loopButtonY,
                             loopButtonWidth,
                             regularSymbolFontSize + 2.0);
    _loop.bordered = NO;
    [_loop setButtonType: NSButtonTypeToggle];
    _loop.state = NSControlStateValueOff;
    _loop.bezelStyle = NSBezelStyleTexturedRounded;
    _loop.font = [NSFont systemFontOfSize:regularSymbolFontSize];
    [self.view addSubview:_loop];
    
    _time = [NSTextField textFieldWithString:@"--:--:--"];
    _time.bordered = NO;
    _time.editable = NO;
    _time.selectable = NO;
    _time.drawsBackground = NO;
    _time.textColor = [[Defaults sharedDefaults] secondaryLabelColor];
    _time.alignment = NSTextAlignmentRight;
    _time.frame = NSMakeRect(_playPause.frame.origin.x - timeLabelWidth,
                             _playPause.frame.origin.y + timeLabelHeight + 8.0,
                             timeLabelWidth,
                             timeLabelHeight);
    [self.view addSubview:_time];
   
    NSTextField* textField = [NSTextField textFieldWithString:@"-"];
    textField.bordered = NO;
    textField.textColor = [[Defaults sharedDefaults] secondaryLabelColor];
    textField.drawsBackground = NO;
    textField.editable = NO;
    textField.selectable = NO;
    textField.alignment = NSTextAlignmentCenter;
    textField.frame = NSMakeRect(_playPause.frame.origin.x + _playPause.frame.size.width - 16.0,
                                 _time.frame.origin.y,
                                 10.0,
                                 timeLabelHeight);
    [self.view addSubview:textField];
    
    _duration = [NSTextField textFieldWithString:@"--:--:--"];
    _duration.bordered = NO;
    _duration.editable = NO;
    _duration.selectable = NO;
    _duration.font = [NSFont systemFontOfSize:13.0];
    _duration.textColor = [[Defaults sharedDefaults] secondaryLabelColor];
    _duration.drawsBackground = NO;
    _duration.alignment = NSTextAlignmentLeft;
    _duration.frame = NSMakeRect(textField.frame.origin.x + textField.frame.size.width,
                                 _time.frame.origin.y,
                                 timeLabelWidth,
                                 timeLabelHeight);
    [self.view addSubview:_duration];
    
    _volumeSlider = [[NSSlider alloc] initWithFrame:NSMakeRect(_playPause.frame.origin.x + _playPause.frame.size.width + 70.0,
                                                               volumeSliderY,
                                                               sliderWidth,
                                                               sliderHeight)];
    _volumeSlider.trackFillColor = [[Defaults sharedDefaults] lightBeamColor];
    _volumeSlider.vertical = NO;
    _volumeSlider.maxValue = 1.0;
    _volumeSlider.minValue = 0.0;
    _volumeSlider.floatValue = 1.0;
    _volumeSlider.controlSize = NSControlSizeMini;
    [_volumeSlider setAction:@selector(volumeChange:)];
    //[_volumeSlider setAction:@se];
    [self.view addSubview:_volumeSlider];
    
    textField = [NSTextField textFieldWithString:@"􀊥"];
    textField.bordered = NO;
    textField.textColor = [[Defaults sharedDefaults] secondaryLabelColor];
    textField.drawsBackground = NO;
    textField.editable = NO;
    textField.selectable = NO;
    textField.alignment = NSTextAlignmentRight;
    textField.font = [NSFont systemFontOfSize:15.0f];
    textField.frame = NSMakeRect(_volumeSlider.frame.origin.x - 30.0,
                                 _volumeSlider.frame.origin.y,
                                 30.0,
                                 sliderHeight);
    [self.view addSubview:textField];
    
    textField = [NSTextField textFieldWithString:@"􀊩"];
    textField.bordered = NO;
    textField.textColor = [[Defaults sharedDefaults] secondaryLabelColor];
    textField.drawsBackground = NO;
    textField.editable = NO;
    textField.selectable = NO;
    textField.alignment = NSTextAlignmentLeft;
    textField.font = [NSFont systemFontOfSize:15.0f];
    textField.frame = NSMakeRect(_volumeSlider.frame.origin.x + _volumeSlider.frame.size.width,
    _volumeSlider.frame.origin.y,
    30.0,
    sliderHeight);
    [self.view addSubview:textField];
    
    _tempoSlider = [[NSSlider alloc] initWithFrame:NSMakeRect(_volumeSlider.frame.origin.x + _volumeSlider.frame.size.width + 50,
                                                               volumeSliderY,
                                                               sliderWidth,
                                                               sliderHeight)];
    _tempoSlider.trackFillColor = [NSColor labelColor];
    _tempoSlider.vertical = NO;
    _tempoSlider.maxValue = 1.2;
    _tempoSlider.minValue = 0.8;
    _tempoSlider.floatValue = 1.0;
    _tempoSlider.controlSize = NSControlSizeMini;
    [_tempoSlider setAction:@selector(tempoChange:)];
    [self.view addSubview:_tempoSlider];
    
    NSClickGestureRecognizer* gesture = [[NSClickGestureRecognizer alloc] initWithTarget:self action:@selector(resetTempo:)];
    gesture.buttonMask = 0x2; // right mouse
    [_tempoSlider addGestureRecognizer:gesture];
    
    textField = [NSTextField textFieldWithString:@"􀆊"];
    textField.bordered = NO;
    textField.textColor = [[Defaults sharedDefaults] secondaryLabelColor];
    textField.drawsBackground = NO;
    textField.editable = NO;
    textField.selectable = NO;
    textField.alignment = NSTextAlignmentRight;
    textField.font = [NSFont systemFontOfSize:16.0f];
    textField.frame = NSMakeRect(_tempoSlider.frame.origin.x - 30.0,
                                 _tempoSlider.frame.origin.y,
                                 30.0,
                                 sliderHeight);
    [self.view addSubview:textField];
    
    textField = [NSTextField textFieldWithString:@"􀰫"];
    textField.bordered = NO;
    textField.textColor = [[Defaults sharedDefaults] secondaryLabelColor];
    textField.drawsBackground = NO;
    textField.editable = NO;
    textField.selectable = NO;
    textField.alignment = NSTextAlignmentLeft;
    textField.font = [NSFont systemFontOfSize:16.0f];
    textField.frame = NSMakeRect(_tempoSlider.frame.origin.x + _tempoSlider.frame.size.width,
                                 _volumeSlider.frame.origin.y,
                                 30.0,
                                 sliderHeight);
    [self.view addSubview:textField];

    _level = [[NSLevelIndicator alloc] initWithFrame:NSMakeRect(_volumeSlider.frame.origin.x + 2.0,
                                                                _volumeSlider.frame.origin.y + levelHeight - 4.0,
                                                                sliderWidth - 4,
                                                                levelHeight)];
    _level.levelIndicatorStyle = NSLevelIndicatorStyleContinuousCapacity;
    _level.wantsLayer = YES;
    _level.layer.masksToBounds = NO;
    _level.editable = NO;
    LevelIndicatorCell* cell = [[LevelIndicatorCell alloc] initWithLevelIndicatorStyle:NSLevelIndicatorStyleContinuousCapacity];
    cell.maxValue = 1.0;
    cell.criticalValue = 1.0;
    cell.warningValue = 1.0;
    cell.minValue = 0.0;
    _level.cell = cell;
    [self.view addSubview:_level];
    
    _key = [NSTextField textFieldWithString:kKeyDefault];
    _key.bordered = NO;
    _key.editable = NO;
    _key.selectable = NO;
    _key.drawsBackground = NO;
    _key.textColor = [[Defaults sharedDefaults] secondaryLabelColor];
    _key.alignment = NSTextAlignmentRight;
    _key.frame = NSMakeRect(_level.frame.origin.x + _level.frame.size.width,
                            _playPause.frame.origin.y + bpmLabelHeight + 8.0,
                            keyLabelWidth,
                            bpmLabelHeight);
    [self.view addSubview:_key];
    
    _beatIndicator = [NSTextField textFieldWithString:@"􀀁"];
    _beatIndicator.bordered = NO;
    _beatIndicator.textColor = [[Defaults sharedDefaults] lightFakeBeamColor];;
    _beatIndicator.drawsBackground = NO;
    _beatIndicator.editable = NO;
    _beatIndicator.selectable = NO;
    _beatIndicator.alignment = NSTextAlignmentCenter;
    _beatIndicator.font = [NSFont systemFontOfSize:3.0f];
    _beatIndicator.frame = NSMakeRect(_level.frame.origin.x + _level.frame.size.width + 100.0f,
                            _playPause.frame.origin.y + bpmLabelHeight + 1.0,
                            beatIndicatorWidth,
                            beatIndicatorHeight);
    _beatIndicator.alphaValue = 0.0;
    _beatIndicator.wantsLayer = YES;
    [self.view addSubview:_beatIndicator];

    layer = [CALayer new];
    layer.backgroundFilters = @[ intenseBloomFilter ];
    layer.frame = NSInsetRect(_beatIndicator.bounds, -8, -8);
    layer.masksToBounds = NO;
    layer.mask = [CAShapeLayer MaskLayerFromRect:layer.bounds];
    [_beatIndicator.layer addSublayer:layer];

    _bpm = [NSTextField textFieldWithString:kBPMDefault];
    _bpm.bordered = NO;
    _bpm.editable = NO;
    _bpm.selectable = NO;
    _bpm.drawsBackground = NO;
    _bpm.textColor = [[Defaults sharedDefaults] secondaryLabelColor];
    _bpm.alignment = NSTextAlignmentRight;
    _bpm.frame = NSMakeRect(_beatIndicator.frame.origin.x + _beatIndicator.frame.size.width - 4.0f,
                            _playPause.frame.origin.y + bpmLabelHeight + 8.0,
                            bpmLabelWidth,
                            bpmLabelHeight);
    [self.view addSubview:_bpm];
    
    layer = [CALayer new];
    layer.backgroundFilters = @[ intenseBloomFilter ];
    layer.frame = NSInsetRect(_level.bounds, -8, -8);
    layer.masksToBounds = NO;
    layer.mask = [CAShapeLayer MaskLayerFromRect:layer.bounds];
    [_level.layer addSublayer:layer];
    
    layer = [CALayer layer];
    layer.backgroundColor = [[NSColor colorWithPatternImage:[NSImage imageNamed:@"RastaPattern"]] CGColor];
    layer.contentsScale = NSViewLayerContentsPlacementScaleProportionallyToFill;
    layer.frame = NSInsetRect(_level.bounds, -8, -8);
    layer.compositingFilter = [CIFilter filterWithName:@"CISourceAtopCompositing"];
    layer.opacity = 0.5;
    [_level.layer addSublayer:layer];
}

- (void)resetTempo:(id)sender
{
    [_delegate resetTempo:sender];
}

- (void)tempoChange:(id)sender
{
    [_delegate tempoChange:sender];
}

- (void)volumeChange:(id)sender
{
    [_delegate volumeChange:sender];
}

- (void)viewDidLoad
{
    [super viewDidLoad];
}

- (void)setMeta:(MediaMetaData*)meta
{
    _coverButton.image = [meta imageFromArtwork];
    _titleView.text = meta.title.length > 0 ? meta.title : @"unknown";
    _albumArtistView.text = (meta.album.length > 0 && meta.artist.length > 0) ?
        [NSString stringWithFormat:@"%@ — %@", meta.artist, meta.album] :
        (meta.album.length > 0 ? meta.album : (meta.artist.length > 0 ?
                                               meta.artist : @"unknown") );
//    _coverButton.enabled = YES;
}

- (void)beatEffect:(NSNotification*)notification
{
    // Thats a weird mid-point but hey...
    CGSize mid = CGSizeMake((self.beatIndicator.layer.bounds.size.width - 1) / 2,
                            self.beatIndicator.layer.bounds.size.height - 2);
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
        [context setDuration:kBeatEffectRampUp];
        self.beatIndicator.animator.alphaValue = 1.0;
        CATransform3D tr = CATransform3DIdentity;
        tr = CATransform3DTranslate(tr, mid.width, mid.height, 0);
        tr = CATransform3DScale(tr, 3.1, 3.1, 1);
        tr = CATransform3DTranslate(tr, -mid.width, -mid.height, 0);
        self.beatIndicator.animator.layer.transform = tr;
    } completionHandler:^{
        [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
            [context setDuration:kBeatEffectRampDown];
            [context setTimingFunction:[CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut]];
            self.beatIndicator.animator.alphaValue = 0.0;
            CATransform3D tr = CATransform3DIdentity;
            tr = CATransform3DTranslate(tr, mid.width, mid.height, 0);
            tr = CATransform3DScale(tr, 1.0, 1.0, 1);
            tr = CATransform3DTranslate(tr, -mid.width, -mid.height, 0);
            self.beatIndicator.animator.layer.transform = tr;
        }];
    }];
}

@end

