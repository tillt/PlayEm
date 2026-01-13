//
//  IdentifyController.m
//  PlayEm
//
//  Created by Till Toenshoff on 01.12.22.
//  Copyright © 2022 Till Toenshoff. All rights reserved.
//

#import "IdentifyViewController.h"

#import <ShazamKit/ShazamKit.h>
#import <WebKit/WebKit.h>

#import "../Defaults.h"
#import "NSImage+Average.h"
#import "NSImage+Resize.h"
#import <AudioToolbox/AudioToolbox.h>
#import "AudioController.h"
#import "IdentificationCoverView.h"
#import "ImageController.h"
#import "LazySample.h"
#import "MediaMetaData.h"
#import "TimedMediaMetaData.h"
#import "MediaMetaData+ImageController.h"
#import "AudioDevice.h"

#define DEBUG_TAPPING 1

NSString* const kTitleColumnIdenfifier = @"TitleColumn";
NSString* const kCoverColumnIdenfifier = @"CoverColumn";
NSString* const kButtonColumnIdenfifier = @"ButtonColumn";

NSString* const kSoundCloudQuery = @"https://soundcloud.com/search?q=%@";
NSString* const kBeatportQuery = @"https://beatport.com/search?q=%@";

const CGFloat kTableRowHeight = 52.0f;

@interface IdentifyViewController ()

@property (weak, nonatomic) AudioController* audioController;
@property (strong, nonatomic) SHSession* session;
@property (assign, nonatomic) unsigned long long sessionFrame;

@property (strong, nonatomic) AVAudioPCMBuffer* stream;

@property (strong, nonatomic) IdentificationCoverView* identificationCoverView;

@property (strong, nonatomic) dispatch_queue_t identifyQueue;

@property (strong, nonatomic) NSMutableArray<TimedMediaMetaData*>* identifieds;

@property (strong, nonatomic) NSTableView* tableView;
@property (strong, nonatomic, nullable) NSURL* imageURL;

@property (strong, nonatomic) NSVisualEffectView* effectBelowList;

@property (strong, nonatomic) NSColor* titleColor;
@property (strong, nonatomic) NSColor* artistColor;
@property (strong, nonatomic) NSColor* genreColor;

@property (strong, nonatomic) NSFont* titleFont;
@property (strong, nonatomic) NSFont* artistFont;
@property (strong, nonatomic) NSFont* genreFont;

@property (assign, nonatomic) CGFloat titleFontSize;
@property (assign, nonatomic) CGFloat artistFontSize;
@property (assign, nonatomic) CGFloat genreFontSize;

@property (strong, nonatomic) NSURL* sampleLocation;

@end

static AVAudioFile* gShzDumpFile = nil;
static NSString* gShzDumpPath = nil;

@implementation IdentifyViewController

+ (NSTextField*)textFieldWithFrame:(NSRect)frame font:(NSFont*)font color:(NSColor*)color
{
    NSTextField* title = [[NSTextField alloc] initWithFrame:frame];
    title.editable = NO;
    title.font = font;
    title.drawsBackground = NO;
    title.bordered = NO;
    title.usesSingleLineMode = YES;
    title.cell.truncatesLastVisibleLine = YES;
    title.cell.lineBreakMode = NSLineBreakByTruncatingTail;
    title.alignment = NSTextAlignmentLeft;
    title.textColor = color;
    return title;
}

- (id)initWithAudioController:(AudioController*)audioController delegate:(id<IdentifyViewControllerDelegate>)delegate
{
    self = [super init];
    if (self) {
        _delegate = delegate;
        _audioController = audioController;
        dispatch_queue_attr_t attr = dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL, QOS_CLASS_USER_INITIATED, 0);
        _identifyQueue = dispatch_queue_create("PlayEm.IdentifyQueue", attr);
        _identifieds = [NSMutableArray array];
        _sampleLocation = nil;

        _titleFont = [[Defaults sharedDefaults] largeFont];
        _titleFontSize = [[Defaults sharedDefaults] largeFontSize];
        _titleColor = [[Defaults sharedDefaults] lightFakeBeamColor];

        _artistFont = [[Defaults sharedDefaults] smallFont];
        _artistFontSize = [[Defaults sharedDefaults] smallFontSize];
        _artistColor = [[Defaults sharedDefaults] regularFakeBeamColor];

        _genreFont = [[Defaults sharedDefaults] smallFont];
        _genreFontSize = [[Defaults sharedDefaults] smallFontSize];
        _genreColor = [[Defaults sharedDefaults] secondaryLabelColor];
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];

    self.view.wantsLayer = YES;
    self.view.layer.masksToBounds = NO;
}

