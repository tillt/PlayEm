//
//  FXViewController.m
//  PlayEm
//
//  Created by Till Toenshoff on 01/07/26.
//  Copyright © 2026 Till Toenshoff. All rights reserved.
//

#import "FXViewController.h"

#import "../Defaults.h"
#import "AudioController.h"
#import "Defaults.h"

@interface FXViewController ()
@property (nonatomic, strong) AudioController* audioController;
@property (nonatomic, strong) NSView* content;
@property (nonatomic, strong) NSPopUpButton* effectMenu;
@property (nonatomic, strong) NSTextField* effectLabel;
@property (nonatomic, strong) NSArray<NSDictionary*>* effects;
@property (nonatomic, strong) NSStackView* rootStack;
@property (nonatomic, strong) NSStackView* paramsStack;
@end

@implementation FXViewController

- (instancetype)initWithAudioController:(AudioController*)audioController
{
    NSPanel* panel = [[NSPanel alloc] initWithContentRect:NSMakeRect(0, 0, 380, 200)
                                                styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskUtilityWindow)
                                                  backing:NSBackingStoreBuffered
                                                    defer:NO];
    self = [super initWithWindow:panel];
    if (self) {
        _audioController = audioController;
        _effects = @[];
        panel.floatingPanel = YES;
        panel.level = NSFloatingWindowLevel;
        panel.becomesKeyOnlyIfNeeded = YES;
        panel.hidesOnDeactivate = YES;
        panel.collectionBehavior = NSWindowCollectionBehaviorTransient;
        [self buildUI];
    }
    return self;
}

- (void)setAudioController:(AudioController*)audioController
{
    _audioController = audioController;
    [self reloadParameterControls];
}

- (void)buildUI
{
    self.content = [[NSView alloc] initWithFrame:self.window.contentView.bounds];
    self.content.translatesAutoresizingMaskIntoConstraints = NO;
    self.window.contentView = self.content;

    self.rootStack = [[NSStackView alloc] initWithFrame:NSZeroRect];
    self.rootStack.orientation = NSUserInterfaceLayoutOrientationVertical;
    self.rootStack.alignment = NSLayoutAttributeLeading;
    self.rootStack.spacing = 8.0;
    self.rootStack.edgeInsets = NSEdgeInsetsMake(10.0, 10.0, 10.0, 10.0);
    self.rootStack.translatesAutoresizingMaskIntoConstraints = NO;
    [self.content addSubview:self.rootStack];

    NSLayoutConstraint* rootTop = [self.rootStack.topAnchor constraintEqualToAnchor:self.content.topAnchor];
    NSLayoutConstraint* rootLeading = [self.rootStack.leadingAnchor constraintEqualToAnchor:self.content.leadingAnchor];
    NSLayoutConstraint* rootTrailing = [self.rootStack.trailingAnchor constraintEqualToAnchor:self.content.trailingAnchor];
    NSLayoutConstraint* rootBottom = [self.rootStack.bottomAnchor constraintEqualToAnchor:self.content.bottomAnchor];
    [NSLayoutConstraint activateConstraints:@[ rootTop, rootLeading, rootTrailing, rootBottom ]];

    // Header row
    self.effectLabel = [NSTextField labelWithString:@"Effect"];
    self.effectLabel.font = [[Defaults sharedDefaults] smallFont];
    [self.effectLabel.widthAnchor constraintEqualToConstant:60.0].active = YES;
    [self.effectLabel.heightAnchor constraintEqualToConstant:20.0].active = YES;

    self.effectMenu = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    self.effectMenu.target = self;
    self.effectMenu.action = @selector(effectChanged:);
    self.effectMenu.translatesAutoresizingMaskIntoConstraints = NO;
    [self.effectMenu.heightAnchor constraintEqualToConstant:24.0].active = YES;

    NSStackView* header = [NSStackView stackViewWithViews:@[ self.effectLabel, self.effectMenu ]];
    header.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    header.alignment = NSLayoutAttributeCenterY;
    header.spacing = 10.0;
    header.translatesAutoresizingMaskIntoConstraints = NO;
    [self.rootStack addArrangedSubview:header];

    self.paramsStack = [[NSStackView alloc] initWithFrame:NSZeroRect];
    self.paramsStack.orientation = NSUserInterfaceLayoutOrientationVertical;
    self.paramsStack.alignment = NSLayoutAttributeLeading;
    self.paramsStack.spacing = 6.0;
    self.paramsStack.translatesAutoresizingMaskIntoConstraints = NO;
    [self.rootStack addArrangedSubview:self.paramsStack];

    [self updateEffects:@[]];
}

