//
//  MetaController.m
//  PlayEm
//
//  Created by Till Toenshoff on 12/20/25.
//  Copyright © 2025 Till Toenshoff. All rights reserved.
//

#import "MetaController.h"
#import "MediaMetaData.h"

@interface MetaController()
{
}

@property (strong, nonatomic) dispatch_block_t loadOperation;

@end


@implementation MetaController

- (void)loadAbortWithCallback:(void (^)(void))callback
{
    if (_loadOperation != NULL) {
        dispatch_block_cancel(_loadOperation);
        if (callback != NULL) {
            dispatch_block_notify(_loadOperation, dispatch_get_main_queue(), ^{
                callback();
            });
        }
    } else {
        callback();
    }
}

- (MediaMetaData*)loadWithPath:(NSString*)path cancelTest:(BOOL (^)(void))cancelTest
{
    NSLog(@"loading metadata from %@...", path);
    NSError* error = nil;
    
    //    if (![engine startAndReturnError:&error]) {
    //        NSLog(@"startAndReturnError failed: %@\n", error);
    //        return NO;
    //    }

    MediaMetaData* meta = nil;
    
    // Not being able to get metadata is not a reason to fail the load process.
    meta = [MediaMetaData mediaMetaDataWithURL:[NSURL fileURLWithPath:path]
                                         error:&error];
    if (meta == nil) {
        if (error) {
            NSLog(@"failed to read metadata from %@: %@ ", path, error);
        }
        return nil;
    }

    return meta;
}

- (void)loadAsyncWithPath:(NSString*)path callback:(void (^)(MediaMetaData*))callback
{
    MetaController* __weak weakSelf = self;

    __block MediaMetaData* meta = nil;
    __weak __block dispatch_block_t weakBlock;

    //Incompatible block pointer types sending 'int (^)(void)' to parameter of type 'BOOL (^)(void)'
    dispatch_block_t block = dispatch_block_create(DISPATCH_BLOCK_NO_QOS_CLASS, ^{
        meta = [weakSelf loadWithPath:path cancelTest:^BOOL{
            return dispatch_block_testcancel(weakBlock) != 0 ? YES : NO;
        }];
    });
    
    weakBlock = block;
    _loadOperation = block;
    
    // Run the load operation!
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), _loadOperation);
    
    // Dispatch a callback on the main thread once decoding is done.
    dispatch_block_notify(_loadOperation, dispatch_get_main_queue(), ^{
        NSLog(@"meta loader phase one is done - we are back on the main thread - run the callback block with %@", meta);
        NSLog(@"container meta loading done");
        callback(meta);
    });
}

@end
