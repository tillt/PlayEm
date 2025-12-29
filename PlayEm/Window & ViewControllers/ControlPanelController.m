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
#import "../Views/SymbolButton.h"
#import "NSImage+Resize.h"

NSString * const kBPMDefault = @"";
NSString * const kKeyDefault = @"";

static const NSTimeInterval kBeatEffectRampUp = 0.05f;
static const NSTimeInterval kBeatEffectRampDown = 0.5f;

extern NSString * const kAudioControllerChangedPlaybackStateNotification;
extern NSString * const kPlaybackStateStarted;
extern NSString * const kPlaybackStateEnded;
extern NSString * const kPlaybackStatePaused;
extern NSString * const kPlaybackStatePlaying;

@interface ControlPanelController ()
@property (strong, nonatomic) NSTextField* keyField;

@property (strong, nonatomic) NSTextField* duration;
@property (strong, nonatomic) NSTextField* time;

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
        _durationUnitTime = YES;
        _delegate = delegate;
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(AudioControllerPlaybackStateChange:)
                                                     name:kAudioControllerChangedPlaybackStateNotification
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(beatEffect:)
                                                     name:kBeatTrackedSampleBeatNotification
                                                   object:nil];
    }
    return self;
}

- (void)AudioControllerPlaybackStateChange:(NSNotification*)notification
{
    NSString* state = notification.object;
    BOOL playing = [state isEqualToString:kPlaybackStatePlaying];
    // By closing the window as soon as the playback ends or gets paused we avoid
    // having to re-init the shazam stream. We assume its ok for the user.
    if (!playing) {
        [_coverButton pauseAnimating];
    }
    [_coverButton setStill:!playing animated:YES];
    if (playing) {
        [_coverButton startAnimating];
    }
}

- (BOOL)automaticallyAdjustsSize
{
    return YES;
}

- (void)toggleProgressUnit:(id)sender
{
    _durationUnitTime = !_durationUnitTime;
}

