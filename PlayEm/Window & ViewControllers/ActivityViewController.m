//
//  ActivityViewController.m
//  PlayEm
//
//  Created by Till Toenshoff on 12/28/25.
//  Copyright © 2025 Till Toenshoff. All rights reserved.
//

#import "ActivityViewController.h"

#import <QuartzCore/QuartzCore.h>

#import "ActivityManager.h"
#import "Defaults.h"

NS_ASSUME_NONNULL_BEGIN

static NSString* const kTitleColumnIdentifier = @"TitleColumn";
static NSString* const kProgressColumnIdentifier = @"ProgressColumn";
static NSString* const kCancelButtonIdentifier = @"CancelButton";
static NSString* const kCancelButtonViewIdentifier = @"CancelButtonControl";
static const CGFloat kRowHeight = 60.0;
static const CGFloat kCancelColumnWidth = 32.0;
static const CGFloat kProgressColumnPadding = 8.0;
static const BOOL kActivityDebugLogging = NO;

@interface CircleProgressView : NSView
@property (nonatomic, assign) double progress;  // 0...1
- (void)setProgress:(double)progress animated:(BOOL)animated;
@property (nonatomic, strong, nullable) NSUUID* tokenUUID;
@end

@implementation CircleProgressView {
    CAShapeLayer* _bgLayer;
    CAShapeLayer* _fgLayer;
}

- (instancetype)initWithFrame:(NSRect)frameRect
{
    self = [super initWithFrame:frameRect];
    if (self) {
        self.wantsLayer = YES;
        self.accessibilityRole = NSAccessibilityProgressIndicatorRole;
        self.accessibilityLabel = @"Activity progress";
        self.accessibilityMinValue = @0;
        self.accessibilityMaxValue = @100;

        _bgLayer = [CAShapeLayer layer];
        _bgLayer.lineWidth = 3.0;
        _bgLayer.fillColor = NSColor.clearColor.CGColor;
        _bgLayer.strokeColor = NSColor.tertiaryLabelColor.CGColor;
        [self.layer addSublayer:_bgLayer];

        _fgLayer = [CAShapeLayer layer];
        _fgLayer.lineWidth = 3.0;
        _fgLayer.fillColor = NSColor.clearColor.CGColor;
        _fgLayer.strokeColor = NSColor.whiteColor.CGColor;
        _fgLayer.lineCap = kCALineCapRound;
        _fgLayer.strokeEnd = 0.0;
        [self.layer addSublayer:_fgLayer];
    }
    return self;
}

- (BOOL)isFlipped
{
    return YES;
}

- (void)layout
{
    [super layout];
    [self updatePaths];
}

- (void)updatePaths
{
    const CGFloat inset = 5.0 + (_fgLayer.lineWidth / 2.0);
    CGRect b = self.bounds;
    CGRect circle = CGRectInset(b, inset, inset);
    CGPoint center = CGPointMake(CGRectGetMidX(circle), CGRectGetMidY(circle));
    CGFloat radius = MIN(circle.size.width, circle.size.height) / 2.0;
    CGMutablePathRef p = CGPathCreateMutable();
    CGPathAddArc(p, NULL, center.x, center.y, radius, -M_PI_2, -M_PI_2 + 2 * M_PI,
                 false);  // start at top
    _bgLayer.frame = b;
    _fgLayer.frame = b;
    _bgLayer.path = p;
    _fgLayer.path = p;
    CGPathRelease(p);
}

- (void)setProgress:(double)progress
{
    [self setProgress:progress animated:YES];
}

- (void)setProgress:(double)progress animated:(BOOL)animated
{
    CGFloat clamped = (CGFloat) MIN(1.0, MAX(0.0, progress));
    if (clamped == _progress) {
        return;
    }
    _progress = clamped;
    self.accessibilityValue = @(_progress * 100.0);

    [CATransaction begin];
    if (!animated) {
        [CATransaction setDisableActions:YES];
    } else {
        [CATransaction setAnimationDuration:0.8];
        [CATransaction setAnimationTimingFunction:[CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut]];
    }
    _fgLayer.strokeEnd = _progress;
    [CATransaction commit];
}

- (BOOL)accessibilityIsIgnored
{
    return NO;
}

@end

// While neat in isolation, this doesnt play well with the table view
// animations. It appears the table-view reload animations totally trash all
// timing - even if done carefully (not globally as in `reloadData`).
@interface ArcSpinnerView : NSView
@property (nonatomic, assign) BOOL spinning;
@property (nonatomic, assign) BOOL wasIndeterminate;
@end

