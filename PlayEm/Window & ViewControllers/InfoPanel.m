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
@property (strong, nonatomic) NSTextField* metaTitle;
@property (strong, nonatomic) NSTextField* metaArtist;
@property (strong, nonatomic) NSTextField* metaAlbum;
@property (strong, nonatomic) NSTextField* metaYear;
@property (strong, nonatomic) NSTextField* metaGenre;
@property (strong, nonatomic) NSTextField* metaBPM;
@property (strong, nonatomic) NSTextField* metaKey;
@property (strong, nonatomic) NSTextField* metaTrack;
@property (strong, nonatomic) NSTextField* metaDisk;
@property (strong, nonatomic) NSTextField* metaLocation;
@property (strong, nonatomic) NSImageView* coverView;

@property (strong, nonatomic) NSDictionary* dictionary;
@end

@implementation InfoPanelController

- (void)loadView
{
    NSLog(@"loadView");

    self.view = [[NSView alloc] initWithFrame:NSMakeRect(0.0,  0.0, 450.0, 740.0)];

    const CGFloat imageWidth = 400.0f;
    const CGFloat nameFieldWidth = 80.0;
    const CGFloat rowUnitHeight = 18.0f;
    const CGFloat kBorderWidth = 5.0;
    const CGFloat kRowInset = 4.0f;
    const CGFloat kRowSpace = 4.0f;

    CGFloat y = 20.0f;
   
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
        @"04 genre": @{
            @"width": @150,
        },
        @"05 year": @{
            @"width": @60,
        },
        @"06 track": @{
            @"width": @40,
        },
        @"07 disk": @{
            @"width": @40,
        },
        @"08 tempo": @{
            @"width": @40,
        },
        @"09 key": @{
            @"width": @40,
        },
        @"10 location": @{
            @"width": @340,
            @"rows": @3,
            @"editable": @NO,
        },
    };
    NSMutableDictionary* dict = [NSMutableDictionary dictionary];
    
    NSArray* orderedKeys = [[config allKeys] sortedArrayUsingSelector:@selector(compare:)];
    for (NSString* key in [orderedKeys reverseObjectEnumerator]) {
        NSString* name = [key substringFromIndex:3];

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
        textField.alignment = NSTextAlignmentRight;
        textField.frame = NSMakeRect(kBorderWidth,
                                     y - floor((rowUnitHeight - 13.0) / 2.0f),
                                     nameFieldWidth,
                                     (rows * rowUnitHeight) + kRowInset);
        [self.view addSubview:textField];
        
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

        textField.frame = NSMakeRect(nameFieldWidth + kBorderWidth + kBorderWidth,
                                     y,
                                     width - kBorderWidth,
                                     (rows * rowUnitHeight) + kRowInset);
        [self.view addSubview:textField];
        
        dict[name] = textField;

        y += (rows * rowUnitHeight) + kRowInset + kRowSpace;
    }
    _dictionary = dict;

    y += kRowSpace;
    
    _coverView = [NSImageView imageViewWithImage:[NSImage imageNamed:@"UnknownSong"]];
    _coverView.alignment = NSViewHeightSizable | NSViewWidthSizable | NSViewMinYMargin | NSViewMaxYMargin;
    _coverView.imageScaling = NSImageScaleProportionallyUpOrDown;
    _coverView.frame = CGRectMake((self.view.bounds.size.width - imageWidth) / 2.0f ,
                                  y,
                                  imageWidth,
                                  imageWidth);
    [self.view addSubview:_coverView];
}

- (void)setMeta:(MediaMetaData*)meta
{
    _meta = meta;

    if (self.view == nil) {
        return;
    }

    if (_meta.artwork) {
        _coverView.image = _meta.artwork;
    }

    NSArray<NSString*>* keys = [MediaMetaData mediaMetaKeys];
    
    for (NSString* key in keys) {
        NSTextField* textField = (NSTextField*)_dictionary[key];
        if (textField == nil) {
            continue;
        }
        NSString* value = [_meta stringForKey:key];
        if (value == nil) {
            continue;
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

- (void)controlTextDidEndEditing:(NSNotification *)notification
{
    NSTextField* textField = [notification object];
    
    for (NSString* key in [_dictionary allKeys]) {
        if ([_dictionary valueForKey:key] == textField) {
            if ([self valueForTextFieldChanged:key value:[textField stringValue]]) {
                NSLog(@"controlTextDidChange: stringValue == %@ in textField == %@", [textField stringValue], key);
                NSString* stringValue = [textField stringValue];
                [_meta updateWithKey:key string:stringValue];

                NSError* error = nil;
                [_meta syncToFileWithError:&error];
                
                if (_delegate) {
                    [_delegate metaChanged:_meta];
                }
            }
            return;
        }
    }

    NSAssert(NO, @"never should have arrived here");
}

@end
