//
//  MPG123.m
//  PlayEm
//
//  Created by Till Toenshoff on 10.04.20.
//  Copyright © 2020 Till Toenshoff. All rights reserved.
//

#import "MPG123.h"

#include <mpg123.h>

#include <stdio.h>
#include <strings.h>

void usage(const char *cmd)
{
    printf("Usage: %s <input> [<driver> [<output> [encoding [buffersize]]]]\n"
    ,    cmd);
    printf( "\nPlay MPEG audio from intput file to output file/device using\n"
        "specified out123 driver, sample encoding and buffer size optional.\n\n" );
    exit(99);
}

void cleanup(mpg123_handle *mh)
{
    /* It's really to late for error checks here;-) */
    mpg123_close(mh);
    mpg123_delete(mh);
    mpg123_exit();
}

int do_it(char *infile)
{
    mpg123_handle *mh = NULL;
    char *driver = NULL;
    char *outfile = NULL;
    unsigned char* buffer = NULL;
    //const char *encname;
    size_t buffer_size = 0;
    size_t done = 0;
    int channels = 0;
    int encoding = 0;
    //int framesize = 1;
    long rate = 0;
    int  err  = MPG123_OK;
    off_t samples = 0;

    printf("Input file:    %s\n", infile);
    printf("Output driver: %s\n", driver ? driver : "<nil> (default)");
    printf("Output file:   %s\n", outfile ? outfile : "<nil> (default)");

    err = mpg123_init();
    if(err != MPG123_OK || (mh = mpg123_new(NULL, &err)) == NULL)
    {
        fprintf(stderr, "Basic setup goes wrong: %s", mpg123_plain_strerror(err));
        cleanup(mh);
        return -1;
    }

    /* Let mpg123 work with the file, that excludes MPG123_NEED_MORE messages. */
    if(    mpg123_open(mh, infile) != MPG123_OK
    /* Peek into track and get first output format. */
        || mpg123_getformat(mh, &rate, &channels, &encoding) != MPG123_OK )
    {
        fprintf( stderr, "Trouble with mpg123: %s\n", mpg123_strerror(mh) );
        cleanup(mh);
        return -1;
    }

    /* It makes no sense for that to give an error now. */
    printf("Effective output driver: %s\n", driver ? driver : "<nil> (default)");
    printf("Effective output file:   %s\n", outfile ? outfile : "<nil> (default)");

    /* Ensure that this output format will not change
       (it might, when we allow it). */
    mpg123_format_none(mh);
    mpg123_format(mh, rate, channels, encoding);

    /* Buffer could be almost any size here, mpg123_outblock() is just some
       recommendation. The size should be a multiple of the PCM frame size. */
    buffer_size = mpg123_outblock(mh);
    buffer = malloc( buffer_size );

    do
    {
        err = mpg123_read( mh, buffer, buffer_size, &done );
        samples += buffer_size;
    } while (done && err == MPG123_OK);

    free(buffer);

    if(err != MPG123_DONE)
    fprintf( stderr, "Warning: Decoding ended prematurely because: %s\n",
             err == MPG123_ERR ? mpg123_strerror(mh) : mpg123_plain_strerror(err) );

    printf("%li samples written.\n", (long)samples);
    cleanup(mh);
    return 0;
}

struct enc_desc
{
    int code; /* MPG123_ENC_SOMETHING */
    const char *longname; /* signed bla bla */
    const char *name; /* sXX, short name */
};

static const struct enc_desc encdesc[] =
{
    { MPG123_ENC_SIGNED_16,   "signed 16 bit",   "s16", }
,    { MPG123_ENC_UNSIGNED_16, "unsigned 16 bit", "u16"  }
,    { MPG123_ENC_SIGNED_32,   "signed 32 bit",   "s32"  }
,    { MPG123_ENC_UNSIGNED_32, "unsigned 32 bit", "u32"  }
,    { MPG123_ENC_SIGNED_24,   "signed 24 bit",   "s24"  }
,    { MPG123_ENC_UNSIGNED_24, "unsigned 24 bit", "u24"  }
,    { MPG123_ENC_FLOAT_32,    "float (32 bit)",  "f32"  }
,    { MPG123_ENC_FLOAT_64,    "float (64 bit)",  "f64"  }
,    { MPG123_ENC_SIGNED_8,    "signed 8 bit",    "s8"   }
,    { MPG123_ENC_UNSIGNED_8,  "unsigned 8 bit",  "u8"   }
,    { MPG123_ENC_ULAW_8,      "mu-law (8 bit)",  "ulaw" }
,    { MPG123_ENC_ALAW_8,      "a-law (8 bit)",   "alaw" }
};
#define KNOWN_ENCS (sizeof(encdesc)/sizeof(struct enc_desc))

const char* longName(int encoding)
{
    int i;
    for(i=0; i<KNOWN_ENCS; ++i) if(encdesc[i].code == encoding)
        return encdesc[i].longname;
    return NULL;
}

@interface MPG123 ()

@property (assign, nonatomic) mpg123_handle *mpg123_handle;

@property (strong, nonatomic) NSString *path;

@property (assign, nonatomic) size_t buffer_size;
@property (assign, nonatomic) unsigned char *buffer;

@end


@implementation MPG123

- (id)init
{
    self = [super init];
    if (self) {
        _mpg123_handle = NULL;
        _buffer = NULL;
        _buffer_size = 0;
        _path = @"";
    }
    return self;
}

- (void)close
{
    mpg123_close(self.mpg123_handle);
    mpg123_delete(self.mpg123_handle);
    mpg123_exit();
    
    if (self.buffer != NULL) {
        free (_buffer);
    }

    _mpg123_handle = NULL;
    _buffer = NULL;
    _buffer_size = 0;
    _path = @"";
}

