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
@property (nonatomic, strong) NSButton* effectToggle;
@property (nonatomic, strong) NSArray<NSDictionary*>* effects;
@property (nonatomic, strong) NSStackView* rootStack;
@property (nonatomic, strong) NSStackView* paramsStack;
@end

static NSString* const kFXLastEffectEnabledKey = @"FXLastEffectEnabled";

@implementation FXViewController

- (instancetype)initWithAudioController:(AudioController*)audioController
{
    NSPanel* panel = [[NSPanel alloc] initWithContentRect:NSMakeRect(0, 0, 380, 200)
                                                styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable)
                                                  backing:NSBackingStoreBuffered
                                                    defer:NO];
    self = [super initWithWindow:panel];
    if (self) {
        _audioController = audioController;
        _effects = @[];
        panel.floatingPanel = NO;
        panel.level = NSNormalWindowLevel;
        panel.becomesKeyOnlyIfNeeded = YES;
        panel.titlebarAppearsTransparent = YES;
        panel.hidesOnDeactivate = NO;
        panel.title = @"Effect";
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
    self.rootStack.spacing = 0.0;
    // Top inset reduced; keep original horizontal padding.
    self.rootStack.edgeInsets = NSEdgeInsetsMake(0.0, 20.0, 10.0, 20.0);
    self.rootStack.translatesAutoresizingMaskIntoConstraints = NO;
    [self.content addSubview:self.rootStack];

    NSLayoutConstraint* rootTop = [self.rootStack.topAnchor constraintEqualToAnchor:self.content.topAnchor];
    NSLayoutConstraint* rootLeading = [self.rootStack.leadingAnchor constraintEqualToAnchor:self.content.leadingAnchor];
    NSLayoutConstraint* rootTrailing = [self.rootStack.trailingAnchor constraintEqualToAnchor:self.content.trailingAnchor];
    NSLayoutConstraint* rootBottom = [self.rootStack.bottomAnchor constraintEqualToAnchor:self.content.bottomAnchor];
    [NSLayoutConstraint activateConstraints:@[ rootTop, rootLeading, rootTrailing, rootBottom ]];

    // Header row
    self.effectToggle = [NSButton checkboxWithTitle:@"On" target:self action:@selector(effectToggleChanged:)];
    self.effectToggle.controlSize = NSControlSizeSmall;
    self.effectToggle.state = NSControlStateValueOff;
    self.effectToggle.translatesAutoresizingMaskIntoConstraints = NO;

    self.effectMenu = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    self.effectMenu.target = self;
    self.effectMenu.font = [[Defaults sharedDefaults] smallFont];
    self.effectMenu.action = @selector(effectChanged:);
    self.effectMenu.translatesAutoresizingMaskIntoConstraints = NO;
    self.effectMenu.accessibilityLabel = @"Effect selection";

    NSView* header = [[NSView alloc] initWithFrame:NSZeroRect];
    header.translatesAutoresizingMaskIntoConstraints = NO;
    [self.rootStack addArrangedSubview:header];

    [NSLayoutConstraint activateConstraints:@[
        [header.heightAnchor constraintEqualToConstant:40.0]
    ]];

    // Place the toggle on the left and let the menu fill remaining space.
    CGFloat margin = 0.0; // rely on rootStack edgeInsets for horizontal inset
    CGFloat spacing = 8.0;
    [header addSubview:self.effectToggle];
    [header addSubview:self.effectMenu];

    CGFloat topPadding = 6.0;
    [NSLayoutConstraint activateConstraints:@[
        [self.effectToggle.leadingAnchor constraintEqualToAnchor:header.leadingAnchor constant:margin],
        [self.effectToggle.topAnchor constraintEqualToAnchor:header.topAnchor constant:topPadding],
        [self.effectToggle.heightAnchor constraintEqualToConstant:20.0],

        [self.effectMenu.centerXAnchor constraintEqualToAnchor:header.centerXAnchor],
        [self.effectMenu.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.effectToggle.trailingAnchor constant:spacing],
        [self.effectMenu.trailingAnchor constraintLessThanOrEqualToAnchor:header.trailingAnchor constant:-10.0],
        [self.effectMenu.topAnchor constraintEqualToAnchor:header.topAnchor constant:topPadding - 2.0],
        [self.effectMenu.heightAnchor constraintEqualToConstant:24.0]
    ]];

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
        NSString* name = entry[@"displayName"] ?: entry[@"name"];
        NSNumber* subtype = entry[@"subtype"];
        NSString* title = (name && name.length > 0) ? name : [NSString stringWithFormat:@"0x%08x", subtype.unsignedIntValue];
        [self.effectMenu addItemWithTitle:title];
    }
    [self selectEffectIndex:self.audioController.currentEffectIndex];
    self.effectToggle.state = (self.audioController.currentEffectIndex >= 0) ? NSControlStateValueOn : NSControlStateValueOff;

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

    self.effectToggle.state = (idx >= 0) ? NSControlStateValueOn : NSControlStateValueOff;
    if (self.effectSelectionChanged != nil) {
        self.effectSelectionChanged(idx);
    }
}

