//
//  IdentifyController.m
//  PlayEm
//
//  Created by Till Toenshoff on 01.12.22.
//  Copyright © 2022 Till Toenshoff. All rights reserved.
//

#import "IdentifyController.h"
#import <ShazamKit/ShazamKit.h>

#import "AudioController.h"
#import "LazySample.h"

@interface IdentifyController ()

@property (weak, nonatomic) AudioController* audioController;
@property (strong, nonatomic) SHSession* session;

@property (strong, nonatomic) AVAudioPCMBuffer* stream;

@property (strong, nonatomic) NSTextField* genreField;

@property (strong, nonatomic) NSTextField* titleField;
@property (strong, nonatomic) NSImageView* coverView;
@property (strong, nonatomic) NSButton* clipButton;
@property (strong, nonatomic) NSButton* scButton;

@property (strong, nonatomic) NSURL* imageURL;
@property (strong, nonatomic) NSURL* musicURL;

@property (strong, nonatomic) NSProgressIndicator* matchingIndicator;
@property (strong, nonatomic) dispatch_queue_t identifyQueue;

@end

@implementation IdentifyController

- (id)initWithAudioController:(AudioController *)audioController
{
    self = [super init];
    if (self) {
        _audioController = audioController;
        dispatch_queue_attr_t attr = dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL, QOS_CLASS_USER_INITIATED, 0);
        _identifyQueue = dispatch_queue_create("PlayEm.IdentifyQueue", attr);
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do view setup here.
    NSLog(@"viewDidLoad");

}

- (void)popoverDidShow:(NSNotification *)notification
{
    NSLog(@"popoverDidShow");
    [self shazam:self];
}

- (void)popoverDidClose:(NSNotification *)notification
{
    NSLog(@"popoverDidClose");
    [_audioController stopTapping];
    [self reset];
}

