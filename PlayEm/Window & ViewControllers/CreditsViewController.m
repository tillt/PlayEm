//
//  CreditsViewController.m
//  PlayEm
//
//  Created by Till Toenshoff on 8/23/25.
//  Copyright © 2025 Till Toenshoff. All rights reserved.
//

#import "CreditsViewController.h"
#import "../Defaults.h"

static const CGFloat kBigFontSize = 50.0f;
static const CGFloat kNormalFontSize = 13.0f;
static const CGFloat kSmallFontSize = 10.0f;


@interface CreditsViewController ()
{
    NSInteger _bottomIndex;
    unsigned long long _offset;
}

@property (strong, nonatomic) NSTimer* timer;
@property (strong, nonatomic) NSTextView* creditsView;

@end

@implementation CreditsViewController

-(id)infoValueForKey:(NSString*)key
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
    const CGFloat totalHeight = scrolloHeight + 100.0f;

    const NSRect rect = NSMakeRect(0,0,totalWidth,totalHeight);
    NSView* view = [[NSView alloc] initWithFrame:rect];

    NSRect imageRect = NSMakeRect(0, 10.0f,imageWidth,imageWidth);
    NSImageView* imageView = [[NSImageView alloc] initWithFrame:imageRect];
    imageView.image = [NSImage imageNamed:@"AppIcon"];
    [view addSubview:imageView];
    
    const CGFloat x = imageWidth;
    const CGFloat fieldWidth = view.frame.size.width - (imageWidth + 40.0);
    CGFloat y = view.frame.size.height - (kBigFontSize + 20.0);

    NSString* name = [self infoValueForKey:@"CFBundleName"];
    NSTextField* textField = [NSTextField textFieldWithString:name];
    textField.bordered = NO;
    textField.textColor = [[Defaults sharedDefaults] lightBeamColor];
    textField.font = [NSFont fontWithName:@"DIN Condensed" size:kBigFontSize];
    textField.drawsBackground = NO;
    textField.editable = NO;
    textField.selectable = NO;
    textField.cell.truncatesLastVisibleLine = YES;
    textField.cell.lineBreakMode = NSLineBreakByTruncatingTail;
    textField.alignment = NSTextAlignmentLeft;
    textField.frame = NSMakeRect(x,
                                 y,
                                 fieldWidth,
                                 kBigFontSize + 10);
    [view addSubview:textField];

    y -= 2;

    NSString* version = [NSString stringWithFormat:@"Version %@ (%@)",
                         [self infoValueForKey:@"CFBundleShortVersionString"],
                         [self infoValueForKey:@"CFBundleVersion"]];

    textField = [NSTextField textFieldWithString:version];
    textField.bordered = NO;
    textField.textColor = [[Defaults sharedDefaults] secondaryLabelColor];
    textField.font = [NSFont systemFontOfSize:kNormalFontSize];
    textField.drawsBackground = NO;
    textField.editable = NO;
    textField.selectable = NO;
    textField.cell.truncatesLastVisibleLine = YES;
    textField.cell.lineBreakMode = NSLineBreakByTruncatingTail;
    textField.alignment = NSTextAlignmentLeft;
    textField.frame = NSMakeRect(x,
                                 y,
                                 fieldWidth,
                                 kNormalFontSize + 5);
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
    textField.frame = NSMakeRect(x,
                                 y,
                                 fieldWidth,
                                 kSmallFontSize + 5);
    [view addSubview:textField];
    
    NSRect scrollRect = NSMakeRect(200,0,scrolloWidth,scrolloHeight);

    NSScrollView* scrollView = [NSTextView scrollableTextView];
    scrollView.frame = scrollRect;
    scrollView.automaticallyAdjustsContentInsets = NO;
    
    _creditsView = scrollView.documentView;
    _creditsView.backgroundColor = [NSColor clearColor];
    _creditsView.editable = NO;

    NSURL* url = [[NSBundle mainBundle]URLForResource:@"credits" withExtension:@"rtf"];
    NSData* data = [NSData dataWithContentsOfURL:url];

    NSAttributedString *attributedString = [[NSAttributedString alloc] initWithData:data
                                                                      options:@{NSDocumentTypeDocumentAttribute: NSRTFTextDocumentType, NSCharacterEncodingDocumentAttribute: @(NSUTF8StringEncoding)}
                                                           documentAttributes:nil
                                                                        error:nil];

    if (attributedString == nil) {
        NSLog(@"failed loading that markdown file");
        return;
    }

    NSLog(@"attributedString height %f", attributedString.size.height);
    [_creditsView.textStorage appendAttributedString:attributedString];
    _creditsView.frame = NSMakeRect(0, 0,scrollRect.size.width, attributedString.size.height);
    
    [view addSubview:scrollView];
    self.view = view;
}

- (void)viewWillAppear {
    [super viewWillAppear];

    // Make sure there is no ongoing animation.
    NSClipView* clipView = [_creditsView.enclosingScrollView contentView];
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext* context) {
        [context setDuration:0.0f];
        [context setTimingFunction:[CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionLinear]];
        [clipView setBoundsOrigin:CGPointMake(0.0, 0.0)];
    }];
}

- (void)viewDidAppear {
    [super viewDidAppear];

    CreditsViewController* __weak weakSelf = self;
    
    // After some time, check if the user scrolled at all - if not, scroll through credits
    // slowly, then scroll back fast and signal `ready` for user.
    self.timer = [NSTimer scheduledTimerWithTimeInterval:5.0f
                                                 repeats:NO
                                                   block:^(NSTimer* timer){
        NSClipView* clipView = [weakSelf.creditsView.enclosingScrollView contentView];
        NSPoint origin = [clipView bounds].origin;
        if (origin.y != 0.0) {
            return;
        }
        origin.y += weakSelf.creditsView.frame.size.height;
        [NSAnimationContext runAnimationGroup:^(NSAnimationContext* context) {
            [context setDuration:30.0f];
            [context setTimingFunction:[CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionLinear]];
            [clipView.animator setBoundsOrigin:origin];
        } completionHandler:^{
            [NSAnimationContext runAnimationGroup:^(NSAnimationContext* context) {
                [context setDuration:3.0f];
                [context setTimingFunction:[CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut]];
                [clipView.animator setBoundsOrigin:CGPointMake(0.0, 0.0)];
            } completionHandler:^{
                [weakSelf.creditsView.enclosingScrollView flashScrollers];
            }];
        }];
    }];
}

#pragma mark Layer delegate

@end
