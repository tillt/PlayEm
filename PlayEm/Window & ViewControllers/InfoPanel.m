//
//  InfoPanel.m
//  PlayEm
//
//  Created by Till Toenshoff on 15.09.22.
//  Copyright © 2022 Till Toenshoff. All rights reserved.
//

#import "InfoPanel.h"
#import <Quartz/Quartz.h>

#import "MediaMetaData.h"
#import "TextViewWithPlaceholder.h"
#import "DragImageFileView.h"
#import "CAShapeLayer+Path.h"
#import "../Defaults.h"
#import "../NSString+OccurenceCount.h"
#import "../NSImage+Resize.h"

typedef enum : NSUInteger {
    InfoControlTypeText,
    InfoControlTypeCombo,
    InfoControlTypeCheck,
    InfoControlTypePopup,
} InfoControlType;

NSString* const kInfoPageKeyDetails = @"Details";
NSString* const kInfoPageKeyArtwork = @"Artwork";
NSString* const kInfoPageKeyLyrics = @"Lyrics";
NSString* const kInfoPageKeyFile = @"File";

NSString* const kInfoTextMultipleValues = @"Mixed";
NSString* const kInfoNumberMultipleValues = @"-";

static const CGFloat kBigFontSize = 24.0f;
static const CGFloat kNormalFontSize = 13.0f;
static const CGFloat kViewTopMargin = 20.0f;
static const CGFloat kViewLeftMargin = 10.0f;

@interface InfoPanelController ()

@property (strong, nonatomic) NSProgressIndicator* progress;

@property (strong, nonatomic) NSImageView* smallCoverView;
@property (strong, nonatomic) DragImageFileView* largeCoverView;

@property (strong, nonatomic) TextViewWithPlaceholder* lyricsTextView;

@property (strong, nonatomic) NSTabView* tabView;

@property (strong, nonatomic) NSTabViewItem* detailsTabViewItem;
@property (strong, nonatomic) NSTabViewItem* artworkTabViewItem;
@property (strong, nonatomic) NSTabViewItem* lyricsTabViewItem;
@property (strong, nonatomic) NSTabViewItem* fileTabViewItem;

@property (strong, nonatomic) NSMutableDictionary* viewControls;
@property (strong, nonatomic) dispatch_queue_t metaIOQueue;

@property (strong, nonatomic) NSArray<MediaMetaData*>* metas;

@property (strong, nonatomic) MediaMetaData* commonMeta;
@property (strong, nonatomic) MediaMetaData* deltaMeta;

@property (strong, nonatomic) NSTextField* titleTextField;
@property (strong, nonatomic) NSTextField* artistTextField;
@property (strong, nonatomic) NSTextField* albumTextField;

@property (strong, nonatomic) NSImageView* googleArtwork;

@property (strong, nonatomic) NSDictionary* viewConfiguration;
@property (strong, nonatomic) NSDictionary* deltaKeys;
@property (strong, nonatomic) NSMutableDictionary* mutatedKeys;

@property (strong, nonatomic) CALayer* effectLayer;

@property (strong, nonatomic) NSVisualEffectView* effectBelowHeader;

@end

@implementation InfoPanelController

+ (CIFilter*)sharedBloomFilter
{
    static dispatch_once_t once;
    static CIFilter* sharedInstance;
    dispatch_once(&once, ^{
        sharedInstance = [CIFilter filterWithName:@"CIBloom"];
        [sharedInstance setDefaults];
        [sharedInstance setValue:[NSNumber numberWithFloat:3.0]
                          forKey: @"inputRadius"];
        [sharedInstance setValue:[NSNumber numberWithFloat:1.0]
                          forKey: @"inputIntensity"];
    });
    return sharedInstance;
}

- (id)initWithMetas:(NSArray<MediaMetaData*>*)metas
{
    self = [super init];
    if (self) {
        _metas = metas;
        
        NSNumber* bigWidth = @475;
        
        _viewConfiguration = @{
            kInfoPageKeyDetails: @{
                @"title": @{
                    @"order": @1,
                    @"width": bigWidth,
                    @"placeholder": kInfoTextMultipleValues,
                },
                @"artist": @{
                    @"order": @2,
                    @"width": bigWidth,
                    @"placeholder": kInfoTextMultipleValues,
                },
                @"album": @{
                    @"order": @3,
                    @"width": bigWidth,
                    @"placeholder": kInfoTextMultipleValues,
                },
                @"album artist": @{
                    @"order": @4,
                    @"width": bigWidth,
                    @"key": @"albumArtist",
                    @"placeholder": kInfoTextMultipleValues,
                },
                @"tags": @{
                    @"order": @5,
                    @"width": bigWidth,
                    @"placeholder": kInfoTextMultipleValues,
                },
                @"genre": @{
                    @"order": @6,
                    @"width": @180,
                    @"type": @(InfoControlTypeCombo),
                    @"placeholder": kInfoTextMultipleValues,
                },
                @"year": @{
                    @"order": @7,
                    @"width": @60,
                    @"placeholder": kInfoNumberMultipleValues,
                },
                @"track": @{
                    @"order": @8,
                    @"width": @40,
                    @"placeholder": kInfoNumberMultipleValues,
                    @"extra": @{
                        @"title": @"of",
                        @"key": @"tracks",
                    }
                },
                @"disk": @{
                    @"order": @9,
                    @"width": @40,
                    @"placeholder": kInfoNumberMultipleValues,
                    @"extra": @{
                        @"title": @"of",
                        @"key": @"disks",
                    }
                },
                @"compilation": @{
                    @"order": @10,
                    @"width": bigWidth,
                    @"description": @"Album is a compilation of songs by various artists",
                    @"type": @(InfoControlTypeCheck),
                },
                @"rating": @{
                    @"order": @11,
                    @"width": @124,
                    @"key": @"stars",
                    @"type": @(InfoControlTypePopup),
                    @"values": [[[MediaMetaData starsQuantums] allValues] sortedArrayUsingSelector:
                                @selector(localizedCaseInsensitiveCompare:)],
                },
                @"tempo": @{
                    @"order": @12,
                    @"width": @40,
                    @"placeholder": kInfoNumberMultipleValues,
                    @"extra": @{
                        @"title": @"key",
                        @"key": @"key",
                    }
                },
                @"comment": @{
                    @"order": @13,
                    @"width": bigWidth,
                    @"rows": @6,
                    @"placeholder": kInfoTextMultipleValues,
                },
            },
            kInfoPageKeyFile: @{
                @"size": @{
                    @"order": @1,
                    @"width": bigWidth,
                    @"editable": @NO,
                },
                @"duration": @{
                    @"order": @2,
                    @"width": bigWidth,
                    @"editable": @NO,
                },
                @"bit rate": @{
                    @"order": @3,
                    @"width": bigWidth,
                    @"key": @"bitrate",
                    @"editable": @NO,
                },
                @"sample rate": @{
                    @"order": @4,
                    @"width": bigWidth,
                    @"key": @"samplerate",
                    @"editable": @NO,
                },
                @"channels": @{
                    @"order": @5,
                    @"width": bigWidth,
                    @"editable": @NO,
                },
                @"format": @{
                    @"order": @6,
                    @"width": bigWidth,
                    @"editable": @NO,
                },
                @"volume": @{
                    @"order": @3,
                    @"width": bigWidth,
                    @"editable": @NO,
                },
                @"location": @{
                    @"order": @7,
                    @"width": bigWidth,
                    @"rows": @6,
                    @"editable": @NO,
                },
            },
        };
        
        _viewControls = [NSMutableDictionary dictionary];

        dispatch_queue_attr_t attr = dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL,
                                                                             QOS_CLASS_USER_INTERACTIVE,
                                                                             0);
        _metaIOQueue = dispatch_queue_create("PlayEm.MetaQueue", attr);
    }
    return self;
}

