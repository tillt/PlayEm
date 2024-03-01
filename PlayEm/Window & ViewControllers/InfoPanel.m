//
//  InfoPanel.m
//  PlayEm
//
//  Created by Till Toenshoff on 15.09.22.
//  Copyright © 2022 Till Toenshoff. All rights reserved.
//

#import "InfoPanel.h"
#import "MediaMetaData.h"
#import "TextViewWithPlaceholder.h"

typedef enum : NSUInteger {
    InfoControlTypeText,
    InfoControlTypeCombo,
    InfoControlTypeCheck,
} InfoControlType;

NSString* const kInfoPageKeyDetails = @"Details";
NSString* const kInfoPageKeyArtwork = @"Artwork";
NSString* const kInfoPageKeyLyrics = @"Lyrics";
NSString* const kInfoPageKeyFile = @"File";

NSString* const kInfoTextMultipleValues = @"Mixed";
NSString* const kInfoNumberMultipleValues = @"-";

@interface InfoPanelController ()

@property (strong, nonatomic) NSImageView* smallCoverView;
@property (strong, nonatomic) NSImageView* largeCoverView;

@property (strong, nonatomic) TextViewWithPlaceholder* lyricsTextView;

@property (strong, nonatomic) NSTabView* tabView;

@property (strong, nonatomic) NSTabViewItem* detailsTabViewItem;
@property (strong, nonatomic) NSTabViewItem* artworkTabViewItem;
@property (strong, nonatomic) NSTabViewItem* lyricsTabViewItem;
@property (strong, nonatomic) NSTabViewItem* fileTabViewItem;

@property (strong, nonatomic) NSDictionary* dictionary;
@property (strong, nonatomic) dispatch_queue_t metaQueue;

@property (strong, nonatomic) NSArray<MediaMetaData*>* metas;

@property (strong, nonatomic) MediaMetaData* deltaMeta;
@property (strong, nonatomic) MediaMetaData* commonMeta;

@property (strong, nonatomic) NSDictionary* viewConfiguration;

@end

@implementation InfoPanelController

- (id)initWithDelegate:(id<InfoPanelControllerDelegate>)delegate
{
    self = [super init];
    if (self) {
        _delegate = delegate;

        _viewConfiguration = @{
            kInfoPageKeyDetails: @{
                @"title": @{
                    @"order": @1,
                    @"width": @340,
                    @"placeholder": kInfoTextMultipleValues,
                },
                @"artist": @{
                    @"order": @2,
                    @"width": @340,
                    @"placeholder": kInfoTextMultipleValues,
                },
                @"album": @{
                    @"order": @3,
                    @"width": @340,
                    @"placeholder": kInfoTextMultipleValues,
                },
                @"album artist": @{
                    @"order": @4,
                    @"width": @340,
                    @"key": @"albumArtist",
                    @"placeholder": kInfoTextMultipleValues,
                },
                @"genre": @{
                    @"order": @5,
                    @"width": @180,
                    @"type": @(InfoControlTypeCombo),
                    @"placeholder": kInfoTextMultipleValues,
                },
                @"year": @{
                    @"order": @6,
                    @"width": @60,
                    @"placeholder": kInfoNumberMultipleValues,
                },
                @"track": @{
                    @"order": @7,
                    @"width": @40,
                    @"placeholder": kInfoNumberMultipleValues,
                    @"extra": @{
                        @"title": @"of",
                        @"key": @"tracks",
                    }
                },
                @"disk": @{
                    @"order": @8,
                    @"width": @40,
                    @"placeholder": kInfoNumberMultipleValues,
                    @"extra": @{
                        @"title": @"of",
                        @"key": @"disks",
                    }
                },
                @"compilation": @{
                    @"order": @9,
                    @"width": @340,
                    @"description": @"Album is a compilation of songs by various artists",
                    @"type": @(InfoControlTypeCheck),
                },
                @"tempo": @{
                    @"order": @10,
                    @"width": @40,
                    @"placeholder": kInfoNumberMultipleValues,
                    @"extra": @{
                        @"title": @"key",
                        @"key": @"key",
                    }
                },
                @"comment": @{
                    @"order": @11,
                    @"width": @340,
                    @"placeholder": kInfoTextMultipleValues,
                },
            },
            kInfoPageKeyFile: @{
                @"location": @{
                    @"order": @12,
                    @"width": @340,
                    @"rows": @4,
                    @"editable": @NO,
                },
            },
        };
        
        dispatch_queue_attr_t attr = dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL,
                                                                             QOS_CLASS_USER_INTERACTIVE,
                                                                             0);
        _metaQueue = dispatch_queue_create("PlayEm.MetaQueue", attr);
    }
    return self;
}