@implementation ArcSpinnerView {
    CAShapeLayer* _arcLayer;
}

- (instancetype)initWithFrame:(NSRect)frameRect
{
    self = [super initWithFrame:frameRect];
    if (self) {
        self.wantsLayer = YES;
        self.layer.anchorPoint = CGPointMake(0.5, 0.5);

        CAShapeLayer* background = [CAShapeLayer layer];
        background.lineWidth = 3.0;
        background.fillColor = NSColor.clearColor.CGColor;
        background.strokeColor = NSColor.tertiaryLabelColor.CGColor;
        background.frame = self.bounds;
        background.autoresizingMask = kCALayerWidthSizable | kCALayerHeightSizable;
        background.speed = 1.0;
        [self.layer addSublayer:background];

        _arcLayer = [CAShapeLayer layer];
        _arcLayer.lineWidth = 3.0;
        _arcLayer.fillColor = NSColor.clearColor.CGColor;
        _arcLayer.strokeColor = NSColor.whiteColor.CGColor;
        _arcLayer.lineCap = kCALineCapRound;
        _arcLayer.speed = 1.0;
        [self.layer addSublayer:_arcLayer];
        [self updatePath];
    }
    return self;
}

- (void)layout
{
    [super layout];
    [self updatePath];
}

- (void)updatePath
{
    CGRect b = self.bounds;
    CGFloat inset = 6.0;
    CGRect circle = CGRectInset(b, inset, inset);
    CGPoint center = CGPointMake(CGRectGetMidX(circle), CGRectGetMidY(circle));
    CGFloat radius = MIN(circle.size.width, circle.size.height) / 2.0;
    CGMutablePathRef p = CGPathCreateMutable();
    CGPathAddArc(p, NULL, center.x, center.y, radius, -M_PI_2, -M_PI_2 + 2 * M_PI,
                 false);  // start at top
    CGPathRef path = CGPathCreateCopy(p);
    _arcLayer.path = path;
    _arcLayer.frame = b;
    // update the background ring to the same path
    if (self.layer.sublayers.count > 0) {
        CAShapeLayer* background = (CAShapeLayer*) self.layer.sublayers.firstObject;
        background.path = path;
        background.frame = b;
    }
    CGPathRelease(path);
    CGPathRelease(p);
}

- (void)setSpinning:(BOOL)spinning
{
    _spinning = spinning;
    if (spinning) {
        // Ensure a clean slate so timing isn’t compounded when views are
        // reused/relayed out.
        [_arcLayer removeAllAnimations];
        if ([_arcLayer animationForKey:@"spin"] == nil) {
            CABasicAnimation* spin = [CABasicAnimation animationWithKeyPath:@"transform.rotation.z"];
            spin.fromValue = @(0);
            spin.toValue = @(2 * M_PI);
            spin.duration = 1.0;
            spin.repeatCount = HUGE_VALF;
            spin.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionLinear];
            spin.beginTime = CACurrentMediaTime();
            [_arcLayer addAnimation:spin forKey:@"spin"];

            CAKeyframeAnimation* head = [CAKeyframeAnimation animationWithKeyPath:@"strokeStart"];
            head.values = @[ @0.0, @0.25, @0.9 ];
            head.keyTimes = @[ @0.0, @0.5, @1.0 ];
            head.duration = 1.2;
            head.repeatCount = HUGE_VALF;
            head.timingFunctions = @[
                [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut],
                [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut]
            ];
            head.beginTime = CACurrentMediaTime();
            [_arcLayer addAnimation:head forKey:@"head"];

            CAKeyframeAnimation* tail = [CAKeyframeAnimation animationWithKeyPath:@"strokeEnd"];
            tail.values = @[ @0.1, @1.0, @1.0 ];
            tail.keyTimes = @[ @0.0, @0.6, @1.0 ];
            tail.duration = 1.2;
            tail.repeatCount = HUGE_VALF;
            tail.timingFunctions = @[
                [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut],
                [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut]
            ];
            tail.beginTime = CACurrentMediaTime();
            [_arcLayer addAnimation:tail forKey:@"tail"];
        }
        _arcLayer.strokeStart = 0.0;
        _arcLayer.strokeEnd = 0.1;
    } else {
        [_arcLayer removeAllAnimations];
    }
}

