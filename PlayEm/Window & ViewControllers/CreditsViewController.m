//
//  CreditsViewController.m
//  PlayEm
//
//  Created by Till Toenshoff on 8/23/25.
//  Copyright © 2025 Till Toenshoff. All rights reserved.
//
#import "CreditsViewController.h"

#import <CoreImage/CoreImage.h>
#import <QuartzCore/QuartzCore.h>

#import "../CAShapeLayer+Path.h"
#import "../Defaults.h"
#import "../Views/BloomyText.h"
#import "BeatEvent.h"

static const float kCreditsScrollDuration = 320.0f;
static const float kCreditsScrollDelay = 5.0f;
static const float kCreditsScrollBackDuration = 3.0f;

static const CGFloat kBigFontSize = 50.0f;
static const CGFloat kNormalFontSize = 13.0f;
static const CGFloat kSmallFontSize = 10.0f;

static NSString* kCreditsFileName = @"credits";
static NSString* kCreditsFileExtension = @"rtf";

@interface CreditsViewController () {
    NSInteger _bottomIndex;
    unsigned long long _offset;
    double lastEnergy;
}

@property (strong, nonatomic) NSTimer* timer;
@property (strong, nonatomic) NSTextView* creditsView;
@property (strong, nonatomic) NSImageView* imageView;

@end

@implementation CreditsViewController

- (id)infoValueForKey:(NSString*)key
{
    if ([[[NSBundle mainBundle] localizedInfoDictionary] objectForKey:key])
        return [[[NSBundle mainBundle] localizedInfoDictionary] objectForKey:key];

    return [[[NSBundle mainBundle] infoDictionary] objectForKey:key];
}