- (void)loadDetailsWithView:(NSView*)view
{
    const CGFloat imageWidth = 120.0f;
    const CGFloat nameFieldWidth = 80.0;
    const CGFloat rowUnitHeight = 18.0f;
    const CGFloat kBorderWidth = 5.0;
    const CGFloat kRowInset = 4.0f;
    const CGFloat kRowSpace = 4.0f;

    NSMutableDictionary* dict = [NSMutableDictionary dictionary];
    
    NSArray* orderedKeys = [_viewConfiguration[kInfoPageKeyDetails] keysSortedByValueUsingComparator:^(id obj1, id obj2){
        NSNumber *rank1 = [obj1 valueForKeyPath:@"order"];
        NSNumber *rank2 = [obj2 valueForKeyPath:@"order"];
        return (NSComparisonResult)[rank1 compare:rank2];
    }];
    
    NSEnumerator* reversed = [orderedKeys reverseObjectEnumerator];
    
    CGFloat y = 20.0f;
    
    NSString* pageKey = kInfoPageKeyDetails;

    for (NSString* key in reversed) {
        NSString* configKey = key;
        if ([_viewConfiguration[pageKey][key] objectForKey:@"key"]) {
            configKey = _viewConfiguration[pageKey][key][@"key"];
        }

        NSNumber* number = _viewConfiguration[pageKey][key][@"width"];
        CGFloat width = [number floatValue];
        
        unsigned int rows = 1;
        number = [_viewConfiguration[pageKey][key] objectForKey:@"rows"];
        if (number != nil){
            rows = [number intValue];
        }
        
        number = [_viewConfiguration[pageKey][key] objectForKey:@"type"];
        InfoControlType type = InfoControlTypeText;
        if (number != nil){
            type = [number intValue];
        }

        BOOL editable = YES;
        number = [_viewConfiguration[pageKey][key] objectForKey:@"editable"];
        if (number != nil) {
            editable = [number boolValue];
        }
        
        NSTextField* textField = [NSTextField textFieldWithString:key];
        textField.bordered = NO;
        textField.textColor = [NSColor secondaryLabelColor];
        textField.drawsBackground = NO;
        textField.editable = NO;
        textField.selectable = NO;
        textField.alignment = NSTextAlignmentRight;
        textField.frame = NSMakeRect(kBorderWidth,
                                     y - floor((rowUnitHeight - 13.0) / 2.0f),
                                     nameFieldWidth,
                                     (rows * rowUnitHeight) + kRowInset);
        [view addSubview:textField];

        CGFloat x = nameFieldWidth + kBorderWidth + kBorderWidth;

        switch (type) {
            case InfoControlTypeText: {
                textField = [NSTextField textFieldWithString:@""];
                textField.bordered = editable;
                textField.textColor = [NSColor labelColor];
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
                                             y,
                                             width - kBorderWidth,
                                             (rows * rowUnitHeight) + kRowInset);
                [view addSubview:textField];
                
                dict[configKey] = textField;
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
                
                dict[configKey] = comboBox;
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
                
                dict[configKey] = button;
            } break;
        }
        
        NSDictionary* extra = [_viewConfiguration[pageKey][key] objectForKey:@"extra"];

        if (extra != nil) {
            NSTextField* textField = [NSTextField textFieldWithString:extra[@"title"]];
            textField.bordered = NO;
            textField.textColor = [NSColor secondaryLabelColor];
            textField.drawsBackground = NO;
            textField.editable = NO;
            textField.selectable = NO;
            textField.alignment = NSTextAlignmentLeft;
            CGFloat dynamicWidth = textField.attributedStringValue.size.width + kBorderWidth;
            textField.frame = NSMakeRect(x + width,
                                         y - floor((rowUnitHeight - 13.0) / 2.0f),
                                         dynamicWidth,
                                         (rows * rowUnitHeight) + kRowInset);
            [view addSubview:textField];

            textField = [NSTextField textFieldWithString:@""];
            textField.bordered = editable;
            textField.textColor = [NSColor labelColor];
            textField.drawsBackground = NO;
            textField.editable = editable;
            textField.alignment = NSTextAlignmentLeft;
            if (editable) {
                textField.delegate = self;
            }

            textField.usesSingleLineMode = YES;

            textField.frame = NSMakeRect(x + width + kBorderWidth + dynamicWidth,
                                         y,
                                         width - kBorderWidth,
                                         (rows * rowUnitHeight) + kRowInset);
            [view addSubview:textField];

            dict[extra[@"key"]] = textField;
        }

        y += (rows * rowUnitHeight) + kRowInset + kRowSpace;
    }
    _dictionary = dict;

    y += kRowSpace;
    
    _smallCoverView = [NSImageView imageViewWithImage:[NSImage imageNamed:@"UnknownSong"]];
    _smallCoverView.alignment = NSViewHeightSizable | NSViewWidthSizable | NSViewMinYMargin | NSViewMaxYMargin;
    _smallCoverView.imageScaling = NSImageScaleProportionallyUpOrDown;
    _smallCoverView.frame = CGRectMake( 20.0,
                                        y,
                                        imageWidth,
                                        imageWidth);
    [view addSubview:_smallCoverView];
}