- (void)loadControlsWithView:(NSView*)view pageKey:(NSString*)pageKey
{
    //const CGFloat imageWidth = 120.0f;
    const CGFloat nameFieldWidth = 80.0;
    const CGFloat rowUnitHeight = 18.0f;
    const CGFloat kBorderWidth = 5.0;
    const CGFloat kRowInset = 4.0f;
    const CGFloat kRowSpace = 10.0f;
    
    NSMutableDictionary* dict = [NSMutableDictionary dictionaryWithDictionary:_viewControls[pageKey]];
    if (dict == nil) {
        dict = [NSMutableDictionary dictionary];
    }

    NSArray* orderedKeys = [_viewConfiguration[pageKey] keysSortedByValueUsingComparator:^(id obj1, id obj2){
        NSNumber *rank1 = [obj1 valueForKeyPath:@"order"];
        NSNumber *rank2 = [obj2 valueForKeyPath:@"order"];
        return (NSComparisonResult)[rank1 compare:rank2];
    }];
    
    NSEnumerator* reversed = [orderedKeys reverseObjectEnumerator];
    
    CGFloat y = 10.0f;
    
    NSView* lastInputView = nil;
    NSView* firstInputView = nil;
    
    for (NSString* key in reversed) {
        NSMutableDictionary* elements = [NSMutableDictionary dictionary];

        NSString* configKey = key;
        if ([_viewConfiguration[pageKey][key] objectForKey:@"key"]) {
            configKey = _viewConfiguration[pageKey][key][@"key"];
        }

        NSNumber* number = _viewConfiguration[pageKey][key][@"width"];
        CGFloat width = [number floatValue];
        
        unsigned int rows = 1;
        number = [_viewConfiguration[pageKey][key] objectForKey:@"rows"];
        if (number != nil) {
            rows = [number intValue];
        }
        
        number = [_viewConfiguration[pageKey][key] objectForKey:@"type"];
        InfoControlType type = InfoControlTypeText;
        if (number != nil) {
            type = [number intValue];
        }

        BOOL editable = YES;
        number = [_viewConfiguration[pageKey][key] objectForKey:@"editable"];
        if (number != nil) {
            editable = [number boolValue];
        }
        
        NSDictionary* extra = [_viewConfiguration[pageKey][key] objectForKey:@"extra"];
        
        NSTextField* textField = [NSTextField textFieldWithString:key];
        textField.bordered = NO;
        textField.textColor = [[Defaults sharedDefaults] secondaryLabelColor];
        textField.drawsBackground = NO;
        textField.editable = NO;
        textField.selectable = NO;
        textField.alignment = NSTextAlignmentRight;
        textField.frame = NSMakeRect(kBorderWidth,
                                     y - floor((rowUnitHeight - kNormalFontSize) / 2.0f),
                                     nameFieldWidth,
                                     (rows * rowUnitHeight) + kRowInset);
        [view addSubview:textField];

        CGFloat x = nameFieldWidth + kBorderWidth + kBorderWidth;

        switch (type) {
            case InfoControlTypeText: {
                textField = [NSTextField textFieldWithString:@""];
                textField.bordered = editable;
                textField.textColor = [[Defaults sharedDefaults] lightFakeBeamColor];
                textField.drawsBackground = NO;
                textField.editable = editable;
                textField.alignment = NSTextAlignmentLeft;
                
                if (editable) {
                    textField.delegate = self;
                }
                
                if (rows > 1) {
                    textField.lineBreakMode = NSLineBreakByCharWrapping;
                    textField.usesSingleLineMode = NO;
                    textField.cell.wraps = YES;
                    textField.cell.scrollable = NO;
                } else {
                    textField.usesSingleLineMode = YES;
                }
                
                textField.frame = NSMakeRect(x,
                                             y - floor(editable ? 0.0f : (rowUnitHeight - kNormalFontSize) / 2.0f),
                                             width - kBorderWidth,
                                             (rows * rowUnitHeight) + kRowInset);
                [view addSubview:textField];
                
                elements[@"control"] = textField;
                
                textField.nextKeyView = lastInputView;
                lastInputView = textField;
            } break;
            case InfoControlTypeCombo: {
                NSComboBox* comboBox = [NSComboBox new];
                comboBox.frame = NSMakeRect(x,
                                            y,
                                            width - kBorderWidth,
                                            rowUnitHeight + kRowInset);
                comboBox.usesDataSource = YES;
                comboBox.dataSource = self;
                comboBox.delegate = self;
                comboBox.editable = YES;
                comboBox.drawsBackground = NO;
                [view addSubview:comboBox];

                elements[@"control"] = comboBox;
                
                comboBox.nextKeyView = lastInputView;
                lastInputView = comboBox;
            } break;
            case InfoControlTypePopup: {
                NSPopUpButton* popup = [NSPopUpButton new];
                popup.frame = NSMakeRect(x,
                                         y,
                                         width - kBorderWidth,
                                         rowUnitHeight + kRowInset);
                popup.allowsMixedState = NO;
                popup.action = @selector(didSelectPopupItem:);

                NSArray<NSString*>* list = [_viewConfiguration[pageKey][key] objectForKey:@"values"];
                [popup addItemsWithTitles:list];

                [view addSubview:popup];
                
                elements[@"control"] = popup;
                
                popup.nextKeyView = lastInputView;
                lastInputView = popup;
            } break;
            case InfoControlTypeCheck: {
                NSString* title = [_viewConfiguration[pageKey][key] objectForKey:@"description"];
                SEL selector = NSSelectorFromString([NSString stringWithFormat:@"%@Action:", configKey]);
                NSButton* button = [NSButton checkboxWithTitle:title
                                                        target:self
                                                        action:selector];
                button.frame = NSMakeRect(x,
                                          y,
                                          width - kBorderWidth,
                                          rowUnitHeight + kRowInset);
                button.allowsMixedState = NO;
                [view addSubview:button];
                
                elements[@"control"] = button;

                button.nextKeyView = lastInputView;
                lastInputView = button;
            } break;
        }

        if (firstInputView == nil) {
            firstInputView = lastInputView;
        }
        
        // FIXME: There still is a lot wrong with this checkmark thing:
        // 1. It should be a button for being able to undo the change.
        // 2. The symbol is line based -- thus for lines with multiple entries (ie track / tracks) it needs to track multiple value fields.
        NSTextField* checkMark = [NSTextField textFieldWithString:@"􀁣"];
        checkMark.bordered = NO;
        checkMark.textColor = [[Defaults sharedDefaults] secondaryLabelColor];
        checkMark.drawsBackground = NO;
        checkMark.editable = NO;
        checkMark.hidden = YES;
        checkMark.selectable = NO;
        checkMark.font = [NSFont systemFontOfSize:15.0];

        if (extra != nil) {
            NSMutableDictionary* extraElements = [NSMutableDictionary dictionaryWithDictionary:elements];
            NSTextField* textField = [NSTextField textFieldWithString:extra[@"title"]];
            textField.bordered = NO;
            textField.textColor = [[Defaults sharedDefaults] secondaryLabelColor];
            textField.drawsBackground = NO;
            textField.editable = NO;
            textField.selectable = NO;
            textField.alignment = NSTextAlignmentLeft;

            CGFloat dynamicWidth = textField.attributedStringValue.size.width + kBorderWidth;
            textField.frame = NSMakeRect(x + width,
                                         y - floor((rowUnitHeight - kNormalFontSize) / 2.0f),
                                         dynamicWidth,
                                         (rows * rowUnitHeight) + kRowInset);
            [view addSubview:textField];

            textField = [NSTextField textFieldWithString:@""];
            textField.bordered = editable;
            textField.textColor = [[Defaults sharedDefaults] lightFakeBeamColor];
            textField.drawsBackground = NO;
            textField.editable = editable;
            textField.alignment = NSTextAlignmentLeft;
            if (editable) {
                textField.delegate = self;
            }

            textField.usesSingleLineMode = YES;

            textField.frame = NSMakeRect(x + width + kBorderWidth + dynamicWidth,
                                         y - floor(editable ? 0.0f : (rowUnitHeight - kNormalFontSize) / 2.0f),
                                         width - kBorderWidth,
                                         (rows * rowUnitHeight) + kRowInset);
            [view addSubview:textField];

            extraElements[@"control"] = textField;
            extraElements[@"mark"] = checkMark;

            textField.nextKeyView = lastInputView;
            lastInputView = textField;

            checkMark.frame = NSMakeRect(x + width + kBorderWidth + width + dynamicWidth - 5.0,
                                         y,
                                         20.0,
                                         rowUnitHeight + kRowInset);
            dict[extra[@"key"]] = extraElements;
        } else {
            checkMark.frame = NSMakeRect(x + width - 5.0,
                                         y,
                                         20.0,
                                         rowUnitHeight + kRowInset);
        }
        dict[configKey] = elements;
        elements[@"mark"] = checkMark;
        [view addSubview:checkMark];

        y += (rows * rowUnitHeight) + kRowInset + kRowSpace;
    }
    
    firstInputView.nextKeyView = lastInputView;
    
    _viewControls[pageKey] = dict;

    //y += kRowSpace;
}