- (void)loadView
{
    NSLog(@"loadView");
 
    const CGFloat kPopoverWidth = 300.0f;
    const CGFloat kPopoverHeight = 380.0f;
    
    const CGFloat kBorderWidth = 20.0f;
    const CGFloat kBorderHeight = 20.0f;
    const CGFloat kRowSpace = 4.0f;
    
    const CGFloat kTitleFontSize = 19.0f;
    const CGFloat kGenreFontSize = 13.0f;
    const CGFloat kCopyButtonFontSize = kGenreFontSize;

    const CGFloat kIndicatorWidth = kTitleFontSize;
    const CGFloat kIndicatorHeight = kIndicatorWidth;
    
    const CGFloat kTextFieldWidth = kPopoverWidth - (2.0f * kBorderWidth);
    const CGFloat kTextFieldHeight = kTitleFontSize + 8.0f;

    const CGFloat kCoverViewWidth = 260.0;
    const CGFloat kCoverViewHeight = kCoverViewWidth;

    self.view = [[NSView alloc] initWithFrame:NSMakeRect(0.0, 0.0, kPopoverWidth, kPopoverHeight)];
    
    CGFloat y = kPopoverHeight - (kCoverViewHeight + kBorderHeight);
    
    _coverView = [[NSImageView alloc] initWithFrame:NSMakeRect(floorf((kPopoverWidth - kCoverViewWidth) / 2.0f),
                                                               y,
                                                               kCoverViewWidth,
                                                               kCoverViewHeight)];
    _coverView.image = [NSImage imageNamed:@"UnknownSong"];
    _coverView.imageScaling = NSImageScaleProportionallyUpOrDown;
    _coverView.wantsLayer = YES;
    _coverView.layer.cornerRadius = 7;
    _coverView.layer.masksToBounds = YES;
    [_coverView setAction:@selector(musicURLClicked:)];

    [self.view addSubview:_coverView];

    y -= kTextFieldHeight + kRowSpace + kRowSpace + kRowSpace;

    _clipButton = [NSButton buttonWithTitle:@"􀫵" target:self action:@selector(copyTitle:)];
    _clipButton.font = [NSFont systemFontOfSize:kCopyButtonFontSize];
    _clipButton.bordered = NO;
    [_clipButton setButtonType:NSButtonTypeMomentaryPushIn];
    _clipButton.bezelStyle = NSBezelStyleTexturedRounded;
    _clipButton.frame = NSMakeRect(kPopoverWidth - (kCopyButtonFontSize + kBorderWidth),
                                  y,
                                  kCopyButtonFontSize + kBorderWidth,
                                  kTextFieldHeight);
    [self.view addSubview:_clipButton];

    y -= kTextFieldHeight;

    _scButton = [NSButton buttonWithTitle:@"􀙀" target:self action:@selector(openSoundcloud:)];
    _scButton.font = [NSFont systemFontOfSize:kCopyButtonFontSize];
    _scButton.bordered = NO;
    [_scButton setButtonType:NSButtonTypeMomentaryPushIn];
    _scButton.bezelStyle = NSBezelStyleTexturedRounded;
    _scButton.frame = NSMakeRect(kPopoverWidth - (kCopyButtonFontSize + kBorderWidth),
                                  y,
                                  kCopyButtonFontSize + kBorderWidth,
                                  kTextFieldHeight);
    [self.view addSubview:_scButton];

    _titleField = [NSTextField textFieldWithString:@"???"];
    _titleField.bordered = NO;
    _titleField.editable = NO;
    _titleField.selectable = YES;
    _titleField.usesSingleLineMode = NO;
    _titleField.cell.wraps = YES;
    _titleField.cell.scrollable = NO;
    _titleField.font = [NSFont systemFontOfSize:kTitleFontSize];
    _titleField.textColor = [NSColor secondaryLabelColor];
    _titleField.drawsBackground = NO;
    _titleField.alignment = NSTextAlignmentLeft;
    _titleField.lineBreakMode = NSLineBreakByWordWrapping;
    _titleField.frame = NSMakeRect(kBorderWidth,
                                   y,
                                   kTextFieldWidth - kCopyButtonFontSize,
                                   kTextFieldHeight * 2.0f);
    _titleField.preferredMaxLayoutWidth = _titleField.frame.size.width;
    [self.view addSubview:_titleField];

    y -= kTextFieldHeight + kRowSpace;

    _genreField = [NSTextField textFieldWithString:@""];
    _genreField.bordered = NO;
    _genreField.editable = NO;
    _genreField.selectable = YES;
    _genreField.font = [NSFont systemFontOfSize:kGenreFontSize];
    _genreField.textColor = [NSColor secondaryLabelColor];
    _genreField.drawsBackground = NO;
    _genreField.alignment = NSTextAlignmentLeft;
    _genreField.frame = NSMakeRect(kBorderWidth,
                                   y,
                                   kTextFieldWidth,
                                   kTextFieldHeight);
    [self.view addSubview:_genreField];

    y += kRowSpace;

    _matchingIndicator = [[NSProgressIndicator alloc] initWithFrame:NSMakeRect(kPopoverWidth - (kBorderWidth + kIndicatorWidth),
                                                                               y,
                                                                               kIndicatorWidth,
                                                                               kIndicatorHeight)];
    _matchingIndicator.style = NSProgressIndicatorStyleSpinning;
    _matchingIndicator.displayedWhenStopped = NO;
    _matchingIndicator.autoresizingMask =  NSViewNotSizable | NSViewMinXMargin | NSViewMaxXMargin| NSViewMinYMargin | NSViewMaxYMargin;
    [self.view addSubview:_matchingIndicator];
    [_matchingIndicator startAnimation:self];
}

- (void)copyTitle:(id)sender
{
    [[NSPasteboard generalPasteboard] clearContents];
    [[NSPasteboard generalPasteboard] setString:_titleField.stringValue forType:NSPasteboardTypeString];
}

- (void)openSoundcloud:(id)sender
{
    NSString* title = [_titleField.stringValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    title = [title stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLFragmentAllowedCharacterSet]];
    NSURL* queryURL = [NSURL URLWithString:[NSString stringWithFormat:@"https://soundcloud.com/search?q=%@", title]];
    NSURL* appURL = [[NSWorkspace sharedWorkspace] URLForApplicationToOpenURL:queryURL];
    NSWorkspaceOpenConfiguration* configuration = [[NSWorkspaceOpenConfiguration alloc] init];
    [[NSWorkspace sharedWorkspace] openURLs:[NSArray arrayWithObject:queryURL] withApplicationAtURL:appURL configuration:configuration completionHandler:^(NSRunningApplication* app, NSError* error){
    }];
}

- (void)musicURLClicked:(id)sender
{
    NSLog(@"opening %@", _musicURL);
    // For making sure this wont open Music.app we fetch the
    // default app for URLs.
    // With that we explicitly call the browser for opening the
    // URL. That way we get things displayed even in cases where
    // Music.app does not show iCloud.Music.
    NSURL* appURL = [[NSWorkspace sharedWorkspace] URLForApplicationToOpenURL:_musicURL];
    NSWorkspaceOpenConfiguration* configuration = [[NSWorkspaceOpenConfiguration alloc] init];
    [[NSWorkspace sharedWorkspace] openURLs:[NSArray arrayWithObject:_musicURL] withApplicationAtURL:appURL configuration:configuration completionHandler:^(NSRunningApplication* app, NSError* error){
    }];
}