@end

@interface ActivityViewController ()
@property (nonatomic, strong) NSTableView* table;
@property (nonatomic, assign) CGFloat spinnerSide;
@property (nonatomic, assign) CGFloat progressColumnWidth;
@property (nonatomic, assign) NSUInteger lastRowCount;
@end

@implementation ActivityViewController

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(activitiesUpdated:) name:ActivityManagerDidUpdateNotification object:nil];
}

#pragma mark - View lifecycle

- (void)loadView
{
    const NSAutoresizingMaskOptions kViewFullySizeable = NSViewHeightSizable | NSViewWidthSizable;

    NSView* view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 340, 240)];
    const CGFloat kTitleColumnWidth = view.frame.size.width - 86.0;

    // Measure the native spinner size for the chosen control size and give it
    // breathing room.
    NSProgressIndicator* measure = [[NSProgressIndicator alloc] initWithFrame:NSZeroRect];
    measure.style = NSProgressIndicatorStyleSpinning;
    measure.controlSize = NSControlSizeRegular;
    [measure sizeToFit];
    _spinnerSide = ceil(MAX(measure.fittingSize.width, measure.fittingSize.height)) - 2.0;  // slightly smaller than default
    _progressColumnWidth = _spinnerSide + kProgressColumnPadding;                           // small padding inside the column

    NSScrollView* scrollView = [[NSScrollView alloc] initWithFrame:view.bounds];
    scrollView.autoresizingMask = kViewFullySizeable;
    scrollView.drawsBackground = NO;

    _table = [[NSTableView alloc] initWithFrame:NSZeroRect];
    _table.delegate = self;
    _table.dataSource = self;
    _table.rowHeight = kRowHeight;
    _table.backgroundColor = [NSColor clearColor];
    _table.headerView = nil;
    _table.autoresizingMask = kViewFullySizeable;
    _table.columnAutoresizingStyle = NSTableViewNoColumnAutoresizing;
    _table.intercellSpacing = NSMakeSize(0.0, 0.0);  // tighter spacing between fixed-width columns

    NSTableColumn* titleColumn = [[NSTableColumn alloc] init];
    titleColumn.identifier = kTitleColumnIdentifier;
    titleColumn.width = kTitleColumnWidth;
    titleColumn.minWidth = kTitleColumnWidth;
    titleColumn.maxWidth = kTitleColumnWidth;
    titleColumn.resizingMask = NSTableColumnNoResizing;
    [_table addTableColumn:titleColumn];

    NSTableColumn* progressColumn = [[NSTableColumn alloc] init];
    progressColumn.identifier = kProgressColumnIdentifier;
    progressColumn.width = _progressColumnWidth;
    progressColumn.minWidth = _progressColumnWidth;
    progressColumn.maxWidth = _progressColumnWidth;
    progressColumn.resizingMask = NSTableColumnNoResizing;
    [_table addTableColumn:progressColumn];

    NSTableColumn* cancelColumn = [[NSTableColumn alloc] init];
    cancelColumn.identifier = kCancelButtonIdentifier;
    cancelColumn.width = kCancelColumnWidth;
    cancelColumn.minWidth = kCancelColumnWidth;
    cancelColumn.maxWidth = kCancelColumnWidth;
    cancelColumn.resizingMask = NSTableColumnNoResizing;
    [_table addTableColumn:cancelColumn];

    scrollView.documentView = _table;
    [view addSubview:scrollView];

    self.view = view;
    _lastRowCount = [ActivityManager shared].activities.count;
}

#pragma mark - NSTableViewDataSource

- (NSInteger)numberOfRowsInTableView:(NSTableView*)tableView
{
    return [ActivityManager shared].activities.count;
}

#pragma mark - NSTableViewDelegate