-(void)googleArtwork:(id)sender
{
    NSString* insert = [NSString stringWithFormat:@"\"%@\"+\"%@\"", self.commonMeta.title, self.commonMeta.artist];
    NSString* urlPath = [NSString stringWithFormat:@"https://www.google.com/search?tbm=isch&q=%@", insert];
    [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:urlPath]];
}

- (void)loadArtworkWithView:(NSView*)view
{
    const CGFloat imageWidth = 480.0;
//    NSImage* image = [NSImage imageWithSystemSymbolName:@"text.page.badge.magnifyingglass"
//                               accessibilityDescription:nil];
//    NSImageSymbolConfiguration* config = [NSImageSymbolConfiguration configurationWithPointSize:100 weight:NSFontWeightBlack scale:NSImageSymbolScaleLarge];
//    NSImage* imageWithConfig = [image imageWithSymbolConfiguration:config];
//    _googleArtwork = [NSImageView imageViewWithImage:imageWithConfig];
//
//    _googleArtwork.frame = CGRectMake(view.bounds.size.width - 80.0,
//                                      view.bounds.size.height - 85.0,
//                                      40.0,
//                                      40.0f);
//    
//    [_googleArtwork addSymbolEffect:[NSSymbolBreatheEffect effect]
//                            options:[NSSymbolEffectOptions options]
//                           animated:YES];
//
//    [view addSubview:_googleArtwork];

    _largeCoverView = [DragImageFileView new];
    _largeCoverView.image = [NSImage resizedImage:[NSImage imageNamed:@"UnknownSong"] size:NSMakeSize(imageWidth, imageWidth)];
    _largeCoverView.alignment = NSViewHeightSizable | NSViewWidthSizable | NSViewMinYMargin | NSViewMaxYMargin;
    _largeCoverView.imageScaling = NSImageScaleProportionallyUpOrDown;
    _largeCoverView.frame = CGRectMake((self.view.bounds.size.width - (imageWidth + (2 * kViewLeftMargin))) / 2.0f,
                                       kViewTopMargin,
                                       imageWidth,
                                       imageWidth);
    _largeCoverView.wantsLayer = YES;
    _largeCoverView.layer.borderColor = [NSColor separatorColor].CGColor;
    _largeCoverView.layer.borderWidth = 2.0f;
    _largeCoverView.layer.cornerRadius = 7.0f;
    _largeCoverView.layer.masksToBounds = YES;
    [view addSubview:_largeCoverView];
    
    _largeCoverView.delegate = self;
    
    NSArray *dragTypes = [NSArray arrayWithObjects: NSCreateFileContentsPboardType(@"jpeg"),
                                                    NSCreateFileContentsPboardType(@"jpg"),
                                                    NSCreateFileContentsPboardType(@"png"), 
                                                    nil];
    [_largeCoverView registerForDraggedTypes:dragTypes];
    _largeCoverView.allowsCutCopyPaste = YES;
}

