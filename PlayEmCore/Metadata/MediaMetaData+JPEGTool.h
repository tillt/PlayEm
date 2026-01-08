//
//  MediaMetaData+JPEGTool.h
//  PlayEm
//
//  Created by Till Toenshoff on 12/17/25.
//  Copyright © 2025 Till Toenshoff. All rights reserved.
//

#import "MediaMetaData.h"

#ifndef MediaMetaData_JPEGTool_h
#define MediaMetaData_JPEGTool_h

@interface MediaMetaData (JPEGTool)

- (NSData*)sizedJPEG420;

@end

#endif /* MediaMetaData_JPEGTool_h */