- (void)reset
{
    _coverView.animator.image = [NSImage imageNamed:@"UnknownSong"];
    _titleField.animator.stringValue = @"???";
    _genreField.animator.stringValue = @"";
    _imageURL = nil;
    _musicURL = nil;
    _clipButton.animator.alphaValue = 0.0;
    _scButton.animator.alphaValue = 0.0;
}

// FIXME: This isnt safe as we may pull the sample away below the running session.
- (void)shazam:(id)sender
{
    NSLog(@"shazam!");
    [self reset];

    _session = [[SHSession alloc] init];
    _session.delegate = self;

    LazySample* sample = _audioController.sample;
    assert(sample);
    
    AVAudioFrameCount matchWindowFrameCount = kPlaybackBufferFrames;
    AVAudioChannelLayout* layout = [[AVAudioChannelLayout alloc] initWithLayoutTag:kAudioChannelLayoutTag_Mono];
    AVAudioFormat* format = [[AVAudioFormat alloc] initWithCommonFormat:AVAudioPCMFormatFloat32
                                                             sampleRate:sample.rate
                                                            interleaved:NO
                                                          channelLayout:layout];
    
    _stream = [[AVAudioPCMBuffer alloc] initWithPCMFormat:format frameCapacity:matchWindowFrameCount];
    
//#define DEBUG_TAPPING 1

#ifdef DEBUG_TAPPING
    FILE* fp = fopen("/tmp/debug_tap.out", "wb");
#endif
    [_audioController startTapping:^(unsigned long long offset, float* input, unsigned int frames) {
        dispatch_async(self.identifyQueue, ^{
            [self.stream setFrameLength:frames];
            float* outputBuffer = self.stream.floatChannelData[0];
            for (int i = 0; i < frames; i++) {
                float s = 0.0;
                for (int channel = 0; channel < sample.channels; channel++) {
                    s += input[(sample.channels * i) + channel];
                }
                s /= sample.channels;
                outputBuffer[i] = s;
            }
#ifdef DEBUG_TAPPING
            fwrite(outputBuffer, sizeof(float), frames, fp);
#endif
            [self.session matchStreamingBuffer:self.stream atTime:[AVAudioTime timeWithSampleTime:offset atRate:sample.rate]];
        });
    }];
}

- (void)session:(SHSession *)session didFindMatch:(SHMatch *)match
{
    dispatch_async(dispatch_get_main_queue(), ^{
        self.titleField.animator.stringValue = [NSString stringWithFormat:@"%@ - %@", match.mediaItems[0].artist, match.mediaItems[0].title];
        self.genreField.animator.stringValue = match.mediaItems[0].genres.count ? match.mediaItems[0].genres[0] : @"";
        self.clipButton.animator.alphaValue = 1.0;
        self.scButton.animator.alphaValue = 1.0;

        if (match.mediaItems[0].appleMusicURL != nil) {
            self.musicURL = match.mediaItems[0].appleMusicURL;
        }
        if (match.mediaItems[0].artworkURL != nil && ![match.mediaItems[0].artworkURL.absoluteString isEqualToString:self.imageURL.absoluteString]) {
            self.coverView.image = [NSImage imageNamed:@"UnknownSong"];
            NSLog(@"need to re/load the image as the displayed URL %@ wouldnt match the requested URL %@", self.imageURL.absoluteString, match.mediaItems[0].artworkURL.absoluteString);
            dispatch_async(dispatch_queue_create("AsyncImageQueue", NULL), ^{
                NSImage *image = [[NSImage alloc] initWithContentsOfURL:match.mediaItems[0].artworkURL];
                dispatch_async(dispatch_get_main_queue(), ^{
                    self.coverView.animator.image = image;
                    self.imageURL = match.mediaItems[0].artworkURL;
                });
            });
        }
    });
}

- (void)session:(SHSession *)session didNotFindMatchForSignature:(SHSignature *)signature error:(nullable NSError *)error
{
    NSLog(@"didNotFindMatchForSignature - error was: %@", error);
    dispatch_async(dispatch_get_main_queue(), ^{
        [self reset];
        self.titleField.animator.stringValue = @"unknown!";
    });
}

@end