- (void)loadLyricsWithView:(NSView*)view
{
    NSScrollView* scrollView = [TextViewWithPlaceholder scrollableTextView];
    self.lyricsTextView = scrollView.documentView;
    scrollView.frame = CGRectMake(  kViewLeftMargin * 2,
                                    kViewTopMargin + 10.0,
                                    self.view.bounds.size.width - 60.0f,
                                    self.view.bounds.size.height - 230.0f);

    _lyricsTextView.textColor = [[Defaults sharedDefaults] lightFakeBeamColor];
    scrollView.drawsBackground = NO;
    scrollView.hasVerticalScroller = YES;
    scrollView.verticalScrollElasticity = NSScrollElasticityNone;
    scrollView.borderType = NSLineBorder;
    _lyricsTextView.editable = YES;
    _lyricsTextView.drawsBackground = NO;
    _lyricsTextView.alignment = NSTextAlignmentLeft;
    _lyricsTextView.delegate = self;
    _lyricsTextView.font = [[Defaults sharedDefaults] normalFont];
    
    [view addSubview:scrollView];
}

- (void)loadView
{
    NSLog(@"loadView");

    self.preferredContentSize = NSMakeSize(600, 700.0);

    const CGFloat imageWidth = 100.0f;
    const CGFloat kRowInset = 4.0f;

//    NSVisualEffectView* view = [[NSVisualEffectView alloc] initWithFrame:NSMakeRect(0.0, 0.0, self.preferredContentSize.width, self.preferredContentSize.height)];
//    view.material = NSVisualEffectMaterialTitlebar;
//    view.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;

    NSView* view = [[NSView alloc] initWithFrame:NSMakeRect(0.0,  0.0, self.preferredContentSize.width, self.preferredContentSize.height)];

    const CGFloat headerHeight = 130.0f;
    _effectBelowHeader = [[NSVisualEffectView alloc] initWithFrame:NSMakeRect(0,
                                                                              self.preferredContentSize.height - (headerHeight - 30.0f),
                                                                              self.preferredContentSize.width,
                                                                              headerHeight)];
    _effectBelowHeader.material = NSVisualEffectMaterialMenu;
    _effectBelowHeader.autoresizingMask = NSViewHeightSizable | NSViewMinXMargin;
    _effectBelowHeader.blendingMode = NSVisualEffectBlendingModeBehindWindow;
    
    CGFloat progressIndicatorWidth = 32;
    CGFloat progressIndicatorHeight = 32;
    _progress = [[NSProgressIndicator alloc] initWithFrame:NSMakeRect((_effectBelowHeader.frame.size.width - progressIndicatorWidth) / 2.0,
                                                                      _effectBelowHeader.frame.size.height - (progressIndicatorHeight + kViewTopMargin),
                                                                      progressIndicatorWidth,
                                                                      progressIndicatorHeight)];
    _progress.style = NSProgressIndicatorStyleSpinning;
    _progress.displayedWhenStopped = NO;
    _progress.autoresizingMask =  NSViewNotSizable | NSViewMinXMargin | NSViewMaxXMargin| NSViewMinYMargin | NSViewMaxYMargin;
    _progress.indeterminate = YES;
    [_effectBelowHeader addSubview:_progress];

    _smallCoverView = [NSImageView imageViewWithImage:[NSImage resizedImage:[NSImage imageNamed:@"UnknownSong"]
                                                                       size:NSMakeSize(imageWidth, imageWidth)]];
    _smallCoverView.alignment = NSViewHeightSizable | NSViewWidthSizable | NSViewMinYMargin | NSViewMaxYMargin;
    _smallCoverView.imageScaling = NSImageScaleProportionallyUpOrDown;
    _smallCoverView.frame = CGRectMake( kViewLeftMargin + kViewLeftMargin,
                                        _effectBelowHeader.frame.size.height - (imageWidth + kViewTopMargin),
                                        imageWidth,
                                        imageWidth);
    _smallCoverView.wantsLayer = YES;
    _smallCoverView.layer.borderColor = [NSColor separatorColor].CGColor;
    _smallCoverView.layer.borderWidth = 2.0f;
    _smallCoverView.layer.cornerRadius = 7.0f;
    _smallCoverView.layer.masksToBounds = YES;

    [_effectBelowHeader addSubview:_smallCoverView];

    CGFloat x = imageWidth + kViewLeftMargin + kViewLeftMargin + kViewLeftMargin;
    CGFloat fieldWidth = _effectBelowHeader.frame.size.width - (imageWidth + 40.0);
    CGFloat y = _effectBelowHeader.frame.size.height - (kViewTopMargin + kViewTopMargin + kBigFontSize);

    NSTextField* textField = [NSTextField textFieldWithString:@""];
    textField.bordered = NO;
    textField.textColor = [[Defaults sharedDefaults] lightFakeBeamColor];
    textField.font = [[Defaults sharedDefaults] bigFont];
    textField.drawsBackground = NO;
    textField.editable = NO;
    textField.selectable = NO;
    textField.cell.truncatesLastVisibleLine = YES;
    textField.cell.lineBreakMode = NSLineBreakByTruncatingTail;
    textField.alignment = NSTextAlignmentLeft;
    textField.frame = NSMakeRect(x,
                                 y,
                                 fieldWidth,
                                 kBigFontSize + kRowInset);
    [_effectBelowHeader addSubview:textField];
    self.titleTextField = textField;

    y -= kBigFontSize + kRowInset - 10.0f;

    textField = [NSTextField textFieldWithString:@""];
    textField.bordered = NO;
    textField.textColor = [[Defaults sharedDefaults] secondaryLabelColor];
    textField.font = [[Defaults sharedDefaults] normalFont];
    textField.drawsBackground = NO;
    textField.editable = NO;
    textField.cell.truncatesLastVisibleLine = YES;
    textField.cell.lineBreakMode = NSLineBreakByTruncatingTail;
    textField.selectable = NO;
    textField.alignment = NSTextAlignmentLeft;
    textField.frame = NSMakeRect(x,
                                 y,
                                 fieldWidth,
                                 kNormalFontSize + kRowInset);
    [_effectBelowHeader addSubview:textField];
    self.artistTextField = textField;

    y -= kNormalFontSize + kRowInset;

    textField = [NSTextField textFieldWithString:@""];
    textField.bordered = NO;
    textField.textColor = [[Defaults sharedDefaults] secondaryLabelColor];
    textField.font = [NSFont systemFontOfSize:kNormalFontSize weight:NSFontWeightRegular];
    textField.drawsBackground = NO;
    textField.editable = NO;
    textField.selectable = NO;
    textField.alignment = NSTextAlignmentLeft;
    
    textField.cell.truncatesLastVisibleLine = YES;
    textField.cell.lineBreakMode = NSLineBreakByTruncatingTail;
    textField.frame = NSMakeRect(x,
                                 y,
                                 fieldWidth,
                                 kNormalFontSize + kRowInset);
    [_effectBelowHeader addSubview:textField];
    self.albumTextField = textField;

    [view addSubview:_effectBelowHeader];

    y = 10.0;
    x = view.frame.size.width - 200.0;

    NSButton* button = [NSButton buttonWithTitle:@"Cancel" target:self action:@selector(cancel:)];
    button.frame = NSMakeRect(x, y, 100.0, 25.0);
    [view addSubview:button];

    x += 100.0;

    button = [NSButton buttonWithTitle:@"OK" target:self action:@selector(okPressed:)];
    button.frame = NSMakeRect(x, y, 100.0, 25.0);
    button.keyEquivalent = @"\r";
    [view addSubview:button];
    
    self.view = view;
}