- (void)AudioControllerPlaybackStateChange:(NSNotification*)notification
{
    NSString* state = notification.object;
    BOOL playing = [state isEqualToString:kPlaybackStatePlaying];
    // By closing the window as soon as the playback ends or gets paused we avoid
    // having to re-init the shazam stream. We assume its ok for the user.
    if (!playing) {
        [_identificationCoverView pauseAnimating];
    }
    [_identificationCoverView setStill:!playing animated:YES];
    if (playing) {
        [_identificationCoverView startAnimating];
        [self shazam:self];
    }
}

- (void)setCurrentIdentificationSource:(NSURL*)url
{
    if ([_sampleLocation isEqualTo:url]) {
        return;
    }
    _identifieds = [NSMutableArray array];
    _sampleLocation = url;
    [self.tableView reloadData];
    [self updateBigCoverAnimated:YES];
}

- (void)viewWillAppear
{
    [self updateBigCoverAnimated:NO];

    [_identificationCoverView setStill:!_audioController.playing animated:NO];
    [_identificationCoverView startAnimating];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(AudioControllerPlaybackStateChange:)
                                                 name:kAudioControllerChangedPlaybackStateNotification
                                               object:nil];
    [self shazam:self];
}

- (void)viewDidDisappear
{}

- (void)viewWillDisappear
{
    NSLog(@"IdentifyController.view becoming invisible");
    [[NSApplication sharedApplication] stopModal];
    [_audioController stopTapping];

    // Finalize dump header if active.
#ifdef DEBUG_TAPPING
    if (gShzDumpFile != nil) {
        gShzDumpFile = nil;
    }
#endif
    [[NSNotificationCenter defaultCenter] removeObserver:self name:kAudioControllerChangedPlaybackStateNotification object:nil];
}