- (void)showWithParent:(NSWindow*)parent
{
    if (parent != nil) {
        [self.window center];
        [self.window makeKeyAndOrderFront:parent];
    } else {
        [self.window makeKeyAndOrderFront:nil];
    }
}

- (void)selectEffectIndex:(NSInteger)index
{
    if (index >= 0 && index < (NSInteger) self.effectMenu.numberOfItems) {
        [self.effectMenu selectItemAtIndex:index];
    } else {
        [self.effectMenu selectItem:nil];
    }
}

- (void)updateEffects:(NSArray<NSDictionary*>*)effects
{
    self.effects = effects ?: @[];
    [self.effectMenu removeAllItems];
    for (NSDictionary* entry in self.effects) {
        NSString* name = entry[@"name"];
        NSNumber* subtype = entry[@"subtype"];
        NSString* title = (name && name.length > 0) ? name : [NSString stringWithFormat:@"0x%08x", subtype.unsignedIntValue];
        [self.effectMenu addItemWithTitle:title];
    }
    [self selectEffectIndex:self.audioController.currentEffectIndex];
    [self reloadParameterControls];
}

- (void)effectChanged:(id)sender
{
    NSInteger idx = self.effectMenu.indexOfSelectedItem;
    if (idx < 0) {
        return;
    }
    AudioComponentDescription desc = {0};
    if (idx >= 0 && idx < (NSInteger) self.effects.count) {
        NSDictionary* entry = self.effects[(NSUInteger) idx];
        NSValue* packed = entry[@"component"];
        if (packed != nil && strcmp([packed objCType], @encode(AudioComponentDescription)) == 0) {
            [packed getValue:&desc];
        }
    }
    [self.audioController selectEffectWithDescription:desc indexHint:idx];
    [self reloadParameterControls];
    [self applyStoredParametersForCurrentEffect];
    if (self.effectSelectionChanged != nil) {
        self.effectSelectionChanged(idx);
    }
}

- (void)applyCurrentSelection
{
    if (self.effectMenu.indexOfSelectedItem >= 0) {
        [self effectChanged:self.effectMenu];
    }
}

- (void)hide
{
    [self.window orderOut:nil];
}