- (void)loadArtworkWithView:(NSView*)view
{
    const CGFloat imageWidth = self.view.bounds.size.width - 80.0;
       
    _largeCoverView = [NSImageView imageViewWithImage:[NSImage imageNamed:@"UnknownSong"]];
    _largeCoverView.alignment = NSViewHeightSizable | NSViewWidthSizable | NSViewMinYMargin | NSViewMaxYMargin;
    _largeCoverView.imageScaling = NSImageScaleProportionallyUpOrDown;
    _largeCoverView.frame = CGRectMake((self.view.bounds.size.width - (imageWidth + 40.0)) / 2.0f,
                                       (self.view.bounds.size.height - (imageWidth + 60.0)) / 2.0f,
                                       imageWidth,
                                       imageWidth);
    _largeCoverView.wantsLayer = YES;
    _largeCoverView.layer.borderColor = [NSColor separatorColor].CGColor;
    _largeCoverView.layer.borderWidth = 1.0f;
    _largeCoverView.layer.cornerRadius = 7.0f;
    _largeCoverView.layer.masksToBounds = YES;
    
    [view addSubview:_largeCoverView];
}

- (void)loadLyricsWithView:(NSView*)view
{
    NSScrollView* scrollView = [TextViewWithPlaceholder scrollableTextView];
    self.lyricsTextView = scrollView.documentView;
    scrollView.frame = CGRectMake(  20.0f,
                                    20.0f,
                                    self.view.bounds.size.width - 80.0f,
                                    self.view.bounds.size.height - 100.0f);

    _lyricsTextView.textColor = [NSColor labelColor];
    scrollView.drawsBackground = NO;
    scrollView.hasVerticalScroller = YES;
    scrollView.verticalScrollElasticity = NSScrollElasticityNone;
    scrollView.borderType = NSLineBorder;
    _lyricsTextView.editable = YES;
    _lyricsTextView.drawsBackground = NO;
    _lyricsTextView.alignment = NSTextAlignmentLeft;
    _lyricsTextView.delegate = self;
    _lyricsTextView.font = [NSFont systemFontOfSize:13.0f];
    
    [view addSubview:scrollView];
}

- (void)loadFileWithView:(NSView*)view
{
}

- (void)loadView
{
    NSLog(@"loadView");

    self.view = [[NSView alloc] initWithFrame:NSMakeRect(0.0,  0.0, 480.0, 510.0)];
}

- (void)viewWillAppear
{
    NSLog(@"InfoPanel becoming visible");
    
    NSMutableArray* metas = [NSMutableArray arrayWithArray:[_delegate selectedSongMetas]];
    
    if (metas == nil) {
        NSLog(@"No meta available right now");
        return;
    }

    if (_tabView != nil) {
        [_tabView removeFromSuperview];
    }
    
    self.tabView = [[NSTabView alloc] initWithFrame:NSMakeRect(10.0, 10.0, self.view.frame.size.width - 20.0, self.view.frame.size.height - 20.0)];
    self.tabView.delegate = self;
    
    NSViewController* vc = [NSViewController new];
    self.detailsTabViewItem = [NSTabViewItem tabViewItemWithViewController:vc];
    [_detailsTabViewItem setLabel:kInfoPageKeyDetails];
    [self.tabView addTabViewItem:_detailsTabViewItem];
    [self loadDetailsWithView:_detailsTabViewItem.view];

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

    if ([metas count] == 1) {
        vc = [NSViewController new];
        self.fileTabViewItem = [NSTabViewItem tabViewItemWithViewController:vc];
        [_fileTabViewItem setLabel:kInfoPageKeyFile];
        [self.tabView addTabViewItem:_fileTabViewItem];
        [self loadFileWithView:_fileTabViewItem.view];
    }

    [self.view addSubview:_tabView];

    self.metas = metas;
    
    if ([_tabView.selectedTabViewItem.label isEqualToString:@"Lyrics"]) {
        [_lyricsTextView.window makeFirstResponder:_lyricsTextView];
    }
    
    // Lets confirm the metadata from the file itself - iTunes doesnt give us all the
    // beauty we need and it may also rely on outdated informations. iTunes does the
    // same when showing the info from a library entry.
    dispatch_async(_metaQueue, ^{
        NSError* error = nil;
        
        //NSMutableArray* patchedMetas = [NSMutableArray array];
        for (MediaMetaData* meta in self.metas) {
            MediaMetaData* patchedMeta = [meta copy];
            if (![patchedMeta readFromFileWithError:&error]) {
                return;
            }
            if (![meta isEqualToMediaMetaData:patchedMeta]) {
                [patchedMeta writeToFileWithError:&error];
                
                //NSMutableArray* patchedMetas = [NSMutableArray array];
                dispatch_async(dispatch_get_main_queue(), ^{
                    NSLog(@"InfoPanel gathered differing metadata");
                    [self.delegate metaChangedForMeta:meta updatedMeta:patchedMeta];
                });
            }
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            self.metas = [self.delegate selectedSongMetas];
        });
    });
}

