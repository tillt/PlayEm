//
//  GraphStatusViewController.m
//  PlayEm
//
//  Copyright © 2026 Till Toenshoff. All rights reserved.
//

#import "GraphStatusViewController.h"

#import "../../PlayEmCore/Audio/AudioController.h"
#import "../../PlayEmCore/Audio/AudioDevice.h"
#import "../../PlayEmCore/Sample/LazySample.h"
#import "../Defaults.h"

static NSString* const kStatusColumnIdentifier = @"StatusColumn";
static NSString* const kValueColumnIdentifier = @"ValueColumn";

@interface GraphStatusViewController ()

@property (nonatomic, weak) AudioController* audioController;
@property (nonatomic, weak, nullable) LazySample* sample;
@property (nonatomic, strong) NSTableView* tableView;
@property (nonatomic, strong) NSArray<NSDictionary<NSString*, NSString*>*>* rows;

@end

@implementation GraphStatusViewController

- (instancetype)initWithAudioController:(AudioController*)audioController sample:(LazySample*)sample
{
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _audioController = audioController;
        _sample = sample;
        _rows = @[];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleGraphChange:) name:kPlaybackGraphChanged object:nil];
    }
    return self;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)loadView
{
    NSScrollView* scrollView = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    scrollView.hasVerticalScroller = YES;
    scrollView.hasHorizontalScroller = NO;
    scrollView.autohidesScrollers = YES;
    scrollView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    scrollView.drawsBackground = NO;
    scrollView.horizontalScrollElasticity = NSScrollElasticityNone;
    if ([scrollView respondsToSelector:@selector(setContentInsets:)]) {
        scrollView.contentInsets = NSEdgeInsetsMake(0.0, 0.0, 0.0, 0.0);
    }

    _tableView = [[NSTableView alloc] initWithFrame:scrollView.bounds];
    _tableView.headerView = nil;
    _tableView.allowsEmptySelection = NO;
    _tableView.backgroundColor = [NSColor clearColor];
    _tableView.rowHeight = [[Defaults sharedDefaults] smallFontSize] + 6.0;
    _tableView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    _tableView.intercellSpacing = NSMakeSize(0.0, 4.0);
    _tableView.columnAutoresizingStyle = NSTableViewUniformColumnAutoresizingStyle;
    _tableView.delegate = self;
    _tableView.dataSource = self;

    NSTableColumn* statusCol = [[NSTableColumn alloc] initWithIdentifier:kStatusColumnIdentifier];
    statusCol.title = NSLocalizedString(@"graph.status.column.status", @"Graph status table column title");
    statusCol.minWidth = 0.0;
    statusCol.maxWidth = CGFLOAT_MAX;
    statusCol.resizingMask = NSTableColumnAutoresizingMask;
    [_tableView addTableColumn:statusCol];

    NSTableColumn* valueCol = [[NSTableColumn alloc] initWithIdentifier:kValueColumnIdentifier];
    valueCol.title = NSLocalizedString(@"graph.status.column.value", @"Graph status table column title");
    valueCol.minWidth = 0.0;
    valueCol.maxWidth = CGFLOAT_MAX;
    valueCol.resizingMask = NSTableColumnAutoresizingMask;
    [_tableView addTableColumn:valueCol];

    // Fit columns to available width to avoid horizontal scrolling.
    CGFloat available = scrollView.contentSize.width;
    if ([scrollView respondsToSelector:@selector(contentInsets)]) {
        NSEdgeInsets inset = scrollView.contentInsets;
        available -= (inset.left + inset.right);
    }
    CGFloat statusWidth = MAX(140.0, available * 0.55);
    statusCol.width = statusWidth;
    valueCol.width = MAX(120.0, available - statusWidth);

    scrollView.documentView = _tableView;
    self.view = scrollView;
    [self reloadData];
}