- (BOOL)open:(NSString *)path error:(NSError **)error
{
    int err = mpg123_init();

    if (err != MPG123_OK) {
        NSString *message = [NSString stringWithFormat:@"mpg123_init failed with error: %s", mpg123_plain_strerror(err)];
        NSLog(@"Error: %@\n", message);
        if (error != nil) {
            NSMutableDictionary* details = [NSMutableDictionary dictionary];
            [details setValue:message forKey:NSLocalizedDescriptionKey];
            *error = [NSError errorWithDomain:@"MPG123" code:err userInfo:details];
        }
        return NO;
    }

    _mpg123_handle = mpg123_new(NULL, &err);

    if (err != MPG123_OK) {
        NSString *message = [NSString stringWithFormat:@"mpg123_new failed with error: %s", mpg123_plain_strerror(err)];
        NSLog(@"Error: %@\n", message);
        if (error != nil) {
            NSMutableDictionary* details = [NSMutableDictionary dictionary];
            [details setValue:message forKey:NSLocalizedDescriptionKey];
            *error = [NSError errorWithDomain:@"MPG123" code:err userInfo:details];
        }
        [self close];
        return NO;
    }
    
    err = mpg123_open(_mpg123_handle, [path cStringUsingEncoding:NSUTF8StringEncoding]);
    
    if (err != MPG123_OK) {
        NSString *message = [NSString stringWithFormat:@"mpg123_open failed with error: %s", mpg123_strerror(_mpg123_handle)];
        NSLog(@"Error: %@\n", message);
        if (error != nil) {
            NSMutableDictionary* details = [NSMutableDictionary dictionary];
            [details setValue:message forKey:NSLocalizedDescriptionKey];
            *error = [NSError errorWithDomain:@"MPG123" code:err userInfo:details];
        }
        [self close];
        return NO;
    }
    
    _path = path;
    
    _channels = 0;
    _encoding = 0;
    _framesize = 1;
    _rate = 0;
    
    err = mpg123_getformat(_mpg123_handle, &_rate, &_channels, &_encoding);

    if (err != MPG123_OK) {
        NSString *message = [NSString stringWithFormat:@"mpg123_getformat failed with error: %s", mpg123_strerror(_mpg123_handle)];
        NSLog(@"Error: %@\n", message);
        if (error != nil) {
            NSMutableDictionary* details = [NSMutableDictionary dictionary];
            [details setValue:message forKey:NSLocalizedDescriptionKey];
            *error = [NSError errorWithDomain:@"MPG123" code:err userInfo:details];
        }
        [self close];
        return NO;
    }
    
    NSLog(@"Channels: %d, Framesize: %d, Rate: %ld, Encoding: %s\n", _channels, _framesize, _rate, longName(_encoding));

    /* It makes no sense for that to give an error now. */

    /* Ensure that this output format will not change
       (it might, when we allow it). */

    mpg123_format_none(_mpg123_handle);
    mpg123_format(_mpg123_handle, _rate, _channels, _encoding);

    /* Buffer could be almost any size here, mpg123_outblock() is just some
       recommendation. The size should be a multiple of the PCM frame size. */

    _buffer_size = mpg123_outblock(_mpg123_handle);
    
    if (_buffer_size == 0) {
        NSString *message = [NSString stringWithFormat:@"mpg123_outblock failed"];
        NSLog(@"Error: %@\n", message);
        if (error != nil) {
            NSMutableDictionary* details = [NSMutableDictionary dictionary];
            [details setValue:message forKey:NSLocalizedDescriptionKey];
            *error = [NSError errorWithDomain:@"MPG123" code:0 userInfo:details];
        }
        [self close];
        return NO;
    }

    _buffer = malloc(_buffer_size);

    if (_buffer == NULL) {
        NSString *message = [NSString stringWithFormat:@"malloc failed"];
        NSLog(@"Error: %@\n", message);
        if (error != nil) {
            NSMutableDictionary* details = [NSMutableDictionary dictionary];
            [details setValue:message forKey:NSLocalizedDescriptionKey];
            *error = [NSError errorWithDomain:@"MPG123" code:0 userInfo:details];
        }
        [self close];
        return NO;
    }

    return YES;
}

- (BOOL)decode:(size_t (^) (unsigned char *buffer, size_t size)) outputHandler
{
    size_t done = 0;
    int err = MPG123_OK;
    size_t output = 0;
    off_t frames = 0;
    
    NSLog(@"Decoding MPEG frames...\n");

    do
    {
        err = mpg123_read( self.mpg123_handle, self.buffer, self.buffer_size, &done);
        output = outputHandler(self.buffer, done);

        if(output != done) {
            NSLog(@"Warning: output less than gotten from libmpg123: %li != %li\n", output, done);
        }

        frames += output / self.framesize;

        /* We are not in feeder mode, so MPG123_OK, MPG123_ERR and
           MPG123_NEW_FORMAT are the only possibilities.
           We do not handle a new format, MPG123_DONE is the end... so
           abort on anything not MPG123_OK. */
    } while (done && err == MPG123_OK);
    
    NSLog(@"Decoded %lld frames\n", frames);

    return YES;
}

- (BOOL)decodeToFile:(NSString *)path
{
    FILE *file = fopen([path cStringUsingEncoding:NSUTF8StringEncoding], "wb");
    
    if (file == NULL) {
        return NO;
    }

    [self decode:^(unsigned char *buffer, size_t size) {
        return fwrite(self.buffer, 1LL, size, file);
    }];

    fclose(file);
    
    return YES;
}

@end
