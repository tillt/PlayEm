//
//  AppDelegate.m
//  PlayEm
//
//  Created by Till Toenshoff on 30.03.20.
//  Copyright © 2020 Till Toenshoff. All rights reserved.
//

#import "AppDelegate.h"

#import <AVFoundation/AVFoundation.h>
#import <AppKit/NSOpenPanel.h>
#import "MPG123.h"
#import "Sample.h"
#import "VisualSample.h"
#import "Visualizer.h"
#import "TiledWaveView.h"

@interface AppDelegate ()

//@property (strong, nonatomic) AVAudioPlayer* audioPlayer;

@property (weak, nonatomic) IBOutlet NSWindow *window;
@property (weak, nonatomic) IBOutlet NSSlider *slider;
@property (weak, nonatomic) IBOutlet NSSlider *volumeSlider;
//@property (weak, nonatomic) IBOutlet NSImageView *imageView;
@property (weak, nonatomic) IBOutlet TiledWaveView *waveView;
@property (weak, nonatomic) IBOutlet NSScrollView *scrollView;
@property (strong, nonatomic) MPG123 *mpg123;

@property (strong, nonatomic) VisualSample *visual;

@property (assign, nonatomic) CGFloat windowBarHeight;
@property (assign, nonatomic) CGFloat controlsWidth;

@property (assign, nonatomic) CGSize headImageSize;

@property (strong, nonatomic) NSTimer *timer;

@property (strong, nonatomic) CALayer *headLayer;

@property (nonatomic, strong) AVAudioEngine *engine;
@property (nonatomic, strong) AVAudioPlayerNode *audioPlayerNode;
@property (nonatomic, strong) AVAudioMixerNode *mixer;
@property (nonatomic, strong) AVAudioPCMBuffer *audioPCMBuffer;

@property (weak, nonatomic) IBOutlet NSWindow *fftWindow;
@property (weak, nonatomic) IBOutlet NSView *fftView;

@property (weak, nonatomic) IBOutlet NSWindow *scopeWindow;
@property (weak, nonatomic) IBOutlet NSView *scopeWView;

@property (strong, nonatomic) Visualizer *visualizer;

@end


@implementation AppDelegate

- (IBAction)playPause:(id)sender
{
    if (!self.engine.isRunning) {
        NSLog(@"error: engine not running");
        return;
    }

    if (self.audioPlayerNode.isPlaying) {
        [self.timer invalidate];
        [self.audioPlayerNode stop];
    } else {
        double timerInterval = 1.0/100.0;
        self.timer = [NSTimer scheduledTimerWithTimeInterval:timerInterval repeats:YES block:^(NSTimer *timer){
            if (!self.audioPlayerNode.isPlaying) {
                return;
            }
            AVAudioTime *nodeTime = self.audioPlayerNode.lastRenderTime;
            AVAudioTime *playerTime = [self.audioPlayerNode playerTimeForNodeTime:nodeTime];

            NSTimeInterval seconds = (double)playerTime.sampleTime / playerTime.sampleRate;

            seconds += timerInterval;

            if (seconds < 0) {
                return;
            }

            CGFloat head = (seconds * self.waveView.bounds.size.width) / self.visual.sample.duration;
            
            [self.waveView scrollRectToVisible:CGRectMake(head - (self.scrollView.bounds.size.width / 2.0),
                                                           0.0,
                                                           self.scrollView.bounds.size.width,
                                                           self.waveView.bounds.size.height)];

            [CATransaction begin];
            [CATransaction setValue: (id) kCFBooleanTrue forKey: kCATransactionDisableActions];
            self.headLayer.position = CGPointMake(head, self.headLayer.position.y);
            [CATransaction commit];

            size_t offset = (self.audioPCMBuffer.frameCapacity * seconds) / self.visual.sample.duration;

            [self.visualizer process:self.audioPCMBuffer
                               offet:offset
                       bufferSamples:self.audioPCMBuffer.frameCapacity
                            channels:self.visual.sample.channels];
        }];
        
        NSLog(@"Buffer scheduled");
        [self.audioPlayerNode scheduleBuffer:self.audioPCMBuffer
                                          atTime:nil
                                         options:AVAudioPlayerNodeBufferInterrupts
                           completionHandler:^(){
            NSLog(@"buffer playback completed");
            [self.timer invalidate];
        }];

        [self.audioPlayerNode play];
        NSLog(@"Playback started");
    }
}