- (void)loadView
{
    const CGFloat scrolloWidth = 340.0f;
    const CGFloat scrolloHeight = 100.0f;
    const CGFloat imageWidth = 200.0f;
    const CGFloat totalWidth = scrolloWidth + imageWidth;
    const CGFloat totalHeight = scrolloHeight + 90.0f;

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(beatEffect:) name:kBeatTrackedSampleBeatNotification object:nil];

    const NSRect rect = NSMakeRect(0, 0, totalWidth, totalHeight);
    NSView* view = [[NSView alloc] initWithFrame:rect];

    NSImageView* imageView = [[NSImageView alloc] initWithFrame:NSMakeRect(0.0, 10.0, imageWidth, imageWidth)];
    imageView.image = [NSImage imageNamed:@"AppIcon"];
    [view addSubview:imageView];

    CGFloat d = 90.0;
    _imageView = [[NSImageView alloc] initWithFrame:NSMakeRect(d / 2.0, d / 2.0, imageWidth - d, imageWidth - d)];
    _imageView.wantsLayer = YES;
    _imageView.image = [NSImage imageNamed:@"Cone"];
    [imageView addSubview:_imageView];

    CIFilter* filter = [CIFilter filterWithName:@"CIZoomBlur"];
    [filter setDefaults];
    [filter setValue:[NSNumber numberWithFloat:1.0] forKey:@"inputAmount"];
    [filter setValue:[CIVector vectorWithCGPoint:CGPointMake(_imageView.frame.size.width / 2.0, _imageView.frame.size.height / 2.0)] forKey:@"inputCenter"];

    _imageView.layer.filters = @[ filter ];

    const CGFloat x = imageWidth;
    const CGFloat fieldWidth = view.frame.size.width - (imageWidth + 40.0);
    CGFloat y = view.frame.size.height - (kBigFontSize + 10.0);

    BloomyText* text = [[BloomyText alloc] initWithFrame:NSMakeRect(x, y, fieldWidth, kBigFontSize + 10)];
    text.text = [self infoValueForKey:@"CFBundleName"];
    text.font = [NSFont fontWithName:@"DIN Condensed" size:kBigFontSize];
    text.textColor = [[Defaults sharedDefaults] lightFakeBeamColor];
    text.fontSize = kBigFontSize;
    text.lightTextColor = [[Defaults sharedDefaults] lightBeamColor];
    [view addSubview:text];

    y -= kSmallFontSize + 2.0;

    NSString* version =
        [NSString stringWithFormat:@"Version %@ (%@)", [self infoValueForKey:@"CFBundleShortVersionString"], [self infoValueForKey:@"CFBundleVersion"]];

    NSTextField* textField = [NSTextField textFieldWithString:version];
    textField.bordered = NO;
    textField.textColor = [[Defaults sharedDefaults] secondaryLabelColor];
    textField.font = [NSFont systemFontOfSize:kNormalFontSize];
    textField.drawsBackground = NO;
    textField.editable = NO;
    textField.selectable = NO;
    textField.cell.truncatesLastVisibleLine = YES;
    textField.cell.lineBreakMode = NSLineBreakByTruncatingTail;
    textField.alignment = NSTextAlignmentLeft;
    textField.frame = NSMakeRect(x, y, fieldWidth, kNormalFontSize + 5);
    [view addSubview:textField];

    y -= kSmallFontSize + 2.0;

    NSString* copyright = [self infoValueForKey:@"NSHumanReadableCopyright"];

    textField = [NSTextField textFieldWithString:copyright];
    textField.bordered = NO;
    textField.textColor = [[Defaults sharedDefaults] secondaryLabelColor];
    textField.font = [NSFont systemFontOfSize:kSmallFontSize];
    textField.drawsBackground = NO;
    textField.editable = NO;
    textField.selectable = NO;
    textField.cell.truncatesLastVisibleLine = YES;
    textField.cell.lineBreakMode = NSLineBreakByTruncatingTail;
    textField.alignment = NSTextAlignmentLeft;
    textField.frame = NSMakeRect(x, y, fieldWidth, kSmallFontSize + 5);
    [view addSubview:textField];

    // Couldnt get rid of the inset that the RTF file itself appears to have using
    // TextEdit.
    const CGFloat smudgeRTFInset = 3.0;
    NSRect scrollRect = NSMakeRect(200.0f - smudgeRTFInset, 0.0f, scrolloWidth + smudgeRTFInset, scrolloHeight);

    NSScrollView* scrollView = [NSTextView scrollableTextView];
    scrollView.frame = scrollRect;
    scrollView.scrollerInsets = NSEdgeInsetsMake(0, 0, 0, 0);
    scrollView.contentInsets = NSEdgeInsetsMake(0, 0, 0, 0);
    scrollView.automaticallyAdjustsContentInsets = NO;

    _creditsView = scrollView.documentView;
    _creditsView.backgroundColor = [NSColor clearColor];
    _creditsView.editable = NO;

    NSURL* url = [[NSBundle mainBundle] URLForResource:kCreditsFileName withExtension:kCreditsFileExtension];
    NSData* data = [NSData dataWithContentsOfURL:url];
    NSError* error = nil;

    NSAttributedString* attributedString = [[NSAttributedString alloc]
              initWithData:data
                   options:@{NSDocumentTypeDocumentAttribute : NSRTFTextDocumentType, NSCharacterEncodingDocumentAttribute : @(NSUTF8StringEncoding)}
        documentAttributes:nil
                     error:&error];
    if (attributedString == nil) {
        NSLog(@"failed loading credits file: %@", error);
        return;
    }

    NSLog(@"attributedString height %f", attributedString.size.height);
    [_creditsView.textStorage appendAttributedString:attributedString];
    _creditsView.frame = NSMakeRect(0, 0, scrollRect.size.width, attributedString.size.height);

    [view addSubview:scrollView];
    self.view = view;
}

- (void)viewWillAppear
{
    [super viewWillAppear];

    // Make sure there is no ongoing animation.
    NSClipView* clipView = [_creditsView.enclosingScrollView contentView];
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext* context) {
        [context setDuration:0.0f];
        [context setTimingFunction:[CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionLinear]];
        [clipView setBoundsOrigin:CGPointMake(0.0, 0.0)];
    }];
}