- (void)loadView
{
    NSLog(@"%s", __PRETTY_FUNCTION__);
    
    const CGFloat playPauseButtonY = 5.0;
    const CGFloat playPauseButtonWidth = 30.0;
    
    const CGFloat volumeSliderY = 10.0;
    
    const CGFloat controlPanelWidth = 826.0;
    const CGFloat controlPanelHeight = 56.0;

    const CGFloat timeLabelWidth = 152.0;
    const CGFloat timeLabelHeight = 16.0;

    const CGFloat coverButtonX = 2.0;
    const CGFloat coverButtonY = 0.0;

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
       
    const CGFloat loopButtonY = playPauseButtonY + floor(([[Defaults sharedDefaults] largeFontSize] -
                                                          [[Defaults sharedDefaults] normalFontSize]) / 2.0) + 2.0;

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
   
    const CGFloat coverButtonWidth = self.view.frame.size.height - 2.0;
    _coverButton = [[IdentificationCoverView alloc] initWithFrame:NSMakeRect(coverButtonX,
                                                                             coverButtonY,
                                                                             coverButtonWidth,
                                                                             coverButtonWidth)
                                                   contentsInsets:NSEdgeInsetsZero
                                                            style:CoverViewStyleSepiaForSecondImageLayer | CoverViewStyleRotatingLaser];

    NSClickGestureRecognizer* recognizer = [[NSClickGestureRecognizer alloc] initWithTarget:_delegate
                                                                                     action:@selector(showInfoForCurrentSong:)];
    recognizer.numberOfClicksRequired = 1;
    [_coverButton addGestureRecognizer:recognizer];
    
    [self.view addSubview:_coverButton];
   
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
    layer.drawsAsynchronously = YES;
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
    layer.drawsAsynchronously = YES;
    layer.masksToBounds = NO;
    layer.mask = [CAShapeLayer MaskLayerFromRect:layer.bounds];
    [_albumArtistView.layer addSublayer:layer];
    
    _playPause = [[SymbolButton alloc] initWithFrame:CGRectMake(_titleView.frame.origin.x + scrollingTextViewWidth + 64.0f,
                                                                playPauseButtonY,
                                                                playPauseButtonWidth + 8.0,
                                                                [[Defaults sharedDefaults] largeFontSize] + 14.0)];
    
    _playPause.symbolName = @"play.fill";
    _playPause.alternateSymbolName = @"pause.fill";
    _playPause.state = NSControlStateValueOff;
    _playPause.enabled = NO;
    _playPause.target = _delegate;
    _playPause.action = @selector(togglePause:);
    [self.view addSubview:_playPause];

    _autoplayProgress = [[NSProgressIndicator alloc] initWithFrame:NSMakeRect(_titleView.frame.origin.x + scrollingTextViewWidth + 54.0f,
                                                                              _playPause.frame.origin.y + bpmLabelHeight - 14.0,
                                                                              20.0,
                                                                              20.0)];
    _autoplayProgress.style = NSProgressIndicatorStyleSpinning;
    _autoplayProgress.displayedWhenStopped = NO;
    _autoplayProgress.autoresizingMask =  NSViewNotSizable | NSViewMinXMargin | NSViewMaxXMargin| NSViewMinYMargin | NSViewMaxYMargin;
    [self.view addSubview:_autoplayProgress];

    _loop = [[SymbolButton alloc] initWithFrame:NSMakeRect(_playPause.frame.origin.x + _playPause.frame.size.width - 8.0,
                                                           loopButtonY,
                                                           loopButtonWidth,
                                                           [[Defaults sharedDefaults] normalFontSize] + 8.0)];
    
    _loop.symbolName = @"arrow.right";
    _loop.alternateSymbolName = @"infinity";
    _loop.target = nil;
    _loop.action = nil;

    _loop.state = NSControlStateValueOff;
    [self.view addSubview:_loop];

    _time = [NSTextField textFieldWithString:@"--:--:--"];
    _time.bordered = NO;
    _time.editable = NO;
    _time.selectable = NO;
    _time.drawsBackground = NO;
    _time.textColor = [[Defaults sharedDefaults] secondaryLabelColor];
    _time.alignment = NSTextAlignmentRight;
    _time.frame = NSMakeRect(_playPause.frame.origin.x - timeLabelWidth + 10.0,
                             _playPause.frame.origin.y + timeLabelHeight + 8.0,
                             timeLabelWidth,
                             timeLabelHeight);
    [self.view addSubview:_time];

    NSClickGestureRecognizer* gesture = [[NSClickGestureRecognizer alloc] initWithTarget:self
                                                                                  action:@selector(toggleProgressUnit:)];
    gesture.buttonMask = 0x1;
    [_time addGestureRecognizer:gesture];

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
    
    gesture = [[NSClickGestureRecognizer alloc] initWithTarget:self action:@selector(toggleProgressUnit:)];
    gesture.buttonMask = 0x1;
    [_duration addGestureRecognizer:gesture];
    
    _volumeSlider = [[NSSlider alloc] initWithFrame:NSMakeRect(_playPause.frame.origin.x + _playPause.frame.size.width + 70.0,
                                                               volumeSliderY,
                                                               sliderWidth,
                                                               sliderHeight)];
    _volumeSlider.trackFillColor = [[Defaults sharedDefaults] lightFakeBeamColor];
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
    
    gesture = [[NSClickGestureRecognizer alloc] initWithTarget:self action:@selector(resetTempo:)];
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
    
    _keyField = [NSTextField textFieldWithString:kKeyDefault];
    _keyField.bordered = NO;
    _keyField.editable = NO;
    _keyField.selectable = NO;
    _keyField.drawsBackground = NO;
    _keyField.textColor = [[Defaults sharedDefaults] secondaryLabelColor];
    _keyField.alignment = NSTextAlignmentRight;
    _keyField.frame = NSMakeRect(_level.frame.origin.x + _level.frame.size.width,
                            _playPause.frame.origin.y + bpmLabelHeight + 8.0,
                            keyLabelWidth,
                            bpmLabelHeight);
    [self.view addSubview:_keyField];

    _keyProgress = [[NSProgressIndicator alloc] initWithFrame:NSMakeRect(_keyField.frame.origin.x + 42.0,
                                                                         _keyField.frame.origin.y + 4.0,
                                                                          14.0,
                                                                          14.0)];
    _keyProgress.style = NSProgressIndicatorStyleSpinning;
    _keyProgress.displayedWhenStopped = NO;
    _keyProgress.autoresizingMask =  NSViewNotSizable | NSViewMinXMargin | NSViewMaxXMargin| NSViewMinYMargin | NSViewMaxYMargin;
    [self.view addSubview:_keyProgress];

    _beatIndicator = [NSTextField textFieldWithString:@"􀀁"];
    _beatIndicator.bordered = NO;
    _beatIndicator.textColor = [[Defaults sharedDefaults] lightFakeBeamColor];;
    _beatIndicator.drawsBackground = NO;
    _beatIndicator.editable = NO;
    _beatIndicator.selectable = NO;
    _beatIndicator.alignment = NSTextAlignmentCenter;
    _beatIndicator.font = [NSFont systemFontOfSize:3.0f];
    _beatIndicator.frame = NSMakeRect(  _level.frame.origin.x + _level.frame.size.width + 100.0f,
                                        _playPause.frame.origin.y + bpmLabelHeight + 1.0,
                                        beatIndicatorWidth,
                                        beatIndicatorHeight);
    _beatIndicator.alphaValue = 0.0;
    _beatIndicator.wantsLayer = YES;
    _beatIndicator.layer.drawsAsynchronously = YES;
    [self.view addSubview:_beatIndicator];

    layer = [CALayer new];
    layer.drawsAsynchronously = YES;
    layer.backgroundFilters = @[ intenseBloomFilter ];
    layer.frame = NSInsetRect(_beatIndicator.bounds, -8, -8);
    layer.masksToBounds = NO;
    layer.mask = [CAShapeLayer MaskLayerFromRect:layer.bounds];
    [_beatIndicator.layer addSublayer:layer];
    
    _beatProgress = [[NSProgressIndicator alloc] initWithFrame:NSMakeRect(_beatIndicator.frame.origin.x + 58.0,
                                                                          _playPause.frame.origin.y + bpmLabelHeight + 13.0,
                                                                          14.0,
                                                                          14.0)];
    _beatProgress.style = NSProgressIndicatorStyleSpinning;
    _beatProgress.displayedWhenStopped = NO;
    _beatProgress.autoresizingMask =  NSViewNotSizable | NSViewMinXMargin | NSViewMaxXMargin| NSViewMinYMargin | NSViewMaxYMargin;
    [self.view addSubview:_beatProgress];
    
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
    layer.drawsAsynchronously = YES;
    layer.frame = NSInsetRect(_level.bounds, -8, -8);
    layer.masksToBounds = NO;
    layer.mask = [CAShapeLayer MaskLayerFromRect:layer.bounds];
    [_level.layer addSublayer:layer];
    
    layer = [CALayer layer];
    layer.drawsAsynchronously = YES;
    layer.backgroundColor = [[NSColor colorWithPatternImage:[NSImage imageNamed:@"RastaPattern"]] CGColor];
    layer.contentsScale = NSViewLayerContentsPlacementScaleProportionallyToFill;
    layer.frame = NSInsetRect(_level.bounds, -8, -8);
    layer.compositingFilter = [CIFilter filterWithName:@"CISourceAtopCompositing"];
    layer.opacity = 0.5;
    [_level.layer addSublayer:layer];
}