- (void)handleGraphChange:(NSNotification*)notification
{
    id sampleObj = notification.userInfo[@"sample"];

    LazySample* latest = nil;
    if (sampleObj != nil) {
        latest = (LazySample*)sampleObj;
    } else {
        latest = [self.audioController sample];
        if (latest == nil) {
            latest = self.sample;
        }
    }

    [self updateSample:latest];
}

- (void)updateSample:(LazySample*)sample
{
    self.sample = sample;
    [self reloadData];
}

- (void)reloadData
{
    NSMutableArray* rows = [NSMutableArray array];

    // Prefer latest sample from controller if we were created before load.
    LazySample* sample = self.sample;
    if (sample == nil && [self.audioController respondsToSelector:@selector(sample)]) {
        sample = [self.audioController sample];
    }

    // File name.
    NSString* fileName = @"-";
    if (sample && sample.source.url) {
        NSString* last = sample.source.url.lastPathComponent ?: @"";
        if (last.length == 0) {
            last = sample.source.url.path ?: @"";
        }
        fileName = last.length > 0 ? last : @"-";
    }
    [rows addObject:@{ @"label" : @"File", @"value" : fileName }];

    // Encoded (file) sample rate.
    Float64 encodedRate = sample ? sample.fileSampleRate : 0;
    NSString* encodedRateStr = (encodedRate > 0) ? [NSString stringWithFormat:@"%.1f kHz", encodedRate / 1000.0] : @"-";
    [rows addObject:@{ @"label" : @"File rate (encoded)", @"value" : encodedRateStr }];

    // Decoded/resampled rate.
    Float64 decodedRate = sample ? sample.renderedSampleRate : 0;
    NSString* decodedRateStr = (decodedRate > 0) ? [NSString stringWithFormat:@"%.1f kHz", decodedRate / 1000.0] : @"-";
    [rows addObject:@{ @"label" : @"File rate (decoded)", @"value" : decodedRateStr }];

    // Separator.
    [rows addObject:@{ @"type" : @"separator" }];

    // Device name and rate.
    AudioObjectID deviceId = [AudioDevice defaultOutputDevice];
    NSString* deviceName = [AudioDevice nameForDevice:deviceId] ?: @"-";
    [rows addObject:@{ @"label" : @"Device", @"value" : deviceName }];
    Float64 deviceRate = [AudioDevice sampleRateForDevice:deviceId];
    NSString* deviceRateStr = (deviceRate > 0) ? [NSString stringWithFormat:@"%.1f kHz", deviceRate / 1000.0] : @"-";
    [rows addObject:@{ @"label" : @"Device rate", @"value" : deviceRateStr }];

    // Device latency.
    AVAudioFramePosition latency = [AudioDevice latencyForDevice:deviceId scope:kAudioDevicePropertyScopeOutput];
    NSString* latencyStr = (latency > 0) ? [NSString stringWithFormat:@"%lld frames", latency] : @"-";
    [rows addObject:@{ @"label" : @"Device latency", @"value" : latencyStr }];

    // Separator.
    [rows addObject:@{ @"type" : @"separator" }];

    // Effect status.
    NSString* effectLabel = @"Effect";
    NSInteger effectIndex = self.audioController ? self.audioController.currentEffectIndex : -1;
    BOOL effectEnabled = self.audioController ? self.audioController.effectEnabled : NO;
    NSString* effectValue = @"None";
    if (effectIndex >= 0 && effectIndex < (NSInteger) self.audioController.availableEffects.count) {
        NSDictionary* entry = self.audioController.availableEffects[(NSUInteger) effectIndex];
        NSString* name = entry[@"displayName"] ?: entry[@"name"];
        if (name.length > 0) {
            effectValue = [NSString stringWithFormat:@"%@ (%@)", name, effectEnabled ? @"active" : @"inactive"];
        }
    }
    [rows addObject:@{ @"label" : effectLabel, @"value" : effectValue }];

    // Tempo/time-shift effect status.
    NSString* tempoLabel = @"Tempo/Time Shift";
    NSString* tempoValue = @"-";
    if ([self.audioController respondsToSelector:@selector(tempoShift)]) {
        float tempo = self.audioController.tempoShift;
        BOOL tempoBypassed = [self.audioController respondsToSelector:@selector(tempoBypassed)] ? self.audioController.tempoBypassed : (tempo == 1.0f);
        NSString* base = [NSString stringWithFormat:@"%.2fx", tempo];
        tempoValue = [NSString stringWithFormat:@"%@ (%@)", base, tempoBypassed ? @"inactive" : @"active"];
    }
    [rows addObject:@{ @"label" : tempoLabel, @"value" : tempoValue }];

    self.rows = rows;
    [self.tableView reloadData];
}