- (void)viewWillAppear
{
    NSLog(@"InfoPanel becoming visible");

    if (_tabView != nil) {
        [_tabView removeFromSuperview];
    }
    
    self.tabView = [[NSTabView alloc] initWithFrame:NSMakeRect(0.0,
                                                               kViewTopMargin * 2,
                                                               self.view.frame.size.width,
                                                               self.view.frame.size.height - (100.0 + (kViewTopMargin * 2)))];
    self.tabView.delegate = self;
    self.tabView.tabViewBorderType = NSTabViewBorderTypeBezel;
    self.tabView.drawsBackground = YES;
    // For some weird reason the NSColour windowBack.. etc colours do not seem to be
    // actual colours - but just transparent. So we hardcode something here for now.
    //
//    self.tabView.backgroundColor = [NSColor colorWithDeviceRed:228.f/255
//                                                     green:228.f/255
//                                                      blue:228.f/255
//                                                     alpha:1];
//    
//    if (windowBackgroundColor == nil) {
//        self.windowBackgroundColor = [NSColor colorWithDeviceRed:237.f/255
//                                                           green:237.f/255
//                                                            blue:237.f/255
//                                                           alpha:1];
//    }
//    
//    if (bezelColor == nil)
//        self.bezelColor = [NSColor darkGrayColor];
    
    NSViewController* vc = [NSViewController new];
    self.detailsTabViewItem = [NSTabViewItem tabViewItemWithViewController:vc];
    [_detailsTabViewItem setLabel:kInfoPageKeyDetails];
    [self.tabView addTabViewItem:_detailsTabViewItem];
    [self loadControlsWithView:_detailsTabViewItem.view pageKey:kInfoPageKeyDetails];

    vc = [NSViewController new];
    self.artworkTabViewItem = [NSTabViewItem tabViewItemWithViewController:vc];
    [_artworkTabViewItem setLabel:kInfoPageKeyArtwork];
    [self.tabView addTabViewItem:_artworkTabViewItem];
    [self loadArtworkWithView:_artworkTabViewItem.view];

    vc = [NSViewController new];
    self.lyricsTabViewItem = [NSTabViewItem tabViewItemWithViewController:vc];
    [_lyricsTabViewItem setLabel:kInfoPageKeyLyrics];
    [self.tabView addTabViewItem:_lyricsTabViewItem];
    [self loadLyricsWithView:_lyricsTabViewItem.view];

    if ([self.metas count] == 1) {
        vc = [NSViewController new];
        self.fileTabViewItem = [NSTabViewItem tabViewItemWithViewController:vc];
        [_fileTabViewItem setLabel:kInfoPageKeyFile];
        [self.tabView addTabViewItem:_fileTabViewItem];
        [self loadControlsWithView:_fileTabViewItem.view pageKey:kInfoPageKeyFile];
    }

    [self.view addSubview:_tabView];

    if ([_tabView.selectedTabViewItem.label isEqualToString:@"Lyrics"]) {
        [_lyricsTextView.window makeFirstResponder:_lyricsTextView];
    }
    
    self.deltaMeta = [MediaMetaData new];

    _progress.hidden = NO;
    [_progress startAnimation:self];
    
    NSString* const kPatchedMetaKey = @"new";
    NSString* const kOriginalMetaKey = @"old";
    
    _titleTextField.stringValue = @"loading...";
    _artistTextField.stringValue = @"loading...";
    _albumTextField.stringValue = @"loading...";
    // Lets confirm the metadata from the files - iTunes doesnt give us all the
    // beauty we need and it may also rely on outdated informations. iTunes does the
    // same when showing the info from a library entry - it reads up the latest info
    // from the song file metadata.
    dispatch_async(_metaIOQueue, ^{
        NSError* error = nil;
        NSMutableArray* patchedMetas = [NSMutableArray array];
        NSMutableArray* unpatchedMetas = [NSMutableArray array];
        for (MediaMetaData* meta in self.metas) {
            MediaMetaData* patchedMeta = [meta copy];
            if (![patchedMeta readFromFileWithError:&error]) {
                [unpatchedMetas addObject:meta];
                NSLog(@"no metadata found or failed to read with error: %@", error);
                continue;
            }
            if ([meta isEqualToMediaMetaData:patchedMeta]) {
                [unpatchedMetas addObject:meta];
                continue;
            }
            NSMutableDictionary* dict = [NSMutableDictionary dictionary];
            [dict setObject:patchedMeta forKey:kPatchedMetaKey];
            [dict setObject:meta forKey:kOriginalMetaKey];
            [patchedMetas addObject:dict];
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            NSMutableArray* metas = [NSMutableArray arrayWithArray:unpatchedMetas];
            for (NSDictionary* dict in patchedMetas) {
                MediaMetaData* patchedMeta = dict[kPatchedMetaKey];
                MediaMetaData* meta = dict[kOriginalMetaKey];
                [self.delegate metaChangedForMeta:meta 
                                      updatedMeta:patchedMeta];
                [metas addObject:patchedMeta];
            }
            [self.delegate finalizeMetaUpdates];
            
            [self.progress stopAnimation:self];

            self.metas = metas;
        });
    });
}