- (void)loadView
{
    NSLog(@"loadView");

    const CGFloat kPopoverWidth = 640.0f;
    const CGFloat kPopoverHeight = 280.0f;

    const CGFloat kTableViewWidth = 340.0f;

    const CGFloat kCoverColumnWidth = kTableRowHeight;
    const CGFloat kTitleColumnWidth = 238.0;
    const CGFloat kButtonsColumnWidth = 12.0;

    const CGFloat kBorderWidth = 20.0f;
    const CGFloat kBorderHeight = 0.0f;

    const CGFloat kCoverViewWidth = 260.0;
    const CGFloat kCoverViewHeight = kCoverViewWidth + 30.0;

    const NSAutoresizingMaskOptions kViewFullySizeable = NSViewHeightSizable | NSViewWidthSizable;

    self.view = [[NSView alloc] initWithFrame:NSMakeRect(0.0, 0.0, kPopoverWidth, kPopoverHeight)];
    _effectBelowList = [[NSVisualEffectView alloc]
        initWithFrame:NSMakeRect(kCoverViewWidth + kBorderWidth + kBorderWidth, 0, kTableViewWidth + kBorderWidth + kBorderWidth, kPopoverHeight + 30.0)];
    _effectBelowList.material = NSVisualEffectMaterialMenu;
    _effectBelowList.autoresizingMask = NSViewHeightSizable | NSViewMinXMargin;
    _effectBelowList.blendingMode = NSVisualEffectBlendingModeBehindWindow;

    CGFloat y = (kPopoverHeight + 12.0) - (kCoverViewHeight + kBorderHeight);

    NSScrollView* sv = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, y, kTableViewWidth, kCoverViewHeight)];
    sv.hasVerticalScroller = YES;
    sv.autoresizingMask = kViewFullySizeable;
    sv.automaticallyAdjustsContentInsets = YES;
    sv.drawsBackground = NO;

    self.tableView = [[NSTableView alloc] initWithFrame:NSMakeRect(0.0, 0.0, kTableViewWidth, kCoverViewHeight)];
    _tableView.delegate = self;
    _tableView.dataSource = self;
    _tableView.backgroundColor = [NSColor clearColor];
    _tableView.allowsEmptySelection = NO;
    _tableView.autoresizingMask = kViewFullySizeable;
    _tableView.headerView = nil;
    _tableView.columnAutoresizingStyle = NSTableViewNoColumnAutoresizing;
    _tableView.rowHeight = kTableRowHeight + 2.0;
    _tableView.intercellSpacing = NSMakeSize(0.0, 0.0);

    NSTableColumn* col = [[NSTableColumn alloc] init];
    col.title = @"";
    col.identifier = kCoverColumnIdenfifier;
    col.width = kCoverColumnWidth;
    [_tableView addTableColumn:col];

    col = [[NSTableColumn alloc] init];
    col.title = @"";
    col.identifier = kTitleColumnIdenfifier;
    col.width = kTitleColumnWidth;
    [_tableView addTableColumn:col];

    col = [[NSTableColumn alloc] init];
    col.title = @"";
    col.identifier = kButtonColumnIdenfifier;
    col.width = kButtonsColumnWidth;
    [_tableView addTableColumn:col];

    sv.documentView = _tableView;

    [_effectBelowList addSubview:sv];

    // This better be square
    _identificationCoverView =
        [[IdentificationCoverView alloc] initWithFrame:NSMakeRect(0, 0, kCoverViewWidth + kBorderWidth + kBorderWidth, kPopoverHeight + 26.0)
                                        contentsInsets:NSEdgeInsetsMake(kBorderWidth, kBorderWidth, 20.0, kBorderWidth)
                                                 style:CoverViewStyleGlowBehindCoverAtLaser | CoverViewStyleSepiaForSecondImageLayer |
                                                       CoverViewStylePumpingToTheBeat | CoverViewStyleRotatingLaser];

    [self.view addSubview:_identificationCoverView];
    [self.view addSubview:_effectBelowList];
}

- (NSString*)queryWithIdentifiedTrack:(TimedMediaMetaData*)item
{
    NSString* artist = item.meta.artist;
    NSString* title = item.meta.title;
    NSString* ret = title;
    if (artist != nil && ![artist isEqualToString:@""]) {
        ret = [NSString stringWithFormat:@"%@ - %@", artist, title];
    }
    return ret;
}

- (NSMenu*)itemMenuForTag:(int)tag
{
    NSMenu* menu = [NSMenu new];
    NSMenuItem* item = [[NSMenuItem alloc] initWithTitle:@"Add to Track List" action:@selector(addToTrackList:) keyEquivalent:@""];
    [item setKeyEquivalentModifierMask:NSEventModifierFlagCommand];
    item.tag = tag;
    [menu addItem:item];

    [menu addItem:[NSMenuItem separatorItem]];

    item = [[NSMenuItem alloc] initWithTitle:@"Copy to Clipboard" action:@selector(copyQueryToPasteboard:) keyEquivalent:@""];
    [item setKeyEquivalentModifierMask:NSEventModifierFlagCommand];
    item.tag = tag;
    [menu addItem:item];

    [menu addItem:[NSMenuItem separatorItem]];

    item = [[NSMenuItem alloc] initWithTitle:@"Open in Soundcloud" action:@selector(openSoundcloud:) keyEquivalent:@""];
    [item setKeyEquivalentModifierMask:NSEventModifierFlagCommand];
    item.tag = tag;
    [menu addItem:item];

    item = [[NSMenuItem alloc] initWithTitle:@"Open in Beatport" action:@selector(openBeatport:) keyEquivalent:@""];
    [item setKeyEquivalentModifierMask:NSEventModifierFlagCommand];
    item.tag = tag;
    [menu addItem:item];

    item = [menu addItemWithTitle:@"Open in Apple Music" action:@selector(musicURLClicked:) keyEquivalent:@""];
    item.tag = tag;
    item.target = self;

    return menu;
}

