//
//  InfoPanel.m
//  PlayEm
//
//  Created by Till Toenshoff on 15.09.22.
//  Copyright © 2022 Till Toenshoff. All rights reserved.
//

#import "InfoPanel.h"
#import "MediaMetaData.h"

@interface InfoPanelController ()

@property (strong, nonatomic) NSImageView* smallCoverView;
@property (strong, nonatomic) NSImageView* largeCoverView;

@property (strong, nonatomic) NSTextView* lyricsTextView;

@property (strong, nonatomic) NSTabView* tabView;

@property (strong, nonatomic) NSViewController* detailsViewController;
@property (strong, nonatomic) NSViewController* artworkViewController;
@property (strong, nonatomic) NSViewController* lyricsViewController;
@property (strong, nonatomic) NSViewController* fileViewController;

@property (strong, nonatomic) NSDictionary* dictionary;
@property (strong, nonatomic) dispatch_queue_t metaQueue;

@property (strong, nonatomic) MediaMetaData* meta;

@end

@implementation InfoPanelController

- (id)initWithDelegate:(id<InfoPanelControllerDelegate>)delegate
{
    self = [super init];
    if (self) {
        _delegate = delegate;
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

    NSDictionary* config = @{
        @"01 title": @{
            @"width": @340,
        },
        @"02 artist": @{
            @"width": @340,
        },
        @"03 album": @{
            @"width": @340,
        },
        @"04 album artist": @{
            @"width": @340,
            @"key": @"albumArtist",
        },
        @"05 genre": @{
            @"width": @150,
        },
        @"06 year": @{
            @"width": @60,
        },
        @"07 track": @{
            @"width": @40,
            @"extra": @{
                @"title": @"of",
                @"key": @"tracks",
            }
        },
        @"08 disk": @{
            @"width": @40,
            @"extra": @{
                @"title": @"of",
                @"key": @"disks",
            }
        },
        @"09 tempo": @{
            @"width": @40,
            @"extra": @{
                @"title": @"key",
                @"key": @"key",
            }
        },
        @"10 comment": @{
            @"width": @340,
        },
        @"11 location": @{
            @"width": @340,
            @"rows": @4,
            @"editable": @NO,
        },
    };
    NSMutableDictionary* dict = [NSMutableDictionary dictionary];
    
    NSArray* orderedKeys = [[config allKeys] sortedArrayUsingSelector:@selector(compare:)];
    NSEnumerator* reversed = [orderedKeys reverseObjectEnumerator];
    
    CGFloat y = 20.0f;

    for (NSString* key in reversed) {
        NSString* name = [key substringFromIndex:3];

        NSString* configKey = name;
        if ([config[key] objectForKey:@"key"]) {
            configKey = config[key][@"key"];
        }

        NSNumber* number = config[key][@"width"];
        CGFloat width = [number floatValue];
        
        unsigned int rows = 1;
        number = [config[key] objectForKey:@"rows"];
        if (number != nil){
            rows = [number intValue];
        }

        BOOL editable = YES;
        number = [config[key] objectForKey:@"editable"];
        if (number != nil) {
            editable = [number boolValue];
        }

        NSTextField* textField = [NSTextField textFieldWithString:name];
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

        CGFloat x = nameFieldWidth + kBorderWidth + kBorderWidth;

        textField.frame = NSMakeRect(x,
                                     y,
                                     width - kBorderWidth,
                                     (rows * rowUnitHeight) + kRowInset);
        [view addSubview:textField];
        
        dict[configKey] = textField;
        
        NSDictionary* extra = [config[key] objectForKey:@"extra"];

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
    _smallCoverView.frame = CGRectMake( kBorderWidth,
                                        y,
                                        imageWidth,
                                        imageWidth);
    [view addSubview:_smallCoverView];
}

- (void)loadArtworkWithView:(NSView*)view
{
    const CGFloat imageWidth = 400.0;
       
    _largeCoverView = [NSImageView imageViewWithImage:[NSImage imageNamed:@"UnknownSong"]];
    _largeCoverView.alignment = NSViewHeightSizable | NSViewWidthSizable | NSViewMinYMargin | NSViewMaxYMargin;
    _largeCoverView.imageScaling = NSImageScaleProportionallyUpOrDown;
    _largeCoverView.frame = CGRectMake((self.view.bounds.size.width - (imageWidth + 20.0)) / 2.0f,
                                       (self.view.bounds.size.height - (imageWidth + 20.0)) / 2.0f,
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
    NSScrollView* scrollView = [NSTextView scrollableTextView];
    _lyricsTextView = scrollView.documentView;
    scrollView.frame = CGRectMake(10.0f,
                                        10.0f,
                                        self.view.bounds.size.width - 40.0f,
                                        self.view.bounds.size.height - 70.0f);

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

    self.view = [[NSView alloc] initWithFrame:NSMakeRect(0.0,  0.0, 450.0, 540.0)];
    self.tabView = [[NSTabView alloc] initWithFrame:self.view.frame];
    self.tabView.delegate = self;
    
    self.detailsViewController = [[NSViewController alloc] init];
    NSTabViewItem* detailsTabViewItem = [NSTabViewItem tabViewItemWithViewController:_detailsViewController];
    [detailsTabViewItem setLabel:@"Details"];
    [self.tabView addTabViewItem:detailsTabViewItem];

    self.detailsViewController = [[NSViewController alloc] init];
    NSTabViewItem* artworkTabViewItem = [NSTabViewItem tabViewItemWithViewController:_artworkViewController];
    [artworkTabViewItem setLabel:@"Artwork"];
    [self.tabView addTabViewItem:artworkTabViewItem];

    self.lyricsViewController = [[NSViewController alloc] init];
    NSTabViewItem* lyricsTabViewItem = [NSTabViewItem tabViewItemWithViewController:_lyricsViewController];
    [lyricsTabViewItem setLabel:@"Lyrics"];
    [self.tabView addTabViewItem:lyricsTabViewItem];

    self.fileViewController = [[NSViewController alloc] init];
    NSTabViewItem* fileTabViewItem = [NSTabViewItem tabViewItemWithViewController:_fileViewController];
    [fileTabViewItem setLabel:@"File"];
    [self.tabView addTabViewItem:fileTabViewItem];

    [self.view addSubview:_tabView];
    
    [self loadDetailsWithView:detailsTabViewItem.view];
    [self loadArtworkWithView:artworkTabViewItem.view];
    [self loadLyricsWithView:lyricsTabViewItem.view];
    [self loadFileWithView:fileTabViewItem.view];
}

- (void)viewWillAppear
{
    NSLog(@"InfoPanel becoming visible");
    
    MediaMetaData* meta = [_delegate currentSongMeta];
    
    if (meta == nil) {
        NSLog(@"No meta available right now");
        return;
    }
    
    self.meta = meta;
    
    if ([_tabView.selectedTabViewItem.label isEqualToString:@"Lyrics"]) {
        [_lyricsTextView.window makeFirstResponder:_lyricsTextView];
    }
    
    // Lets confirm the metadata from the file itself - iTunes doesnt give us all the
    // beauty we need and it may also rely on outdated informations. iTunes does the
    // same when showing the info from a library entry.
    dispatch_async(_metaQueue, ^{
        NSError* error = nil;
        MediaMetaData* patchedMeta = [self.meta copy];
        if (![patchedMeta readFromFileWithError:&error]) {
            return;
        }
        if (![self.meta isEqualToMediaMetaData:patchedMeta]) {
            [patchedMeta writeToFileWithError:&error];

            dispatch_async(dispatch_get_main_queue(), ^{
                NSLog(@"InfoPanel gathered differing metadata");

                [self.delegate metaChangedForMeta:self.meta updatedMeta:patchedMeta];
                self.meta = patchedMeta;
            });
        }
    });
}

- (void)setMeta:(MediaMetaData*)meta
{
    _meta = meta;

    if (self.view == nil) {
        return;
    }

    if (_meta.artwork != nil) {
        _largeCoverView.image = _meta.artwork;
        _smallCoverView.image = _meta.artwork;
    } else {
        _largeCoverView.image = [NSImage imageNamed:@"UnknownSong"];
        _smallCoverView.image = [NSImage imageNamed:@"UnknownSong"];
    }
    
    if (_meta.lyrics != nil) {
        [_lyricsTextView setString:_meta.lyrics];
    } else {
        [_lyricsTextView setString:@""];
    }

    NSArray<NSString*>* keys = [MediaMetaData mediaMetaKeys];
    
    for (NSString* key in keys) {
        NSTextField* textField = (NSTextField*)_dictionary[key];
        if (textField == nil) {
            continue;
        }

        NSString* value = [_meta stringForKey:key];
        if (value == nil) {
            value = @"";
        }

        textField.stringValue = value;
    }
}

- (BOOL)valueForTextFieldChanged:(NSString*)key value:(NSString*)value
{
    NSString* oldValue = [_meta stringForKey:key];
    
    if (oldValue == nil && [value isEqualToString:@""]) {
        return NO;
    }

    return ![value isEqualToString:oldValue];
}

#pragma mark - NSTextField delegate

- (void)controlTextDidEndEditing:(NSNotification *)notification
{
    NSTextField* textField = [notification object];
    
    MediaMetaData* patchedMeta = [_meta copy];
    
    for (NSString* key in [_dictionary allKeys]) {
        if ([_dictionary valueForKey:key] == textField) {
            if ([self valueForTextFieldChanged:key value:[textField stringValue]]) {
                NSLog(@"controlTextDidChange: stringValue == %@ in textField == %@", [textField stringValue], key);
                NSString* stringValue = [textField stringValue];
                [patchedMeta updateWithKey:key string:stringValue];

                if (![self.meta isEqualToMediaMetaData:patchedMeta]) {
                    NSError* error = nil;
                    [patchedMeta writeToFileWithError:&error];
                    
                    [_delegate metaChangedForMeta:_meta updatedMeta:patchedMeta];
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

    if (_meta == nil) {
        return;
    }
    
    if ([textView.string isEqualToString:_meta.lyrics]) {
        return;
    }
    
    MediaMetaData* patchedMeta = [_meta copy];
    
    [patchedMeta updateWithKey:@"lyrics" string:textView.string];

    NSError* error = nil;
    [patchedMeta writeToFileWithError:&error];
    
    [_delegate metaChangedForMeta:_meta updatedMeta:patchedMeta];
}

#pragma mark - NSTabView delegate

- (void)tabView:(NSTabView *)tabView didSelectTabViewItem:(NSTabViewItem *)tabViewItem
{
    if ([tabViewItem.label isEqualToString:@"Lyrics"]) {
        [_lyricsTextView.window makeFirstResponder:_lyricsTextView];
    }
}

@end