- (void)viewWillDisappear
{
    [[NSApplication sharedApplication] stopModal];
}

- (void)updateViewHeader:(NSMutableDictionary<NSString*,NSNumber*>*)deltaKeys
              occurances:(NSMutableDictionary<NSString*,NSMutableDictionary*>*)occurances
{
    if (![deltaKeys[@"artwork"] boolValue] && _commonMeta.artwork != nil) {
        _largeCoverView.image = [NSImage resizedImage:[_commonMeta imageFromArtwork] size:_largeCoverView.frame.size];
        _smallCoverView.image = [NSImage resizedImage:[_commonMeta imageFromArtwork] size:_smallCoverView.frame.size];
    } else {
        _largeCoverView.image = [NSImage resizedImage:[NSImage imageNamed:@"UnknownSong"] size:_largeCoverView.frame.size];
        _smallCoverView.image = [NSImage resizedImage:[NSImage imageNamed:@"UnknownSong"] size:_smallCoverView.frame.size];
    }
    
    if ([_metas count] > 1) {
        _titleTextField.stringValue = [NSString stringWithFormat:@"%ld artists selected", [[occurances[@"artist"] allKeys] count] ];
    } else {
        _titleTextField.stringValue = _commonMeta.title == nil ? @"" : _commonMeta.title;
    }
    
    if ([_metas count] > 1) {
        _artistTextField.stringValue = [NSString stringWithFormat:@"%ld albums selected", [[occurances[@"album"] allKeys] count]];
    } else {
        _artistTextField.stringValue =_commonMeta.artist == nil ? @"" : _commonMeta.artist;
    }
    
    if ([_metas count] == 1) {
        _albumTextField.stringValue = _commonMeta.album == nil ? @"" : _commonMeta.album;
    } else {
        _albumTextField.stringValue = [NSString stringWithFormat:@"%ld songs selected", [_metas count]];
    }
}