- (void)setMetas:(NSMutableArray<MediaMetaData*>*)metas
{
    _metas = metas;

    if (self.view == nil) {
        return;
    }
    
    if ([_metas count] == 0) {
        return;
    }

    // Identify any meta that is common / not common in the given list.
    NSMutableDictionary<NSString*,NSNumber*>* deltaKeys = [NSMutableDictionary dictionary];
    NSMutableDictionary<NSString*,NSNumber*>* commonKeys = [NSMutableDictionary dictionary];
    _commonMeta = _metas[0];
    for (size_t index = 1; index < [_metas count]; index++) {
        MediaMetaData* meta = _metas[index];
        for (NSString* key in [MediaMetaData mediaMetaKeys]) {
            if (![_commonMeta isEqualToMediaMetaData:meta atKey:key]) {
                deltaKeys[key] = @YES;
            } else {
                commonKeys[key] = @YES;
            }
        }
    }
 
    if (![deltaKeys[@"artwork"] boolValue] && _commonMeta.artwork != nil) {
        _largeCoverView.image = _commonMeta.artwork;
        _smallCoverView.image = _commonMeta.artwork;
    } else {
        _largeCoverView.image = [NSImage imageNamed:@"UnknownSong"];
        _smallCoverView.image = [NSImage imageNamed:@"UnknownSong"];
    }
    
    if (![deltaKeys[@"lyrics"] boolValue] && _commonMeta.lyrics != nil) {
        [_lyricsTextView setString:_commonMeta.lyrics];
    } else {
        [_lyricsTextView setString:@""];
        if ([deltaKeys[@"lyrics"] boolValue]) {
            NSColor* color = [NSColor tertiaryLabelColor];
            NSDictionary* attrs = @{
                NSForegroundColorAttributeName: color,
            };
            _lyricsTextView.placeholderAttributedString = [[NSAttributedString alloc] initWithString:kInfoTextMultipleValues
                                                                                          attributes:attrs];
        }
    }

    NSArray<NSString*>* keys = [_dictionary allKeys];
    
    for (NSString* key in keys) {
        id control = _dictionary[key];
        
        control = _dictionary[key];
        if (control == nil) {
            continue;
        }

        if ([deltaKeys objectForKey:key] == nil) {
            NSString* value = @"";
            value = [_commonMeta stringForKey:key];
            if (value == nil) {
                value = @"";
            }
            if ([control respondsToSelector:@selector(setState:)]) {
                [control setState:[value isEqualToString:@"1"] ? NSControlStateValueOn : NSControlStateValueOff];
            } else if ([control respondsToSelector:@selector(setStringValue:)]) {
                [control setStringValue:value];
            }
        } else {
            if ([control respondsToSelector:@selector(setState:)]) {
                [control setAllowsMixedState:YES];
                [control setState:NSControlStateValueMixed];
            } else if ([control respondsToSelector:@selector(setStringValue:)]) {
                [control setStringValue:@""];
            }
            NSString* placeHolder = [_viewConfiguration[kInfoPageKeyDetails][key] objectForKey:@"placeholder"];
            if (placeHolder != nil && [control respondsToSelector:@selector(cell)]) {
                NSColor* color = [NSColor tertiaryLabelColor];
                NSDictionary* attrs = @{
                    NSForegroundColorAttributeName: color,
                };
                NSTextFieldCell* cell = [control cell];
                cell.placeholderAttributedString = [[NSAttributedString alloc] initWithString:placeHolder
                                                                                   attributes:attrs];
            }
        }
    }
}