- (void)viewDidAppear
{
    [super viewDidAppear];

    CreditsViewController* __weak weakSelf = self;

    // After some time, check if the user scrolled at all - if not, scroll through
    // credits slowly, then scroll back fast and signal `ready` for user.
    self.timer = [NSTimer
        scheduledTimerWithTimeInterval:kCreditsScrollDelay
                               repeats:NO
                                 block:^(NSTimer* timer) {
                                     NSClipView* clipView = [weakSelf.creditsView.enclosingScrollView contentView];
                                     NSPoint origin = [clipView bounds].origin;
                                     if (origin.y != 0.0) {
                                         return;
                                     }
                                     origin.y += weakSelf.creditsView.frame.size.height;
                                     [NSAnimationContext
                                         runAnimationGroup:^(NSAnimationContext* context) {
                                             [context setDuration:kCreditsScrollDuration];
                                             [context setTimingFunction:[CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionLinear]];
                                             [clipView.animator setBoundsOrigin:origin];
                                         }
                                         completionHandler:^{
                                             [NSAnimationContext
                                                 runAnimationGroup:^(NSAnimationContext* context) {
                                                     [context setDuration:kCreditsScrollBackDuration];
                                                     [context setTimingFunction:[CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut]];
                                                     [clipView.animator setBoundsOrigin:CGPointMake(0.0, 0.0)];
                                                 }
                                                 completionHandler:^{
                                                     [weakSelf.creditsView.enclosingScrollView flashScrollers];
                                                 }];
                                         }];
                                 }];
}

- (void)beatPumpingLayer:(CALayer*)layer tempo:(double)tempo localEnergy:(double)localEnergy totalEnergy:(float)totalEnergy
{
    if (localEnergy == 0.0) {
        localEnergy = 0.000000001;
    }
    const double depth = 7.5f;
    // Attempt to get a reasonably wide signal range by normalizing the locals
    // peaks by the globally most energy loaded samples.
    const double normalizedEnergy = MIN(localEnergy / totalEnergy, 1.0);

    // We quickly attempt to reach a value that is higher than the current one.
    const double convergenceSpeedUp = 0.8;
    // We slowly decay into a value that is lower than the current one.
    const double convergenceSlowDown = 0.08;

    double convergenceSpeed = normalizedEnergy > lastEnergy ? convergenceSpeedUp : convergenceSlowDown;
    // To make sure the result is not flapping we smooth (lerp) using the previous
    // result.
    double lerpEnergy = (normalizedEnergy * convergenceSpeed) + lastEnergy * (1.0 - convergenceSpeed);
    // Gate the result for safety -- may mathematically not be needed, too lazy to
    // find out.
    double slopedEnergy = MIN(lerpEnergy, 1.0);

    lastEnergy = slopedEnergy;

    CGFloat scaleByPixel = slopedEnergy * depth;
    double peakZoomBlurAmount = (scaleByPixel * scaleByPixel) / 2.0;

    CABasicAnimation* animation = [CABasicAnimation animationWithKeyPath:@"filters.CIZoomBlur.inputAmount"];
    animation.fromValue = @(peakZoomBlurAmount);

    animation.toValue = @(0.0);

    const double phaseLength = 60.0 / tempo;

    animation.repeatCount = 1.0f;
    animation.autoreverses = NO;
    animation.duration = phaseLength;
    animation.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut];
    animation.fillMode = kCAFillModeBoth;
    animation.removedOnCompletion = NO;

    [layer addAnimation:animation forKey:@"beatScaling"];
}

- (void)beatEffect:(NSNotification*)notification
{
    const NSDictionary* dict = notification.object;

    // Bomb the bass!
    [self beatPumpingLayer:_imageView.layer
                     tempo:[dict[kBeatNotificationKeyTempo] doubleValue]
               localEnergy:[dict[kBeatNotificationKeyLocalEnergy] doubleValue]
               totalEnergy:[dict[kBeatNotificationKeyTotalEnergy] doubleValue]];
}

@end