- (void)showMenu:(id)sender
{
    NSButton* button = sender;
    NSMenu* menu = [self itemMenuForTag:(int) button.tag];
    NSPoint mouseLocation = [NSEvent mouseLocation];

    [menu popUpMenuPositioningItem:menu.itemArray[0] atLocation:NSMakePoint(mouseLocation.x - 12.0f, mouseLocation.y + 12.0f) inView:nil];
}

- (void)addToTrackList:(id)sender
{
    NSButton* button = sender;
    unsigned long row = (_identifieds.count - button.tag) - 1;
    TimedMediaMetaData* track = _identifieds[row];
    NSLog(@"identified: %@", track);
    // NSTimeInterval time = [_audioController.sample timeForFrame:track.frame];
    [_delegate addTrackToTracklist:track];
}

- (void)copyQueryToPasteboard:(id)sender
{
    NSButton* button = sender;
    unsigned long row = (_identifieds.count - button.tag) - 1;
    NSLog(@"requested query from row: %ld", row);
    NSLog(@"identified: %@", _identifieds[row]);
    [[NSPasteboard generalPasteboard] clearContents];
    [[NSPasteboard generalPasteboard] setString:[self queryWithIdentifiedTrack:_identifieds[row]] forType:NSPasteboardTypeString];
}