- (NSSize)windowWillResize:(NSWindow *)sender toSize:(NSSize)frameSize
{
    if (sender == self.window) {
        CGFloat width = self.scrollView.bounds.size.width + (64000.0 - self.scrollView.bounds.size.width) * (1.0 - self.slider.doubleValue);

        NSRect frame = CGRectMake(0.0,
                                  0.0,
                                  width,
                                  self.waveView.bounds.size.height);

        self.waveView.bounds = frame;
        
        self.headLayer.frame = CGRectMake(0.0 - (self.headImageSize.width / 2.0),
                                          0.0,
                                          self.headImageSize.width,
                                          self.scrollView.bounds.size.height);

/*
        self.waveView.image = [Visualizer imageFromVisualSample:self.visual
                                                           start:0.0
                                                        duration:self.visual.sample.duration
                                                            size:imageViewSize];
 */
    } else if (sender == self.scopeWindow) {
        if (frameSize.width > 2048) {
            frameSize = NSMakeSize(2048, frameSize.height);
        }
        [self.visualizer resizeScope:frameSize];
    } else if (sender == self.fftWindow) {
        [self.visualizer resizeFFT:frameSize];
    }

/*
    CGSize scrollViewSize = CGSizeMake(frameSize.width - self.controlsWidth, frameSize.height - self.windowBarHeight);
    CGFloat width = scrollViewSize.width + (64000.0 - scrollViewSize.width) * (1.0 - self.slider.doubleValue);
    CGSize imageViewSize = NSMakeSize(width, frameSize.height - self.windowBarHeight);

    self.headLayer.frame = CGRectMake(0.0, 0.0, self.headLayer.bounds.size.width, scrollViewSize.height);

    self.imageView.image = [Visualizer imageFromVisualSample:self.visual
                                                 start:0.0
                                              duration:self.visual.sample.duration
                                                  size:imageViewSize];
    */
    return frameSize;
}

- (IBAction)volumeValueChanged:(id)sender
{
    NSLog(@"volume: %f\n", self.volumeSlider.doubleValue);
    NSSlider *slider = sender;
    self.mixer.outputVolume = slider.doubleValue;
}

- (void)updateWaveViewSize
{
    NSLog(@"duration: %f\n", self.slider.doubleValue);
    CGFloat width = self.scrollView.bounds.size.width + (64000.0 - self.scrollView.bounds.size.width) * (1.0 - self.slider.doubleValue);
    self.waveView.frame = CGRectMake(0.0, 0.0, width, self.scrollView.bounds.size.height);;
    self.scrollView.documentView.frame = self.waveView.frame;
}

- (IBAction)valueChanged:(id)sender
{
    [self updateWaveViewSize];

    /*
    CGSize imageViewSize = NSMakeSize(width, self.waveView.bounds.size.height);
    self.waveView.image = [Visualizer imageFromVisualSample:self.visual
                                                       start:0.0
                                                    duration:self.visual.sample.duration
                                                        size:imageViewSize];
     
     */
    
}

- (BOOL)application:(NSApplication *)sender openFile:(NSString *)filename
{
    NSLog(@"We got asked to open a file\n");
    return YES;
}

- (void)application:(NSApplication *)application openURLs:(NSArray<NSURL *> *)urls
{
    NSLog(@"We got asked to open a URL\n");
}

- (void)observeValueForKeyPath:(NSString *)keyPath
                      ofObject:(id)object
                        change:(NSDictionary *)change
                       context:(void *)context {
    NSLog(@"%@", change);
}