- (nullable NSView*)tableView:(NSTableView*)tableView viewForTableColumn:(nullable NSTableColumn*)tableColumn row:(NSInteger)row
{
    if (tableColumn == nil) {
        return nil;
    }

    ActivityEntry* entry = [ActivityManager shared].activities[(NSUInteger) row];
    NSString* identifier = tableColumn.identifier;
    const CGFloat paddingH = 0.0;
    const CGFloat paddingV = 0.0;
    const CGFloat progressSize = self.spinnerSide;

    if ([identifier isEqualToString:kTitleColumnIdentifier]) {
        NSView* view = [[NSView alloc] initWithFrame:NSMakeRect(0.0, 0.0, tableColumn.width, tableView.rowHeight)];
        view.identifier = identifier;

        const CGFloat titleHeight = 20.0;
        const CGFloat detailHeight = 16.0;

        NSTextField* titleField = [[NSTextField alloc] initWithFrame:NSMakeRect(paddingH, tableView.rowHeight - paddingV - titleHeight - 4.0, tableColumn.width - (paddingV * 2), titleHeight)];
        titleField.editable = NO;
        titleField.bordered = NO;
        titleField.drawsBackground = NO;
        // Use normal size for the title per updated style.
        titleField.font = [[Defaults sharedDefaults] normalFont];
        titleField.lineBreakMode = NSLineBreakByTruncatingTail;
        titleField.identifier = @"title";
        titleField.stringValue = entry.title;
        [view addSubview:titleField];

        const CGFloat detailYOffset = detailHeight + 4.0;  // tuck much closer to the title
        NSTextField* detailField = [[NSTextField alloc] initWithFrame:NSMakeRect(paddingH, detailYOffset, tableColumn.width - (paddingV * 2), detailHeight)];
        detailField.editable = NO;
        detailField.bordered = NO;
        detailField.drawsBackground = NO;
        // Use small font for the description.
        detailField.font = [[Defaults sharedDefaults] smallFont];
        detailField.textColor = [NSColor secondaryLabelColor];
        detailField.lineBreakMode = NSLineBreakByTruncatingTail;
        detailField.identifier = @"detail";
        detailField.stringValue = entry.detail ?: (entry.completed ? @"Done" : @"");
        [view addSubview:detailField];

        return view;
    } else if ([identifier isEqualToString:kProgressColumnIdentifier]) {
        NSView* view = [[NSView alloc] initWithFrame:NSMakeRect(0.0, 0.0, tableColumn.width, tableView.rowHeight)];
        view.identifier = identifier;

        ArcSpinnerView* spinner = [[ArcSpinnerView alloc] initWithFrame:NSMakeRect(0, 0, progressSize, progressSize)];
        spinner.identifier = @"spinner";
        [view addSubview:spinner];

        CircleProgressView* circle = [[CircleProgressView alloc] initWithFrame:NSMakeRect(0, 0, progressSize, progressSize)];
        circle.identifier = @"circle";
        circle.tokenUUID = entry.token.uuid;
        [view addSubview:circle];

        const CGFloat progressY = round((tableView.rowHeight - progressSize) / 2.0) + 10.0;
        const CGFloat progressX = round((tableColumn.width - progressSize) / 2.0);
        spinner.frame = NSMakeRect(progressX, progressY, progressSize, progressSize);
        circle.frame = NSMakeRect(progressX, progressY, progressSize, progressSize);

        [self configureProgressIndicatorSpinner:spinner circle:circle entry:entry];

        return view;
    } else if ([identifier isEqualToString:kCancelButtonIdentifier]) {
        NSView* view = [[NSView alloc] initWithFrame:NSMakeRect(0.0, 0.0, tableColumn.width, tableView.rowHeight)];
        view.identifier = identifier;

        const CGFloat cancelSize = 20.0;
        const CGFloat cancelY = round((tableView.rowHeight - cancelSize) / 2.0) + 10.0;
        const CGFloat cancelX = round((tableColumn.width - cancelSize) / 2.0) - 8.0;
        NSButton* cancelButton = [NSButton buttonWithTitle:@"" target:self action:@selector(cancelButtonPressed:)];

        NSImageSymbolConfiguration* baseConfig = [NSImageSymbolConfiguration configurationWithPointSize:18 weight:NSFontWeightBold];
        NSImageSymbolConfiguration* palette =
            [NSImageSymbolConfiguration configurationWithPaletteColors:@[ [NSColor labelColor], [NSColor tertiaryLabelColor] ]];
        NSImageSymbolConfiguration* config = [baseConfig configurationByApplyingConfiguration:palette];

        NSImage* closeImage = [NSImage imageWithSystemSymbolName:@"xmark.circle.fill" accessibilityDescription:@"Cancel"];
        closeImage = [closeImage imageWithSymbolConfiguration:config];

        cancelButton.image = closeImage;
        cancelButton.imagePosition = NSImageOnly;
        cancelButton.bezelStyle = NSBezelStyleToolbar;
        cancelButton.controlSize = NSControlSizeSmall;
        cancelButton.identifier = kCancelButtonViewIdentifier;
        // Fire on mouse-down so frequent table reloads can’t eat the click before
        // mouse-up.
        [[cancelButton cell] sendActionOn:NSEventMaskLeftMouseDown];
        cancelButton.tag = row;
        cancelButton.enabled = entry.cancellable;
        cancelButton.hidden = !entry.cancellable;
        cancelButton.frame = NSMakeRect(cancelX, cancelY, cancelSize, cancelSize);
        [view addSubview:cancelButton];
        return view;
    }

    return nil;
}