- (void)updateControlsFromMetas
{
    if (_metas == nil || [_metas count] == 0) {
        return;
    }

    // Identify any meta attribute that is common / not common in the given list of metas.
    // A common meta attribute is one that is universally equally set for all metas in our
    // list.

    // `deltaKeys` is a map of keys to booleans, indicating a meta attribute diverting from
    // other metas in the list.
    NSMutableDictionary<NSString*,NSNumber*>* deltaKeys = [NSMutableDictionary dictionary];
    // `occurances` is a map of keys to dictionaries
    NSMutableDictionary<NSString*,NSMutableDictionary*>* occurances = [NSMutableDictionary dictionary];
    _commonMeta = _metas[0];
    for (size_t index = 0; index < [_metas count]; index++) {
        MediaMetaData* meta = _metas[index];
        for (NSString* key in [MediaMetaData mediaMetaKeys]) {
            if (index > 0) {
                if (![_commonMeta isEqualToMediaMetaData:meta atKey:key]) {
                    deltaKeys[key] = @YES;
                }
            }
            NSMutableDictionary* dictionary = occurances[key];
            if (dictionary == nil) {
                dictionary = [NSMutableDictionary dictionary];
            }
            NSString* stringValue = [meta stringForKey:key];
            dictionary[stringValue] = @YES;
            occurances[key] = dictionary;
        }
    }
    
    // Now that we know all commons and deltas among the metas, we can show it in the header.
    [self updateViewHeader:deltaKeys occurances:occurances];

    //
    if (![deltaKeys[@"lyrics"] boolValue] && _commonMeta.lyrics != nil) {
        [_lyricsTextView setString:_commonMeta.lyrics];
    } else {
        [_lyricsTextView setString:@""];
        if ([deltaKeys[@"lyrics"] boolValue]) {
            NSDictionary* attrs = @{
                NSForegroundColorAttributeName: [[Defaults sharedDefaults] tertiaryLabelColor],
                NSFontAttributeName: [NSFont systemFontOfSize:[NSFont systemFontSize]],
            };
            _lyricsTextView.placeholderAttributedString = [[NSAttributedString alloc] initWithString:kInfoTextMultipleValues
                                                                                          attributes:attrs];
        }
    }
    self.deltaKeys = deltaKeys;

    NSArray<NSString*>* pageKeys = [_viewControls allKeys];

    for (NSString* pageKey in pageKeys) {
        NSArray<NSString*>* keys = [_viewControls[pageKey] allKeys];
        for (NSString* key in keys) {
            NSDictionary* elements = _viewControls[pageKey][key];
            id control = elements[@"control"];
            if (control == nil) {
                continue;
            }
            
            if (![pageKey isEqualToString:kInfoPageKeyDetails] || [deltaKeys objectForKey:key] == nil) {
                // The meta data in question is common - it did not change while editing.
                NSString* value = @"";
                value = [_commonMeta stringForKey:key];
                if (value == nil) {
                    value = @"";
                }
                if ([control respondsToSelector:@selector(selectItemWithTitle:)]) {     // NSPopupButton
                    [control selectItemWithTitle:value];
                } else if ([control respondsToSelector:@selector(setState:)]) {         // NSButton, ...
                    [control setState:[value isEqualToString:@"1"] ? NSControlStateValueOn : NSControlStateValueOff];
                } else if ([control respondsToSelector:@selector(setStringValue:)]) {   // NSTextField, NSComboBox, ...
                    [control setStringValue:value];
                }
            } else {
                // The meta data in question is having mixed states.
                if ([control respondsToSelector:@selector(selectItemWithTitle:)]) {
                    [control selectItemWithTitle:@""];
                } else if ([control respondsToSelector:@selector(setState:)]) {
                    [control setAllowsMixedState:YES];
                    [control setState:NSControlStateValueMixed];
                } else if ([control respondsToSelector:@selector(setStringValue:)]) {
                    [control setStringValue:@""];
                }
                NSString* placeHolder = [_viewConfiguration[kInfoPageKeyDetails][key] objectForKey:@"placeholder"];
                if (placeHolder != nil && [control respondsToSelector:@selector(cell)]) {
                    NSDictionary* attrs = @{
                        NSForegroundColorAttributeName:[[Defaults sharedDefaults] tertiaryLabelColor],
                        NSFontAttributeName:[NSFont systemFontOfSize:[NSFont systemFontSize]],
                    };
                    NSTextFieldCell* cell = [control cell];
                    cell.placeholderAttributedString = [[NSAttributedString alloc] initWithString:placeHolder
                                                                                       attributes:attrs];
                }
            }
        }
    }
}

- (void)setMetas:(NSMutableArray<MediaMetaData*>*)metas
{
    _metas = metas;

    if (self.view == nil) {
        NSLog(@"no view yet - nothing to show");
        return;
    }
    
    if ([_metas count] == 0) {
        NSLog(@"no metas handed over - nothing to show");
        return;
    }
    //
    [self updateControlsFromMetas];

    // Fresh metas did not get mutated just yet.
    self.mutatedKeys = [NSMutableDictionary dictionary];
}

- (void)okPressed:(id)sender
{
    // End all editing.
    [self.view.window makeFirstResponder:nil];

    dispatch_async(_metaIOQueue, ^{
        NSMutableDictionary* patchedMetas = [NSMutableDictionary dictionary];

        for (NSString* key in [self.mutatedKeys allKeys]) {
            NSString* stringValue = nil;
            NSData* dataValue = nil;
            if ([key isEqualToString:@"artwork"]) {
                dataValue = self.deltaMeta.artwork;
                NSLog(@"applying the meta image change");
            } else {
                stringValue = [self.deltaMeta stringForKey:key];
                NSLog(@"applying the meta change for %@ towards \"%@\"", key, stringValue);
            }
            for (MediaMetaData* meta in self.metas) {
                MediaMetaData* patchedMeta = [patchedMetas objectForKey:meta.location];
                if (patchedMeta == nil) {
                    patchedMeta = [meta copy];
                }
                if (dataValue != nil) {
                    patchedMeta.artwork = dataValue;
                    ITLibArtworkFormat format = [MediaMetaData artworkFormatForData:dataValue];
                    patchedMeta.artworkFormat = [NSNumber numberWithInteger:format];
                    patchedMetas[meta.location] = patchedMeta;
                } else if (stringValue != nil) {
                    [patchedMeta updateWithKey:key string:stringValue];
                    patchedMetas[meta.location] = patchedMeta;
                }
            }
        }
        
        dispatch_async(dispatch_get_main_queue(), ^{
            NSError* error = nil;
            for (MediaMetaData* meta in self.metas) {
                MediaMetaData* patchedMeta = [patchedMetas objectForKey:meta.location];
                if (patchedMeta == nil) {
                    NSLog(@"there is no change for %@", meta.location);
                    continue;
                }

                [patchedMeta writeToFileWithError:&error];

                [self.delegate metaChangedForMeta:meta
                                      updatedMeta:patchedMeta];
            }
            [self.delegate finalizeMetaUpdates];
            
            [self.view.window close];
        });
    });
}