- (BOOL)valueForTextFieldChanged:(NSString*)key value:(NSString*)value
{
    NSString* oldValue = [_commonMeta stringForKey:key];
    
    if (oldValue == nil && [value isEqualToString:@""]) {
        return NO;
    }

    return ![value isEqualToString:oldValue];
}

- (void)compilationAction:(id)sender
{
    NSString* oldValue = [_commonMeta stringForKey:@"compilation"];
    NSButton* button = (NSButton*)_dictionary[@"compilation"];

    // Even if we signalled allowing mixed state, the user decided and this we stop
    // supporting that.
    [button setAllowsMixedState:NO];

    BOOL value = button.state == NSControlStateValueOn;
    
    if (_commonMeta == nil) {
        return;
    }
    NSNumber* number = [NSNumber numberWithBool:value];
    if ([[number stringValue] isEqualToString:oldValue]) {
        return;
    }
    
    MediaMetaData* patchedMeta = [_commonMeta copy];
    
    patchedMeta.compilation = number;

    NSError* error = nil;
    [patchedMeta writeToFileWithError:&error];
    
    //[_delegate metaChangedForMeta:_meta updatedMeta:patchedMeta];
    _commonMeta.compilation = patchedMeta.compilation;
}

#pragma mark - NSTextField delegate

- (void)controlTextDidEndEditing:(NSNotification *)notification
{
    NSTextField* textField = [notification object];
    
    MediaMetaData* patchedMeta = [_commonMeta copy];

    NSString *key = nil;
    for (NSString* k in [_dictionary allKeys]) {
        if ([_dictionary valueForKey:k] == textField) {
            key = k;
            break;
        }
    }
    NSAssert(key != nil, @"couldnt find the key for the control that triggered the notification");
    
    for (NSString* key in [_dictionary allKeys]) {
        if ([_dictionary valueForKey:key] == textField) {
            if ([self valueForTextFieldChanged:key value:[textField stringValue]]) {
                NSLog(@"controlTextDidChange: stringValue == %@ in textField == %@", [textField stringValue], key);
                NSString* stringValue = [textField stringValue];
                [patchedMeta updateWithKey:key string:stringValue];

                if (![_commonMeta isEqualToMediaMetaData:patchedMeta]) {
                    NSError* error = nil;
                    [patchedMeta writeToFileWithError:&error];
                    
                    //[_delegate metaChangedForMeta:_meta updatedMeta:patchedMeta];
                    //self.meta = patchedMeta;
                    [_commonMeta updateWithKey:key string:stringValue];
                }
            }
            return;
        }
    }

    NSAssert(NO, @"never should have arrived here");
}

#pragma mark - NSTextView delegate

- (void)textDidEndEditing:(NSNotification *)notification
{
    NSTextView* textView = [notification object];

    if (_commonMeta == nil) {
        return;
    }
    
    if ([textView.string isEqualToString:_commonMeta.lyrics]) {
        return;
    }
    
    MediaMetaData* patchedMeta = [_commonMeta copy];
    
    [patchedMeta updateWithKey:@"lyrics" string:textView.string];

    NSError* error = nil;
    [patchedMeta writeToFileWithError:&error];
    
    //[_delegate metaChangedForMeta:_meta updatedMeta:patchedMeta];
    //self.meta = patchedMeta;
    [_commonMeta updateWithKey:@"lyrics" string:textView.string];
}

#pragma mark - NSComboBox delegate

- (void)comboBoxSelectionDidChange:(NSNotification *)notification
{
    [self controlTextDidEndEditing:notification];
}

#pragma mark - NSTabView delegate

- (void)tabView:(NSTabView *)tabView didSelectTabViewItem:(NSTabViewItem *)tabViewItem
{
    if ([tabViewItem.label isEqualToString:@"Lyrics"]) {
        [_lyricsTextView.window makeFirstResponder:_lyricsTextView];
    }
}

#pragma mark - NSComboBoxDataSource

- (NSInteger)numberOfItemsInComboBox:(NSComboBox *)comboBox
{
    return [[_delegate knownGenres] count];
}

- (nullable id)comboBox:(NSComboBox *)comboBox objectValueForItemAtIndex:(NSInteger)index
{
    return [_delegate knownGenres][index];
}

@end