- (void)effectToggleChanged:(id)sender
{
    if (self.effectToggle.state == NSControlStateValueOn) {
        NSInteger selected = self.effectMenu.indexOfSelectedItem;
        if (selected < 0 && self.effects.count > 0) {
            selected = 0;
            [self.effectMenu selectItemAtIndex:selected];
        }
        if (selected >= 0) {
            // If already selected, just ensure it is enabled.
            if (self.audioController.currentEffectIndex == selected) {
                [self.audioController applyEffectEnabled:YES];
                [[NSUserDefaults standardUserDefaults] setBool:YES forKey:kFXLastEffectEnabledKey];
                [self applyStoredParametersForCurrentEffect];
            } else {
                [self effectChanged:self.effectMenu];
            }
        }
    } else {
        [self.audioController applyEffectEnabled:NO];
        [[NSUserDefaults standardUserDefaults] setBool:NO forKey:kFXLastEffectEnabledKey];
        // Keep current UI/values; do not reload to avoid pulling defaults from the unit.
    }
}

- (void)setEffectEnabledState:(BOOL)enabled
{
    self.effectToggle.state = enabled ? NSControlStateValueOn : NSControlStateValueOff;
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

    // Preserve any persisted values so toggling bypass does not reset UI or parameters.
    NSDictionary* persisted = nil;
    NSString* persistedKey = [self defaultsKeyForEffectIndex:self.audioController.currentEffectIndex];
    if (persistedKey.length > 0) {
        persisted = [[NSUserDefaults standardUserDefaults] dictionaryForKey:persistedKey];
    }

    for (NSNumber* key in keys) {
        NSDictionary* meta = info[key];
        NSString* name = meta[@"name"] ?: @"";
        if (name.length == 0) {
            name = [NSString stringWithFormat:@"Param %@", key];
        }
        double min = [meta[@"min"] doubleValue];
        double max = [meta[@"max"] doubleValue];
        double current = meta[@"current"] ? [meta[@"current"] doubleValue] : [meta[@"default"] doubleValue];
        if (persisted != nil) {
            id stored = persisted[[key stringValue]];
            if (stored != nil) {
                current = [stored doubleValue];
            }
        }
        AudioUnitParameterUnit unit = (AudioUnitParameterUnit)[meta[@"unit"] unsignedIntValue];
        BOOL isBoolean = (unit == kAudioUnitParameterUnit_Boolean);

        NSStackView* row = [NSStackView stackViewWithViews:@[]];
        row.orientation = NSUserInterfaceLayoutOrientationHorizontal;
        row.alignment = NSLayoutAttributeCenterY;
        row.distribution = NSStackViewDistributionFill;
        row.spacing = spacing;
        row.translatesAutoresizingMaskIntoConstraints = NO;

        NSTextField* nameField = [NSTextField labelWithString:name];
        nameField.font = [[Defaults sharedDefaults] smallFont];
        nameField.textColor = [[Defaults sharedDefaults] secondaryLabelColor];
        nameField.lineBreakMode = NSLineBreakByTruncatingTail;
        nameField.accessibilityLabel = name;
        [nameField.widthAnchor constraintEqualToConstant:nameWidth].active = YES;
        [nameField.heightAnchor constraintEqualToConstant:20.0].active = YES;

        NSString* unitText = [self displayUnitFor:unit];
        NSControl* control = nil;
        NSString* valueString = @"";

        if (isBoolean) {
            NSButton* toggle = [NSButton checkboxWithTitle:@"" target:self action:@selector(parameterChanged:)];
            toggle.state = (current >= 0.5) ? NSControlStateValueOn : NSControlStateValueOff;
            toggle.tag = (NSInteger) key.unsignedIntValue;
            toggle.controlSize = NSControlSizeMini;
            toggle.translatesAutoresizingMaskIntoConstraints = NO;
            [toggle.heightAnchor constraintEqualToConstant:18.0].active = YES;
            [toggle.widthAnchor constraintEqualToConstant:18.0].active = YES;
            toggle.accessibilityLabel = name;
            control = toggle;
            //valueString = (toggle.state == NSControlStateValueOn) ? @"On" : @"Off";
        } else {
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
            slider.accessibilityLabel = name;
            slider.accessibilityTitleUIElement = nameField;

            NSString* help = [NSString stringWithFormat:@"Range %.2f to %.2f", min, max];
            if (unitText.length > 0) {
                help = [help stringByAppendingFormat:@" %@", unitText];
            }
            slider.accessibilityHelp = help;
            control = slider;
            valueString =
                unitText.length > 0 ? [NSString stringWithFormat:@"%.2f %@", current, unitText] : [NSString stringWithFormat:@"%.2f", current];
        }

        NSTextField* valueField = [NSTextField labelWithString:valueString];
        valueField.font = [[Defaults sharedDefaults] smallFont];
        valueField.alignment = NSTextAlignmentRight;
        valueField.tag = control.tag;
        valueField.textColor = [[Defaults sharedDefaults] secondaryLabelColor];
        valueField.identifier = @"valueLabel";
        valueField.toolTip = isBoolean ? @"boolean" : unitText;
        valueField.accessibilityLabel = name;
        valueField.accessibilityValue = valueString;
        if (unitText.length > 0) {
            valueField.accessibilityHelp = [NSString stringWithFormat:@"Value in %@", unitText];
        }
        [valueField setContentHuggingPriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];
        [valueField setContentCompressionResistancePriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];
        [valueField.widthAnchor constraintEqualToConstant:valueWidth].active = YES;
        [valueField.heightAnchor constraintEqualToConstant:20.0].active = YES;

        [row addArrangedSubview:nameField];
        [row addArrangedSubview:control];
        [row addArrangedSubview:valueField];

        [self.paramsStack addArrangedSubview:row];
    }
    [self adjustWindowToFitContent];
}