- (void)openSoundcloud:(id)sender
{
    NSButton* button = sender;
    NSLog(@"soundcloud button tag: %ld", button.tag);
    unsigned long row = (_identifieds.count - button.tag) - 1;
    NSLog(@"soundcloud button row: %ld", row);

    // FIXME: this may very well be wrong -- however, the amperesand gets
    // correctly replaced,
    // FIXME: when needed -- all the predefined sets dont do that for some reason.
    NSCharacterSet* URLFullCharacterSet = [[NSCharacterSet characterSetWithCharactersInString:@" \"#%/:<>?@[\\]^`{|}&"] invertedSet];

    NSString* search = [self queryWithIdentifiedTrack:_identifieds[row]];
    search = [search stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    search = [search stringByAddingPercentEncodingWithAllowedCharacters:URLFullCharacterSet];

    NSURL* queryURL = [NSURL URLWithString:[NSString stringWithFormat:kSoundCloudQuery, search]];
    NSURL* appURL = [[NSWorkspace sharedWorkspace] URLForApplicationToOpenURL:queryURL];
    NSWorkspaceOpenConfiguration* configuration = [NSWorkspaceOpenConfiguration new];
    [[NSWorkspace sharedWorkspace] openURLs:[NSArray arrayWithObject:queryURL]
                       withApplicationAtURL:appURL
                              configuration:configuration
                          completionHandler:^(NSRunningApplication* app, NSError* error) {
                          }];
}

- (void)openBeatport:(id)sender
{
    NSButton* button = sender;
    unsigned long row = (_identifieds.count - button.tag) - 1;
    NSLog(@"beatport button row %ld", row);

    // FIXME: this may very well be wrong -- however, the amperesand gets
    // correctly replaced,
    // FIXME: when needed -- all the predefined sets dont do that for some reason.
    NSCharacterSet* URLFullCharacterSet = [[NSCharacterSet characterSetWithCharactersInString:@" \"#%/:<>?@[\\]^`{|}&"] invertedSet];

    NSString* search = [self queryWithIdentifiedTrack:_identifieds[row]];
    search = [search stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    search = [search stringByAddingPercentEncodingWithAllowedCharacters:URLFullCharacterSet];

    NSURL* queryURL = [NSURL URLWithString:[NSString stringWithFormat:kBeatportQuery, search]];
    NSURL* appURL = [[NSWorkspace sharedWorkspace] URLForApplicationToOpenURL:queryURL];
    NSWorkspaceOpenConfiguration* configuration = [NSWorkspaceOpenConfiguration new];
    [[NSWorkspace sharedWorkspace] openURLs:[NSArray arrayWithObject:queryURL]
                       withApplicationAtURL:appURL
                              configuration:configuration
                          completionHandler:^(NSRunningApplication* app, NSError* error) {
                          }];
}

- (void)musicURLClicked:(id)sender
{
    NSButton* button = sender;
    unsigned long row = (_identifieds.count - button.tag) - 1;
    NSLog(@"music url row %ld", row);
    NSURL* musicURL = _identifieds[row].meta.appleLocation;
    //    NSLog(@"opening %@", _musicURL);
    // For making sure this wont open Music.app we fetch the
    // default app for URLs.
    // With that we explicitly call the browser for opening the
    // URL. That way we get things displayed even in cases where
    // Music.app does not show iCloud.Music.
    NSURL* appURL = [[NSWorkspace sharedWorkspace] URLForApplicationToOpenURL:musicURL];
    NSWorkspaceOpenConfiguration* configuration = [NSWorkspaceOpenConfiguration new];
    [[NSWorkspace sharedWorkspace] openURLs:[NSArray arrayWithObject:musicURL]
                       withApplicationAtURL:appURL
                              configuration:configuration
                          completionHandler:^(NSRunningApplication* app, NSError* error) {
                          }];
}

- (void)shazam:(id)sender
{
    NSLog(@"shazam!");

    _session = [[SHSession alloc] init];
    _session.delegate = self;

    SampleFormat sampleFormat = _audioController.sample.sampleFormat;

    AVAudioFrameCount matchWindowFrameCount = kPlaybackBufferFrames;
    AVAudioChannelLayout* layout = [[AVAudioChannelLayout alloc] initWithLayoutTag:kAudioChannelLayoutTag_Mono];
    AVAudioFormat* format = [[AVAudioFormat alloc] initWithCommonFormat:AVAudioPCMFormatFloat32
                                                             sampleRate:_audioController.sample.renderedSampleRate
                                                            interleaved:NO
                                                          channelLayout:layout];

    _stream = [[AVAudioPCMBuffer alloc] initWithPCMFormat:format frameCapacity:matchWindowFrameCount];

#ifdef DEBUG_TAPPING
    static dispatch_once_t dumpOnce;
    dispatch_once(&dumpOnce, ^{
        gShzDumpPath = @"/tmp/shazam_stream.wav";
        NSLog(@"[ShazamStream] dump sample=%ld)", _audioController.sample.renderedSampleRate);
        // Create a WAV file via AVAudioFile using the tap format.
        NSError* fileErr = nil;
        NSURL* url = [NSURL fileURLWithPath:gShzDumpPath];
        // Remove existing file if present.
        [[NSFileManager defaultManager] removeItemAtURL:url error:nil];
        AVAudioFormat* fileFormat = [[AVAudioFormat alloc] initWithCommonFormat:AVAudioPCMFormatFloat32
                                                                     sampleRate:_audioController.sample.renderedSampleRate
                                                                       channels:1
                                                                    interleaved:NO];
        gShzDumpFile = [[AVAudioFile alloc] initForWriting:url settings:fileFormat.settings commonFormat:fileFormat.commonFormat interleaved:NO error:&fileErr];
        if (gShzDumpFile == nil || fileErr != nil) {
            NSLog(@"[ShazamStream] failed to open dump file at %@ err=%@", gShzDumpPath, fileErr);
            gShzDumpFile = nil;
            return;
        }
        NSLog(@"[ShazamStream] dumping mono float32 stream to %@ at %.0f Hz", gShzDumpPath, fileFormat.sampleRate);
    });
#endif

    __weak IdentifyViewController* weakSelf = self;

    [_audioController startTapping:^(unsigned long long offset, float* input, unsigned int frames) {
        IdentifyViewController* strongSelf = weakSelf;
        if (!strongSelf) {
            NSLog(@"weak reference gone");
            return;
        }
        __weak IdentifyViewController* innerWeakSelf = strongSelf;
        dispatch_async(strongSelf.identifyQueue, ^{
            IdentifyViewController* innerSelf = innerWeakSelf;
            if (!innerSelf) {
                return;
            }
            static double s_totalSeconds = 0.0;
            double seconds = (double) frames / innerSelf->_audioController.sample.renderedSampleRate;
            s_totalSeconds += seconds;
//#ifdef DEBUG_TAPPING
//                NSLog(@"[ShazamStream] offset=%llu frames=%u ch=%d totalSeconds=%.3f",
//                      offset, frames, sampleFormat.channels, s_totalSeconds);
//#endif
            [innerSelf.stream setFrameLength:frames];
            float* outputBuffer = innerSelf.stream.floatChannelData[0];
            int channelCount = (sampleFormat.channels > 0) ? sampleFormat.channels : 2;
            for (int i = 0; i < frames; i++) {
                float s = 0.0;
                for (int channel = 0; channel < channelCount; channel++) {
                    s += input[(channelCount * i) + channel];
                }
                s /= (channelCount > 0 ? channelCount : 1);
                outputBuffer[i] = s;
            }
#ifdef DEBUG_TAPPING
            if (gShzDumpFile != nil && frames > 0) {
                NSError* writeErr = nil;
                AVAudioPCMBuffer* dumpBuffer = [[AVAudioPCMBuffer alloc] initWithPCMFormat:gShzDumpFile.processingFormat frameCapacity:frames];
                dumpBuffer.frameLength = frames;
                memcpy(dumpBuffer.floatChannelData[0], outputBuffer, frames * sizeof(float));
                if (![gShzDumpFile writeFromBuffer:dumpBuffer error:&writeErr]) {
                    NSLog(@"[ShazamStream] failed to write dump frame err=%@", writeErr);
                }
#endif
            }
            innerSelf.sessionFrame = offset;

            AVAudioTime* time = [AVAudioTime timeWithSampleTime:offset atRate:innerSelf->_audioController.sample.renderedSampleRate];
            [innerSelf.session matchStreamingBuffer:innerSelf.stream atTime:time];
        });
    }];
}

#pragma mark - Shazam session delegate

- (void)updateBigCoverAnimated:(BOOL)animated
{
    MediaMetaData* meta = nil;

    if (_identifieds.count > 0) {
        meta = _identifieds[0].meta;
    } else {
        // We need some metadata object to begin with - even if that is just for the process
        // and not even stored. We run into this when the list is empty but we need to show
        // something.
        meta = [MediaMetaData unknownMediaMetaData];
    }
    
    __weak IdentifyViewController* weakSelf = self;

    [meta resolvedArtworkForSize:_identificationCoverView.frame.size.width
                     placeholder:NO
                        callback:^(NSImage* image){
        IdentifyViewController* strongSelf = weakSelf;
        if (image == nil || strongSelf == nil) {
            return;
        }
        [strongSelf->_identificationCoverView setImage:image animated:animated];
    }];
}

- (void)processMatchResult:(SHMatch*)match
{
    __weak IdentifyViewController* weakSelf = self;

    dispatch_async(dispatch_get_main_queue(), ^{
        IdentifyViewController* strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }

        TimedMediaMetaData* lastTrack = nil;
        if (strongSelf->_identifieds.count > 0) {
            lastTrack = self->_identifieds[0];
        }

        TimedMediaMetaData* insertTrack = nil;

        if (match == nil) {
            if (lastTrack &&
                lastTrack.meta.artworkLocation == nil &&
                lastTrack.meta.appleLocation == nil) {
                NSLog(@"unknown already on top, no need to add more");
            } else {
                // we need to insert an unknown track
                insertTrack = [TimedMediaMetaData unknownTrackAtFrame:[NSNumber numberWithUnsignedLongLong:strongSelf.sessionFrame]];
            }
        } else {
            if (lastTrack &&
                match.mediaItems[0].artworkURL != nil &&
                [match.mediaItems[0].artworkURL.absoluteString isEqualToString:lastTrack.meta.artworkLocation.absoluteString]) {
                NSLog(@"this track already is on top, no need to add more");
            } else {
                // we need to insert this track
                insertTrack = [[TimedMediaMetaData alloc] initWithMatchedMediaItem:match.mediaItems[0]
                                                                             frame:[NSNumber numberWithUnsignedLongLong:strongSelf.sessionFrame]];
            }
        }

        if (insertTrack == nil) {
            return;
        }

        [strongSelf->_identifieds insertObject:insertTrack atIndex:0];
        [strongSelf updateBigCoverAnimated:YES];

        [strongSelf->_tableView beginUpdates];
        NSIndexSet* indexSet = [NSIndexSet indexSetWithIndex:0];
        [strongSelf->_tableView insertRowsAtIndexes:indexSet withAnimation:NSTableViewAnimationSlideRight];
        [strongSelf->_tableView endUpdates];
    });
    
    
//
//    // FIXME: While the logic is sound, this just doesnt make sense.
//    // FIXME: We should instead have the view decide what to do, not the feeding unit.
//    // FIXME: This part here should feed all the results we have (unfiltered for dupes)
//    // FIXME: Into something that then decides transparently about keepers.
//    if (match.mediaItems[0].artworkURL != nil &&
//        ![match.mediaItems[0].artworkURL.absoluteString isEqualToString:strongSelf.imageURL.absoluteString]) {
//        NSLog(@"need to re/load the image as the displayed URL %@ wouldnt match "
//              @"the requested URL %@",
//              strongSelf.imageURL.absoluteString, match.mediaItems[0].artworkURL.absoluteString);
//
//        TimedMediaMetaData* track = [[TimedMediaMetaData alloc] initWithMatchedMediaItem:match.mediaItems[0]
//                                                                                   frame:[NSNumber numberWithUnsignedLongLong:strongSelf.sessionFrame]];
//
//        NSLog(@"track starts at frame: %@", track.frame);
//        
//        NSImageView* iv = [result viewWithTag:kImageViewTag];
//        __weak IdentifyViewController* weakContinuedSelf = strongSelf;
//
//        [track.meta resolvedArtworkForSize:iv.frame.size.width callback:^(NSImage* image) {
//            __weak NSView* strongView = weakView;
//            __weak NSTableView* strongTable = weakTable;
//            if (image == nil || strongView == nil || strongTable == nil) {
//                return;
//            }
//            if ([strongTable rowForView:strongView] == row) {
//                NSImageView* iv = [strongView viewWithTag:kImageViewTag];
//                iv.image = image;
//            }
//        }];
//
//        
//        void (^continuation)(void) = ^(void) {
//            IdentifyViewController* strongSelf = weakContinuedSelf;
//            if (!strongSelf) {
//                return;
//            }
//
//            strongSelf.imageURL = match.mediaItems[0].artworkURL;
//            [strongSelf->_identifieds insertObject:track atIndex:0];
//            [strongSelf updateBigCoverAnimated:YES];
//            [strongSelf->_tableView beginUpdates];
//            NSIndexSet* indexSet = [NSIndexSet indexSetWithIndex:0];
//            [strongSelf->_tableView insertRowsAtIndexes:indexSet withAnimation:NSTableViewAnimationSlideRight];
//            [strongSelf->_tableView endUpdates];
//        };
//
//        if (track.meta.artwork != nil) {
//            continuation();
//        } else {
//            if (track.meta.artworkLocation != nil) {
//                [[ImageController shared] resolveDataForURL:track.meta.artworkLocation
//                                                   callback:^(NSData* data) {
//                                                       track.meta.artwork = data;
//                                                       continuation();
//                                                   }];
//            }
//        }
//    }
}

- (void)session:(SHSession*)session didFindMatch:(SHMatch*)match
{
    [self processMatchResult:match];
}

- (void)session:(SHSession*)session didNotFindMatchForSignature:(SHSignature*)signature error:(nullable NSError*)error
{
    NSLog(@"didNotFindMatchForSignature offset=%llu error=%@", self.sessionFrame, error);
    [self processMatchResult:nil];
}

#pragma mark - Table View delegate

- (BOOL)tableView:(NSTableView*)tableView shouldSelectRow:(NSInteger)row
{
    return NO;
}

- (nullable NSView*)tableView:(NSTableView*)tableView viewForTableColumn:(nullable NSTableColumn*)tableColumn row:(NSInteger)row
{
    NSLog(@"%s -- column:%@ row:%ld", __PRETTY_FUNCTION__, [tableColumn description], row);
    NSView* result = [tableView makeViewWithIdentifier:tableColumn.identifier owner:self];

    NSString* const buttonTitle = @"􀍠";

    const CGFloat kArtworkSize = kTableRowHeight - 2.0;

    assert(_identifieds.count > 0);

    TimedMediaMetaData* track = _identifieds[row];

    const NSInteger tag = (_identifieds.count - 1) - row;
    if ([tableColumn.identifier isEqualToString:kCoverColumnIdenfifier]) {
        NSImageView* imageView = nil;
        if (result == nil) {
            imageView = [[NSImageView alloc] initWithFrame:NSMakeRect(0.0, 0.0, kArtworkSize, kArtworkSize)];
            result = imageView;
        } else {
            imageView = (NSImageView*) result;
        }
        result.identifier = tableColumn.identifier;

        __weak NSImageView* weakView = imageView;
        __weak NSTableView* weakTable = tableView;

        [track.meta resolvedArtworkForSize:_identificationCoverView.frame.size.width
                               placeholder:YES
                                  callback:^(NSImage* image){
            NSImageView* strongView = weakView;
            NSTableView* strongTable = weakTable;
            
            if (image == nil || strongView == nil || strongTable == nil) {
                return;
            }
            //if ([strongTable columnForView:strongView] == 0) {
            strongView.image = image;
            
        //}
        }];
    } else if ([tableColumn.identifier isEqualToString:kButtonColumnIdenfifier]) {
        NSButton* menuButton = nil;
        if (result == nil) {
            NSView* view = [[NSView alloc] initWithFrame:NSMakeRect(0.0, 0.0, tableColumn.width, kArtworkSize)];
            menuButton = [NSButton buttonWithTitle:buttonTitle target:self action:@selector(showMenu:)];
            menuButton.font = [NSFont systemFontOfSize:[[Defaults sharedDefaults] normalFontSize]];
            menuButton.bordered = NO;
            [menuButton setButtonType:NSButtonTypeMomentaryPushIn];
            menuButton.bezelStyle = NSBezelStyleTexturedRounded;
            menuButton.frame = NSMakeRect(0.0, roundf((kArtworkSize - roundf(kArtworkSize / 2.0)) / 2.0), tableColumn.width, roundf(kArtworkSize / 2.0));
            [view addSubview:menuButton];
            result = view;
        } else {
            NSArray<NSButton*>* subviews = [result subviews];
            menuButton = subviews[0];
        }
        result.identifier = tableColumn.identifier;

        menuButton.tag = tag;
    } else if ([tableColumn.identifier isEqualToString:kTitleColumnIdenfifier]) {
        NSTextField* title = nil;
        NSTextField* artist = nil;
        NSTextField* genre = nil;
        if (result == nil) {
            NSView* view = [[NSView alloc] initWithFrame:NSMakeRect(0.0, 0.0, tableColumn.width, kArtworkSize)];

            title = [IdentifyViewController textFieldWithFrame:NSMakeRect(0.0, ((_artistFontSize + 4.0) * 2.0), tableColumn.width, _titleFontSize + 3.0)
                                                          font:_titleFont
                                                         color:_titleColor];
            [view addSubview:title];

            artist = [IdentifyViewController textFieldWithFrame:NSMakeRect(0.0, (_artistFontSize + 2.0) + 3.0, tableColumn.width, _artistFontSize + 2.0)
                                                           font:_artistFont
                                                          color:_artistColor];
            [view addSubview:artist];

            genre = [IdentifyViewController textFieldWithFrame:NSMakeRect(0.0, 2.0, tableColumn.width, _genreFontSize + 2.0) font:_genreFont color:_genreColor];
            [view addSubview:genre];

            result = view;
        } else {
            NSArray<NSTextField*>* subviews = result.subviews;
            title = subviews[0];
            artist = subviews[1];
            genre = subviews[2];
        }
        result.identifier = tableColumn.identifier;
        [title setStringValue:track.meta.title != nil ? track.meta.title : @""];
        [artist setStringValue:track.meta.artist != nil ? track.meta.artist : @""];
        [genre setStringValue:track.meta.genre != nil ? track.meta.genre : @""];
    }

    return result;
}

#pragma mark - Table View data source

- (NSInteger)numberOfRowsInTableView:(NSTableView*)tableView
{
    return _identifieds.count;
}

@end
