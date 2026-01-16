#import <Foundation/Foundation.h>

NS_INLINE NSString* PECLocalizedString(NSString* key, NSString* comment)
{
    Class cls = NSClassFromString(@"ActivityManager");
    NSBundle* bundle = cls ? [NSBundle bundleForClass:cls] : [NSBundle mainBundle];
    return NSLocalizedStringFromTableInBundle(key, nil, bundle, comment);
}