- (CGFloat)tableView:(NSTableView*)tableView heightOfRow:(NSInteger)row
{
    return kRowHeight;
}

- (void)viewDidLayout
{
    [super viewDidLayout];
}

#pragma mark - Actions

- (void)cancelButtonPressed:(id)sender
{
    NSButton* button = (NSButton*) sender;
    NSInteger row = [self.table rowForView:button];
    if (row < 0 || (NSUInteger) row >= [ActivityManager shared].activities.count) {
        return;
    }
    ActivityEntry* entry = [ActivityManager shared].activities[(NSUInteger) row];
    [[ActivityManager shared] requestCancel:entry.token];
}

#pragma mark - Notifications

- (void)activitiesUpdated:(NSNotification*)note
{
    NSUInteger newCount = [ActivityManager shared].activities.count;
    if (kActivityDebugLogging) {
        NSLog(@"[ActivityVC] activitiesUpdated old:%lu new:%lu", (unsigned long) self.lastRowCount, (unsigned long) newCount);
    }

    NSMutableIndexSet* removes = [NSMutableIndexSet indexSet];
    NSMutableIndexSet* inserts = [NSMutableIndexSet indexSet];

    if (newCount < self.lastRowCount) {
        NSRange range = NSMakeRange(newCount, self.lastRowCount - newCount);
        [removes addIndexesInRange:range];
    } else if (newCount > self.lastRowCount) {
        NSRange range = NSMakeRange(self.lastRowCount, newCount - self.lastRowCount);
        [inserts addIndexesInRange:range];
    }

    if (newCount == self.lastRowCount) {
        NSIndexSet* allRows = [NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, newCount)];
        NSIndexSet* allCols = [NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, self.table.tableColumns.count)];
        [self.table reloadDataForRowIndexes:allRows columnIndexes:allCols];
    } else {
        [self.table beginUpdates];
        if (removes.count > 0) {
            // Slide out (to the right) with a light fade so disappearing rows are
            // visually obvious.
            [self.table removeRowsAtIndexes:removes withAnimation:(NSTableViewAnimationEffectFade)];
            if (kActivityDebugLogging) {
                NSLog(@"[ActivityVC] remove rows: %@", removes);
            }
        }
        if (inserts.count > 0) {
            [self.table insertRowsAtIndexes:inserts withAnimation:NSTableViewAnimationEffectFade];
            if (kActivityDebugLogging) {
                NSLog(@"[ActivityVC] insert rows: %@", inserts);
            }
        }
        [self.table endUpdates];
        self.lastRowCount = newCount;
    }
}

- (void)configureProgressIndicatorSpinner:(ArcSpinnerView*)spinner circle:(CircleProgressView*)circle entry:(ActivityEntry*)entry
{
    BOOL sameToken = [circle.tokenUUID isEqual:entry.token.uuid];
    circle.tokenUUID = entry.token.uuid;

    BOOL indeterminate = (entry.progress < 0.0 && !entry.completed);

    spinner.hidden = !indeterminate;
    circle.hidden = indeterminate;

    if (indeterminate) {
        spinner.spinning = YES;
        spinner.wasIndeterminate = YES;
    } else {
        spinner.spinning = NO;
        spinner.wasIndeterminate = NO;
        [circle setProgress:entry.completed ? 1.0 : entry.progress animated:sameToken];
    }
}

- (NSView*)subviewWithIdentifier:(NSString*)identifier inView:(NSView*)view matchingClass:(Class)cls
{
    if (identifier.length == 0 || view == nil) {
        return nil;
    }
    if ([view.identifier isEqualToString:identifier] && (cls == Nil || [view isKindOfClass:cls])) {
        return view;
    }
    for (NSView* child in view.subviews) {
        NSView* found = [self subviewWithIdentifier:identifier inView:child matchingClass:cls];
        if (found != nil) {
            return found;
        }
    }
    return nil;
}

@end

NS_ASSUME_NONNULL_END