- (void)reloadParameterControls
{
    while (self.paramsStack.arrangedSubviews.count > 0) {
        NSView* v = self.paramsStack.arrangedSubviews.lastObject;
        [self.paramsStack removeArrangedSubview:v];
        [v removeFromSuperview];
    }

    if (self.audioController.currentEffectIndex < 0) {
        NSTextField* disabled = [NSTextField labelWithString:@"Effect disabled."];
        disabled.font = [[Defaults sharedDefaults] smallFont];
        [self.paramsStack addArrangedSubview:disabled];
        [self adjustWindowToFitContent];
        return;
    }

    NSDictionary<NSNumber*, NSDictionary*>* info = [self.audioController effectParameterInfo];
    if (info.count == 0) {
        NSTextField* none = [NSTextField labelWithString:@"No adjustable parameters."];
        none.font = [[Defaults sharedDefaults] smallFont];
        [self.paramsStack addArrangedSubview:none];
        [self adjustWindowToFitContent];
        return;
    }

    NSArray<NSNumber*>* keys = [[info allKeys] sortedArrayUsingSelector:@selector(compare:)];
    CGFloat nameWidth = 130.0;
    CGFloat valueWidth = 90.0;
    CGFloat spacing = 6.0;

    for (NSNumber* key in keys) {
        NSDictionary* meta = info[key];
        NSString* name = meta[@"name"] ?: @"";
        if (name.length == 0) {
            name = [NSString stringWithFormat:@"Param %@", key];
        }
        double min = [meta[@"min"] doubleValue];
        double max = [meta[@"max"] doubleValue];
        double current = meta[@"current"] ? [meta[@"current"] doubleValue] : [meta[@"default"] doubleValue];
        AudioUnitParameterUnit unit = (AudioUnitParameterUnit)[meta[@"unit"] unsignedIntValue];

        NSStackView* row = [NSStackView stackViewWithViews:@[]];
        row.orientation = NSUserInterfaceLayoutOrientationHorizontal;
        row.alignment = NSLayoutAttributeCenterY;
        row.distribution = NSStackViewDistributionFill;
        row.spacing = spacing;
        row.translatesAutoresizingMaskIntoConstraints = NO;

        NSTextField* nameField = [NSTextField labelWithString:name];
        nameField.font = [[Defaults sharedDefaults] smallFont];
        nameField.lineBreakMode = NSLineBreakByTruncatingTail;
        [nameField.widthAnchor constraintEqualToConstant:nameWidth].active = YES;
        [nameField.heightAnchor constraintEqualToConstant:20.0].active = YES;

        NSSlider* slider = [[NSSlider alloc] initWithFrame:NSZeroRect];
        slider.minValue = min;
        slider.maxValue = max;
        slider.doubleValue = current;
        slider.target = self;
        slider.trackFillColor = [NSColor labelColor];
        slider.action = @selector(parameterChanged:);
        slider.tag = (NSInteger) key.unsignedIntValue;
        slider.translatesAutoresizingMaskIntoConstraints = NO;
        slider.controlSize = NSControlSizeMini;
        [slider setContentHuggingPriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
        [slider setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
        [slider.heightAnchor constraintEqualToConstant:16.0].active = YES;
        [slider.widthAnchor constraintGreaterThanOrEqualToConstant:110.0].active = YES;

        NSString* unitText = [self displayUnitFor:unit];
        NSString* valueString = unitText.length > 0 ? [NSString stringWithFormat:@"%.2f %@", current, unitText] : [NSString stringWithFormat:@"%.2f", current];
        NSTextField* valueField = [NSTextField labelWithString:valueString];
        valueField.font = [[Defaults sharedDefaults] smallFont];
        valueField.alignment = NSTextAlignmentRight;
        valueField.tag = slider.tag;
        valueField.identifier = @"valueLabel";
        valueField.toolTip = unitText;
        [valueField setContentHuggingPriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];
        [valueField setContentCompressionResistancePriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];
        [valueField.widthAnchor constraintEqualToConstant:valueWidth].active = YES;
        [valueField.heightAnchor constraintEqualToConstant:20.0].active = YES;

        [row addArrangedSubview:nameField];
        [row addArrangedSubview:slider];
        [row addArrangedSubview:valueField];

        [self.paramsStack addArrangedSubview:row];
    }
    [self adjustWindowToFitContent];
}

- (void)parameterChanged:(id)sender
{
    if (![sender isKindOfClass:[NSSlider class]]) {
        return;
    }
    NSSlider* slider = (NSSlider*) sender;
    AudioUnitParameterID param = (AudioUnitParameterID) slider.tag;
    AudioUnitParameterValue value = (AudioUnitParameterValue) slider.doubleValue;
    [self.audioController setEffectParameter:param value:value];
    [self persistParameter:param value:value];
    for (NSView* v in self.paramsStack.arrangedSubviews) {
        if (![v isKindOfClass:[NSStackView class]]) {
            continue;
        }
        for (NSView* sub in ((NSStackView*) v).arrangedSubviews) {
            if ([sub isKindOfClass:[NSTextField class]] && sub.tag == slider.tag && sub.identifier != nil && [sub.identifier isEqualToString:@"valueLabel"]) {
                NSString* unitText = ((NSTextField*) sub).toolTip ?: @"";
                ((NSTextField*) sub).stringValue =
                    unitText.length > 0 ? [NSString stringWithFormat:@"%.2f %@", value, unitText] : [NSString stringWithFormat:@"%.2f", value];
            }
        }
    }
}

- (void)adjustWindowToFitContent
{
    [self.rootStack layoutSubtreeIfNeeded];
    NSRect currentFrame = self.window.frame;
    NSRect currentContent = [self.window contentRectForFrameRect:currentFrame];
    CGFloat contentWidth = currentContent.size.width;

    NSSize fitting = [self.rootStack fittingSize];
    CGFloat contentHeight = fitting.height;
    CGFloat minHeight = 120.0;
    CGFloat maxHeight = 420.0;
    if (contentHeight < minHeight) {
        contentHeight = minHeight;
    }
    if (contentHeight > maxHeight) {
        contentHeight = maxHeight;
    }

    NSRect targetContent = NSMakeRect(0, 0, contentWidth, contentHeight);
    NSRect targetFrame = [self.window frameRectForContentRect:targetContent];

    CGFloat deltaH = targetFrame.size.height - currentFrame.size.height;
    targetFrame.origin.x = currentFrame.origin.x;
    targetFrame.origin.y = currentFrame.origin.y - deltaH;

    [self.window setFrame:targetFrame display:YES animate:YES];
}

- (NSString*)defaultsKeyForEffectIndex:(NSInteger)index
{
    if (index < 0 || index >= (NSInteger) self.effects.count) {
        return nil;
    }
    NSDictionary* entry = self.effects[(NSUInteger) index];
    NSValue* packed = entry[@"component"];
    if (packed == nil || strcmp([packed objCType], @encode(AudioComponentDescription)) != 0) {
        return nil;
    }
    AudioComponentDescription desc = {0};
    [packed getValue:&desc];
    return [NSString stringWithFormat:@"FXParams_%08x_%08x_%08x", (unsigned int) desc.componentType, (unsigned int) desc.componentSubType,
                                      (unsigned int) desc.componentManufacturer];
}

- (void)applyStoredParametersForCurrentEffect
{
    NSString* key = [self defaultsKeyForEffectIndex:self.audioController.currentEffectIndex];
    if (key.length == 0) {
        return;
    }
    NSDictionary* stored = [[NSUserDefaults standardUserDefaults] dictionaryForKey:key];
    if (stored.count == 0) {
        return;
    }
    for (id rawKey in stored) {
        AudioUnitParameterID param = 0;
        if ([rawKey isKindOfClass:[NSString class]]) {
            param = (AudioUnitParameterID)[(NSString*) rawKey intValue];
        } else if ([rawKey isKindOfClass:[NSNumber class]]) {
            param = (AudioUnitParameterID)[(NSNumber*) rawKey unsignedIntValue];
        } else {
            continue;
        }
        double value = [stored[rawKey] doubleValue];
        [self.audioController setEffectParameter:param value:(AudioUnitParameterValue) value];
        // update UI if visible
        for (NSView* row in self.paramsStack.arrangedSubviews) {
            if (![row isKindOfClass:[NSStackView class]]) {
                continue;
            }
            NSStackView* stack = (NSStackView*) row;
            NSSlider* slider = nil;
            NSTextField* valueField = nil;
            for (NSView* sub in stack.arrangedSubviews) {
                if ([sub isKindOfClass:[NSSlider class]] && sub.tag == (NSInteger) param) {
                    slider = (NSSlider*) sub;
                }
                if ([sub isKindOfClass:[NSTextField class]] && sub.tag == (NSInteger) param && sub.identifier != nil &&
                    [sub.identifier isEqualToString:@"valueLabel"]) {
                    valueField = (NSTextField*) sub;
                }
            }
            if (slider != nil) {
                slider.doubleValue = value;
            }
            if (valueField != nil) {
                NSString* unitText = valueField.toolTip ?: @"";
                valueField.stringValue =
                    unitText.length > 0 ? [NSString stringWithFormat:@"%.2f %@", value, unitText] : [NSString stringWithFormat:@"%.2f", value];
            }
        }
    }
}

- (void)persistParameter:(AudioUnitParameterID)param value:(double)value
{
    NSString* key = [self defaultsKeyForEffectIndex:self.audioController.currentEffectIndex];
    if (key.length == 0) {
        return;
    }
    NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
    NSMutableDictionary* stored = [[defaults dictionaryForKey:key] mutableCopy];
    if (stored == nil) {
        stored = [NSMutableDictionary dictionary];
    }
    NSString* paramKey = [NSString stringWithFormat:@"%u", (unsigned int) param];
    stored[paramKey] = @(value);
    [defaults setObject:stored forKey:key];
}

- (NSString*)displayUnitFor:(AudioUnitParameterUnit)unit
{
    switch (unit) {
    case kAudioUnitParameterUnit_Decibels:
        return @"dB";
    case kAudioUnitParameterUnit_Hertz:
        return @"Hz";
    case kAudioUnitParameterUnit_Percent:
        return @"%";
    case kAudioUnitParameterUnit_Seconds:
        return @"s";
    case kAudioUnitParameterUnit_Milliseconds:
        return @"ms";
    case kAudioUnitParameterUnit_LinearGain:
        return @"x";
    case kAudioUnitParameterUnit_BPM:
        return @"BPM";
    default:
        return @"";
    }
}

@end
