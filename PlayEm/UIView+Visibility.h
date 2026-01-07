#import <Cocoa/Cocoa.h>
#import <QuartzCore/QuartzCore.h>

@interface NSView (Visibility) <CAAnimationDelegate>

- (BOOL)visible;
- (void)setVisible:(BOOL)visible;
- (void)setVisible:(BOOL)visible animated:(BOOL)animated;

@end