- (void)setKey:(NSString*)key hint:(NSString*)hint
{
    if (key == nil) {
        NSLog(@"invalid key pressed - just got a nil pointer");
        return;
    }
    _keyField.stringValue = key;
    _keyField.toolTip = hint;
}

- (void)setKeyHidden:(BOOL)hidden
{
    _keyField.hidden = hidden;
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
    _coverButton.image = [NSImage resizedImageWithData:[meta artworkWithDefault] size:_coverButton.bounds.size];
    _titleView.text = meta.title.length > 0 ? meta.title : @"unknown";
    _albumArtistView.text = (meta.album.length > 0 && meta.artist.length > 0) ?
        [NSString stringWithFormat:@"%@ — %@", meta.artist, meta.album] :
        (meta.album.length > 0 ? meta.album : (meta.artist.length > 0 ?
                                               meta.artist : @"unknown") );
//    _coverButton.enabled = YES;
    _playPause.enabled = YES;
}

- (void)beatEffect:(NSNotification*)notification
{
    // Animate the beat-indicator
    
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

    const NSDictionary* dict = notification.object;
    int style = [dict[kBeatNotificationKeyStyle] intValue];
    unsigned long long beat = [dict[kBeatNotificationKeyBeat] unsignedLongLongValue];
    unsigned int index = (beat + 1) % 4;
    double bpm = [dict[kBeatNotificationKeyTempo] doubleValue];
    double beatLength = 60 / bpm;

    if ((style & BeatEventStyleAlarmOutro) == BeatEventStyleAlarmOutro) {
        [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
            [context setDuration:beatLength / 2.0];
            [context setTimingFunction:[CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseIn]];
            self.duration.animator.alphaValue = 0.4;
        } completionHandler:^{
            [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
                [context setDuration:beatLength / 2.0];
                [context setTimingFunction:[CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut]];
                self.duration.animator.alphaValue = 1.0;
            }];
        }];
    } else if ((style & BeatEventStyleAlarmTeardown) == BeatEventStyleAlarmTeardown && index == 1) {
        [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
            [context setDuration:beatLength];
            [context setTimingFunction:[CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseIn]];
            self.duration.animator.alphaValue = 0.4;
        } completionHandler:^{
            [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
                [context setDuration:beatLength];
                [context setTimingFunction:[CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut]];
                self.duration.animator.alphaValue = 1.0;
            }];
        }];
    }
    
    if (!_durationUnitTime) {
        const unsigned long long totalBeats = [dict[kBeatNotificationKeyTotalBeats] unsignedLongLongValue];
        const unsigned long long remainingBeats = totalBeats - (beat + 1);
        
        //NSLog(@"remain: %lld", remainingBeats);
        
        const unsigned long long barIndex = (beat / 4) + 1;
        const unsigned int beatIndex = (beat % 4) + 1;

        const unsigned long long remainingBarIndex = remainingBeats / 4;
        const unsigned int remainingBeatIndex = (remainingBeats % 4) + 1;

        [self updateDuration:[NSString stringWithFormat:@"%lld:%d", remainingBarIndex, remainingBeatIndex]
                        time:[NSString stringWithFormat:@"%lld:%d", barIndex, beatIndex]];
    }
}

- (void)updateDuration:(NSString*)duration time:(NSString*)time
{
    _duration.stringValue = duration;
    _time.stringValue = time;
}

- (void)warningEffect:(NSNotification*)notification
{
}

@end