#pragma mark - NSTableViewDataSource

- (NSInteger)numberOfRowsInTableView:(NSTableView*)tableView
{
    return (NSInteger) self.rows.count;
}

- (CGFloat)tableView:(NSTableView*)tableView heightOfRow:(NSInteger)row
{
    NSDictionary* entry = self.rows[(NSUInteger) row];
    if ([entry[@"type"] isEqualToString:@"separator"]) {
        return tableView.rowHeight - 4.0;
    }
    return tableView.rowHeight;
}

#pragma mark - NSTableViewDelegate

- (BOOL)tableView:(NSTableView*)tableView shouldSelectRow:(NSInteger)row
{
    return NO;
}

- (NSView*)tableView:(NSTableView*)tableView viewForTableColumn:(NSTableColumn*)tableColumn row:(NSInteger)row
{
    NSDictionary* entry = self.rows[(NSUInteger) row];

    NSString* type = entry[@"type"];
    // We have our hand-rolled separators in place.
    if ([type isEqualToString:@"separator"]) {
        NSView* lineView = [tableView makeViewWithIdentifier:@"SeparatorCell" owner:self];
        if (lineView == nil) {
            lineView = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, tableColumn.width,  tableView.rowHeight)];
            lineView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
            lineView.identifier = @"SeparatorCell";

            NSBox* box = [[NSBox alloc] initWithFrame:NSMakeRect(0, ceil(lineView.frame.size.height / 2.0), lineView.frame.size.width, 1.0)];
            box.boxType = NSBoxSeparator;
            box.autoresizingMask = NSViewNotSizable;
            [lineView addSubview:box];
        }
        return lineView;
    }

    NSString* identifier = tableColumn.identifier;

    NSTextField* textField = [tableView makeViewWithIdentifier:identifier owner:self];
    if (textField == nil) {
        textField = [[NSTextField alloc] initWithFrame:NSMakeRect(0.0, 0.0, tableColumn.width, tableView.rowHeight)];
        textField.identifier = identifier;
        textField.bezeled = NO;
        //textField.backgroundColor = [NSColor blueColor];
        textField.drawsBackground = NO;
        textField.editable = NO;
        textField.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
        textField.selectable = NO;
        textField.textColor = [[Defaults sharedDefaults] secondaryLabelColor];
        textField.font = [[Defaults sharedDefaults] smallFont];
    }

    if ([identifier isEqualToString:kStatusColumnIdentifier]) {
        textField.stringValue = entry[@"label"] ?: @"";
        textField.alignment = NSTextAlignmentLeft;
    } else {
        textField.stringValue = entry[@"value"] ?: @"";
        textField.alignment = NSTextAlignmentRight;
    }
    // Truncate long fields; file/device/effect use middle truncation, others tail.
    NSString* label = entry[@"label"];
    if ([label isEqualToString:@"File"] || [label isEqualToString:@"Device"] || [label isEqualToString:@"Effect"]) {
        textField.lineBreakMode = NSLineBreakByTruncatingMiddle;
    } else {
        textField.lineBreakMode = NSLineBreakByTruncatingTail;
    }

    return textField;
}

@end