- (void)cancel:(id)sender
{
    [self.view.window close];
}

- (void)patchMetasAtKey:(NSString*)key string:(NSString*)stringValue
{
    NSTextField* checkMark = _viewControls[kInfoPageKeyDetails][key][@"mark"];

    // Make sure we need to patch in the first place...
    if (![[_commonMeta stringForKey:key] isEqualToString:stringValue]) {
        _mutatedKeys[key] = @YES;
        [_deltaMeta updateWithKey:key string:stringValue];
        checkMark.hidden = NO;
    } else {
        [_mutatedKeys removeObjectForKey:key];
        checkMark.hidden = YES;
    }
}

- (void)compilationAction:(id)sender
{   
    NSButton* button = (NSButton*)_viewControls[kInfoPageKeyDetails][@"compilation"][@"control"];

    // Even if we signalled allowing mixed state, the user decided and this we stop
    // supporting that.
    [button setAllowsMixedState:NO];

    BOOL value = button.state == NSControlStateValueOn;
    
    NSNumber* number = [NSNumber numberWithBool:value];
    NSString* stringValue = [number stringValue];

    [self patchMetasAtKey:@"compilation" string:stringValue];
}

- (void)didSelectPopupItem:(id)sender
{
    NSPopUpButton* button = sender;
    NSString* stringValue = [[button selectedItem] title];
    
    [self patchMetasAtKey:@"stars" string:stringValue];
}

#pragma mark - NSTextField delegate

- (void)controlTextDidEndEditing:(NSNotification *)notification
{
    NSTextField* textField = [notification object];
    
    NSString *key = nil;
    for (NSString* pageKey in [_viewControls allKeys]) {
        for (NSString* k in [_viewControls[pageKey] allKeys]) {
            if ([[_viewControls[pageKey] valueForKey:k] valueForKey:@"control"] == textField) {
                key = k;
                break;
            }
        }
        if (key != nil) {
            break;
        }
    }
    NSAssert(key != nil, @"couldnt find the key for the control that triggered the notification");
    
    NSString* stringValue = [textField stringValue];
    
    [self patchMetasAtKey:key string:stringValue];
    textField.placeholderAttributedString = nil;
}

- (void)controlTextDidChange:(NSNotification *)notification
{
//    NSTextField* textField = [notification object];
//    NSString *key = nil;
//    for (NSString* k in [_viewControls allKeys]) {
//        if ([_viewControls valueForKey:k] == textField) {
//            key = k;
//            break;
//        }
//    }
//    NSAssert(key != nil, @"couldnt find the key for the control that triggered the notification");

//    textField.placeholderAttributedString = nil;
}

#pragma mark - NSTextView delegate

- (void)textDidEndEditing:(NSNotification *)notification
{
    TextViewWithPlaceholder* textView = [notification object];
    
    NSString* stringValue = textView.string;
    
    [self patchMetasAtKey:@"lyrics" string:stringValue];
    //textView.placeholderAttributedString = nil;
}

#pragma mark - NSComboBox delegate

- (void)comboBoxSelectionDidChange:(NSNotification *)notification
{
    NSComboBox* comboBox = [notification object];

    NSInteger index = [comboBox indexOfSelectedItem];
    NSString* stringValue = @"";
    if (index < 0 || index >= comboBox.numberOfItems) {
        NSLog(@"failed to load items from combobox");
        return;
    }
    stringValue = [self comboBox:comboBox objectValueForItemAtIndex:index];
    
    if (comboBox == _viewControls[kInfoPageKeyDetails][@"genre"][@"control"]) {
        [self patchMetasAtKey:@"genre" string:stringValue];
    }
    if (comboBox == _viewControls[kInfoPageKeyDetails][@"stars"][@"control"]) {
        [self patchMetasAtKey:@"stars" string:stringValue];
    }
}

#pragma mark - NSTabView delegate

- (void)tabView:(NSTabView *)tabView didSelectTabViewItem:(NSTabViewItem *)tabViewItem
{
    if ([tabViewItem.label isEqualToString:@"Lyrics"]) {
        [_lyricsTextView.window makeFirstResponder:_lyricsTextView];
    }
}

#pragma mark - NSComboBoxDataSource

- (NSInteger)numberOfItemsInComboBox:(NSComboBox*)comboBox
{
    if (comboBox == _viewControls[kInfoPageKeyDetails][@"stars"][@"control"]) {
        return [[MediaMetaData starRatings] count];
    }
    if (comboBox == _viewControls[kInfoPageKeyDetails][@"genre"][@"control"]) {
        return [[_delegate knownGenres] count];
    }
//    assert(NO);
    return 0;
}

- (nullable id)comboBox:(NSComboBox*)comboBox objectValueForItemAtIndex:(NSInteger)index
{
    if (comboBox == _viewControls[kInfoPageKeyDetails][@"stars"][@"control"]) {
        return [MediaMetaData starRatings][index];
    }
    if (comboBox == _viewControls[kInfoPageKeyDetails][@"genre"][@"control"]) {
        return [_delegate knownGenres][index];
    }
    //    assert(NO);
    return 0;
}

#pragma mark - DragImageFileViewDelegate

- (BOOL)performDragOperationWithURL:(NSURL*)url
{
    NSData* data = [NSData dataWithContentsOfURL:url];
    if (data == nil) {
        return NO;
    }
    // Handrolled `patchMetaAsKey:string:` for `artwork` data.
    _deltaMeta.artwork = data;
    _mutatedKeys[@"artwork"] = @YES;
    _deltaMeta.artworkFormat = [NSNumber numberWithInteger:[MediaMetaData artworkFormatForData:data]];
    _mutatedKeys[@"artworkFormat"] = @YES;

    NSImage* image = [_deltaMeta imageFromArtwork];
    self.largeCoverView.image = image;
    self.smallCoverView.image = image;

    return YES;
}

@end