- (IBAction)openDocument:(id)sender
{
    NSOpenPanel* openDlg = [NSOpenPanel openPanel];
    [openDlg setCanChooseFiles:YES];
    [openDlg setCanChooseDirectories:YES];
    
    NSString *filePath = nil;

    if ([openDlg runModal] == NSModalResponseOK)
    {
        for(NSURL* URL in [openDlg URLs])
        {
            NSLog( @"%@", [URL path]);
            filePath = [URL path];
        }
    } else {
        return;
    }
    
    NSError *error = nil;

    self.mpg123 = [[MPG123 alloc] init];
    
    if (![self.mpg123 open:filePath error:&error]) {
        NSLog(@"failed: %@", error);
        return;
    }
    
    // Prepare sample.
    Sample *sample = [[Sample alloc] initWithChannels:self.mpg123.channels
                                                 rate:self.mpg123.rate
                                             encoding:self.mpg123.encoding];

    // Decode MP3 to our sample.
    [self.mpg123 decode:^(unsigned char *buffer, size_t size) {
        return [sample addSampleData:buffer size:size];
    }];
    
    [self.mpg123 close];

    NSLog(@"Sample: %@\n", sample);

    // Prepare sample for wave visualizer - this will reduce the sample to a maximum of 512k extrema.
    self.visual = [[VisualSample alloc] initWithSample:sample];

    [self updateWaveViewSize];

    // Render wave image.
    /*
    self.waveView.frame = self.scrollView.bounds;
    self.waveView.image = [Visualizer imageFromVisualSample:self.visual
                                                       start:0.0
                                                    duration:self.visual.sample.duration
                                                        size:self.scrollView.bounds.size];
    */
    // Prepare buffer.
    AVAudioChannelLayout *channelLayout = [[AVAudioChannelLayout alloc] initWithLayoutTag:kAudioChannelLayoutTag_Stereo];
    
    // FIXNE: AVAudioPCMFormatFloat32 is default and also seems ot be the only format where copying data in as we do below
    // works as expected. WHen using Signed16 we endup with garbled shit - that seems to be a lack of setup somewhere.
    // The perfect solution simply uses the sample-bytes directly.
    AVAudioFormat *audioFormat = [[AVAudioFormat alloc] initWithCommonFormat:AVAudioPCMFormatFloat32
                                                                  sampleRate:44100.0
                                                                 interleaved:NO
                                                               channelLayout:channelLayout];

    AVAudioFrameCount length = (AVAudioFrameCount)sample.data.length / (sample.channels * 2);
    self.audioPCMBuffer = [[AVAudioPCMBuffer alloc] initWithPCMFormat:audioFormat frameCapacity:length];
    self.audioPCMBuffer.frameLength = self.audioPCMBuffer.frameCapacity;
    
    signed short int *source = (signed short int *)sample.data.bytes;
    float *left = self.audioPCMBuffer.floatChannelData[0];
    float *right = self.audioPCMBuffer.floatChannelData[1];

    // Copy sample data.
    for (size_t i=0; i < length;i++)
    {
        *left = (float)(*source) / 32768.0;
        ++left;
        ++source;

        *right = (float)(*source) / 32768.0;
        ++right;
        ++source;
    }
    
    // Connect nodes.
    self.mixer = [self.engine mainMixerNode];
    [self.engine connect:self.audioPlayerNode
                      to:self.mixer
                  format:audioFormat];

    self.mixer.outputVolume = self.volumeSlider.doubleValue;

    // Start engine.
    [self.engine startAndReturnError:&error];
    
    if (error) {
        NSLog(@"Error:%@", error);
    }
}

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
    self.window.delegate = self;
    CGRect rect = CGRectMake(0.0, 0.0, self.window.frame.size.width, self.window.frame.size.height);
    CGRect contentRect = [self.window contentRectForFrameRect:rect];
    self.windowBarHeight = self.window.frame.size.height - contentRect.size.height;
    
    self.controlsWidth = self.window.frame.size.width - self.scrollView.bounds.size.width;
    
    self.headLayer = [[CALayer alloc] init];
    NSImage *image = [NSImage imageNamed:@"CurrentTime"];
    image.resizingMode = NSImageResizingModeTile;
    self.headLayer.contents = image;
    self.headImageSize = image.size;
    self.headLayer.frame = CGRectMake(0.0 - (self.headImageSize.width / 2.0), 0.0, self.headImageSize.width, self.scrollView.bounds.size.height);
    [self.scrollView.contentView.layer addSublayer:self.headLayer];
    [self.headLayer setZPosition:10];
    self.headLayer.opacity = 1.0;
    
    self.headLayer.compositingFilter = [CIFilter filterWithName:@"CISourceAtopCompositing"];
    
    self.visualizer = [[Visualizer alloc] initWithFFTView:self.fftView scopeView:self.scopeWView];
    
    self.scopeWindow.preservesContentDuringLiveResize = YES;
    self.volumeSlider.doubleValue = 0.0;
    self.slider.maxValue = 1.0;
    self.slider.minValue = 0.0;
    
    // Prepare engine.
    self.engine = [[AVAudioEngine alloc] init];
    self.audioPlayerNode = [[AVAudioPlayerNode alloc] init];
    [self.engine attachNode:self.audioPlayerNode];
}

- (void)applicationWillTerminate:(NSNotification *)aNotification
{
    [self.timer invalidate];
    [self.audioPlayerNode stop];
}

@end