- (void)parameterChanged:(id)sender
{
    AudioUnitParameterID param = (AudioUnitParameterID)[sender tag];
    AudioUnitParameterValue value = 0.0f;

    BOOL isBoolean = NO;
    if ([sender isKindOfClass:[NSButton class]]) {
        value = (((NSButton*) sender).state == NSControlStateValueOn) ? 1.0f : 0.0f;
        isBoolean = YES;
    } else if ([sender isKindOfClass:[NSSlider class]]) {
        value = (AudioUnitParameterValue) ((NSSlider*) sender).doubleValue;
    } else {
        return;
    }

    [self.audioController setEffectParameter:param value:value];
    [self persistParameter:param value:value];

    NSString* unitText = @"";

    for (NSView* v in self.paramsStack.arrangedSubviews) {
        if (![v isKindOfClass:[NSStackView class]]) {
            continue;
        }
        for (NSView* sub in ((NSStackView*) v).arrangedSubviews) {
            if ([sub isKindOfClass:[NSTextField class]] && sub.tag == param && sub.identifier != nil &&
                [sub.identifier isEqualToString:@"valueLabel"]) {
                unitText = ((NSTextField*) sub).toolTip ?: @"";

                NSString* newValue = @"";
                if (!isBoolean && ![unitText isEqualToString:@"boolean"]) {
                    newValue =
                        unitText.length > 0 ? [NSString stringWithFormat:@"%.2f %@", value, unitText] : [NSString stringWithFormat:@"%.2f", value];
                }
                ((NSTextField*) sub).stringValue = newValue;
                ((NSTextField*) sub).accessibilityValue = newValue;
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
            NSControl* control = nil;
            NSTextField* valueField = nil;
            for (NSView* sub in stack.arrangedSubviews) {
                if ([sub isKindOfClass:[NSControl class]] && sub.tag == (NSInteger) param) {
                    control = (NSControl*) sub;
                }
                if ([sub isKindOfClass:[NSTextField class]] && sub.tag == (NSInteger) param && sub.identifier != nil &&
                    [sub.identifier isEqualToString:@"valueLabel"]) {
                    valueField = (NSTextField*) sub;
                }
            }
            if (control != nil) {
                if ([control isKindOfClass:[NSButton class]]) {
                    ((NSButton*) control).state = (value >= 0.5) ? NSControlStateValueOn : NSControlStateValueOff;
                } else if ([control isKindOfClass:[NSSlider class]]) {
                    ((NSSlider*) control).doubleValue = value;
                }
            }
            if (valueField != nil) {
                NSString* unitText = valueField.toolTip ?: @"";
                NSString* newValue = @"";
                if (![unitText isEqualToString:@"boolean"]) {
                    newValue =
                        unitText.length > 0 ? [NSString stringWithFormat:@"%.2f %@", value, unitText] : [NSString stringWithFormat:@"%.2f", value];
                }
                valueField.stringValue = newValue;
                valueField.accessibilityValue = newValue;
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
