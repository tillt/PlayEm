//
//  LibraryStore.m
//  PlayEm
//
//  Created by Till Toenshoff on 09/03/26.
//  Copyright © 2026 Till Toenshoff. All rights reserved.
//

#import "LibraryStore.h"

#import <sqlite3.h>

#import "MediaMetaData.h"
#import "NSString+Sanitized.h"
#import "MetaController.h"
#import "NSData+Hashing.h"

static NSString* const kLibrarySchema =
    @"CREATE TABLE IF NOT EXISTS tracks ("
    @" url TEXT PRIMARY KEY,"
    @" title TEXT,"
    @" artist TEXT,"
    @" album TEXT,"
    @" albumArtist TEXT,"
    @" genre TEXT,"
    @" year INTEGER,"
    @" trackNumber INTEGER,"
    @" trackCount INTEGER,"
    @" discNumber INTEGER,"
    @" discCount INTEGER,"
    @" duration REAL,"
    @" bpm REAL,"
    @" key TEXT,"
    @" rating INTEGER,"
    @" comment TEXT,"
    @" tags TEXT,"
    @" compilation INTEGER,"
    @" artworkHash TEXT,"
    @" artworkLocation TEXT,"
    @" addedAt REAL,"
    @" lastSeen REAL,"
    @" appleLocation TEXT"
    @");"
    @"CREATE TABLE IF NOT EXISTS artwork ("
    @" hash TEXT PRIMARY KEY,"
    @" format INTEGER,"
    @" data BLOB"
    @");";

@interface LibraryStore ()
@property (nonatomic, strong) NSURL* databaseURL;
@property (nonatomic) sqlite3* db;
@end

@implementation LibraryStore

#pragma mark - Helpers

static BOOL isLikelyMojibakeString(NSString* s)
{
    if (s.length == 0) {
        return NO;
    }
    // Heuristic: common mojibake sequences when UTF-8 is misread as Latin-1.
    if ([s rangeOfString:@"Ã"].location != NSNotFound ||
        [s rangeOfString:@"Â"].location != NSNotFound ||
        [s rangeOfString:@"�"].location != NSNotFound) {
        return YES;
    }
    return NO;
}

- (instancetype)initWithDatabaseURL:(NSURL*)url
{
    self = [super init];
    if (self) {
        _databaseURL = url;
    }
    return self;
}

- (BOOL)open:(NSError**)error
{
    if (self.db) {
        return YES;
    }

    NSFileManager* fm = [NSFileManager defaultManager];
    NSURL* dir = [self.databaseURL URLByDeletingLastPathComponent];
    if (![fm fileExistsAtPath:dir.path]) {
        [fm createDirectoryAtURL:dir withIntermediateDirectories:YES attributes:nil error:nil];
    }

    int rc = sqlite3_open(self.databaseURL.fileSystemRepresentation, &_db);
    if (rc != SQLITE_OK) {
        if (error) {
            *error = [NSError errorWithDomain:@"LibraryStore" code:rc userInfo:@{NSLocalizedDescriptionKey : @"Failed to open database"}];
        }
        return NO;
    }

    char* errmsg = NULL;
    rc = sqlite3_exec(self.db, kLibrarySchema.UTF8String, NULL, NULL, &errmsg);
    if (rc != SQLITE_OK) {
        if (error) {
            NSString* msg = errmsg ? [NSString stringWithUTF8String:errmsg] : @"Failed to create schema";
            *error = [NSError errorWithDomain:@"LibraryStore" code:rc userInfo:@{NSLocalizedDescriptionKey : msg}];
        }
        if (errmsg) {
            sqlite3_free(errmsg);
        }
        return NO;
    }
    return YES;
}

- (BOOL)importMediaItems:(NSArray<MediaMetaData*>*)items error:(NSError**)error
{
    return [self importMediaItems:items preferExisting:NO error:error];
}

- (BOOL)importMediaItems:(NSArray<MediaMetaData*>*)items preferExisting:(BOOL)preferExisting error:(NSError**)error
{
    if (![self open:error]) {
        return NO;
    }

    // preferExisting == YES keeps DB/file-derived metadata and only updates bookkeeping fields.
    const char* sqlPreferExisting =
                      "INSERT INTO tracks "
                      "(url,title,artist,album,albumArtist,genre,year,trackNumber,trackCount,discNumber,discCount,duration,bpm,key,rating,comment,tags,compilation,artworkHash,artworkLocation,addedAt,lastSeen,appleLocation) "
                      "VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?) "
                      "ON CONFLICT(url) DO UPDATE SET "
                        // keep existing metadata; only update bookkeeping.
                      "addedAt=COALESCE(tracks.addedAt, excluded.addedAt),"
                      "lastSeen=excluded.lastSeen";

    const char* sqlOverwrite =
                      "INSERT INTO tracks "
                      "(url,title,artist,album,albumArtist,genre,year,trackNumber,trackCount,discNumber,discCount,duration,bpm,key,rating,comment,tags,compilation,artworkHash,artworkLocation,addedAt,lastSeen,appleLocation) "
                      "VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?) "
                      "ON CONFLICT(url) DO UPDATE SET "
                      "title=excluded.title,"
                      "artist=excluded.artist,"
                      "album=excluded.album,"
                      "albumArtist=excluded.albumArtist,"
                      "genre=excluded.genre,"
                      "year=excluded.year,"
                      "trackNumber=excluded.trackNumber,"
                      "trackCount=excluded.trackCount,"
                      "discNumber=excluded.discNumber,"
                      "discCount=excluded.discCount,"
                      "duration=excluded.duration,"
                      "bpm=excluded.bpm,"
                      "key=excluded.key,"
                      "rating=excluded.rating,"
                      "comment=excluded.comment,"
                      "tags=excluded.tags,"
                      "compilation=excluded.compilation,"
                      "artworkHash=excluded.artworkHash,"
                      "artworkLocation=excluded.artworkLocation,"
                      "addedAt=COALESCE(tracks.addedAt, excluded.addedAt),"
                      "lastSeen=excluded.lastSeen,"
                      "appleLocation=excluded.appleLocation";

    const char* sql = preferExisting ? sqlPreferExisting : sqlOverwrite;

    const char* artSql = "INSERT INTO artwork (hash, format, data) "
                         "VALUES (?,?,?) "
                         "ON CONFLICT(hash) DO UPDATE SET "
                         "format=excluded.format,"
                         "data=excluded.data";

    sqlite3_stmt* stmt = NULL;
    int rc = sqlite3_prepare_v2(self.db, sql, -1, &stmt, NULL);
    if (rc != SQLITE_OK) {
        if (error) {
            *error = [NSError errorWithDomain:@"LibraryStore" code:rc userInfo:@{NSLocalizedDescriptionKey : @"Failed to prepare insert"}];
        }
        return NO;
    }

    sqlite3_stmt* artStmt = NULL;
    rc = sqlite3_prepare_v2(self.db, artSql, -1, &artStmt, NULL);
    if (rc != SQLITE_OK) {
        if (error) {
            *error = [NSError errorWithDomain:@"LibraryStore" code:rc userInfo:@{NSLocalizedDescriptionKey : @"Failed to prepare artwork insert"}];
        }
        sqlite3_finalize(stmt);
        return NO;
    }

    for (MediaMetaData* meta in items) {
        sqlite3_reset(stmt);
        sqlite3_clear_bindings(stmt);

        sqlite3_bind_text(stmt, 1, meta.location.absoluteString.UTF8String, -1, SQLITE_TRANSIENT);
        sqlite3_bind_text(stmt, 2, (meta.title ?: @"").UTF8String, -1, SQLITE_TRANSIENT);
        sqlite3_bind_text(stmt, 3, (meta.artist ?: @"").UTF8String, -1, SQLITE_TRANSIENT);
        sqlite3_bind_text(stmt, 4, (meta.album ?: @"").UTF8String, -1, SQLITE_TRANSIENT);
        sqlite3_bind_text(stmt, 5, (meta.albumArtist ?: @"").UTF8String, -1, SQLITE_TRANSIENT);
        sqlite3_bind_text(stmt, 6, (meta.genre ?: @"").UTF8String, -1, SQLITE_TRANSIENT);
        sqlite3_bind_int(stmt, 7, meta.year.intValue);
        sqlite3_bind_int(stmt, 8, meta.track.intValue);
        sqlite3_bind_int(stmt, 9, meta.tracks.intValue);
        sqlite3_bind_int(stmt, 10, meta.disk.intValue);
        sqlite3_bind_int(stmt, 11, meta.disks.intValue);
        sqlite3_bind_double(stmt, 12, meta.duration.doubleValue);
        sqlite3_bind_double(stmt, 13, meta.tempo.doubleValue);
        sqlite3_bind_text(stmt, 14, (meta.key ?: @"").UTF8String, -1, SQLITE_TRANSIENT);
        sqlite3_bind_int(stmt, 15, meta.rating.intValue);
        sqlite3_bind_text(stmt, 16, (meta.comment ?: @"").UTF8String, -1, SQLITE_TRANSIENT);
        sqlite3_bind_text(stmt, 17, (meta.tags ?: @"").UTF8String, -1, SQLITE_TRANSIENT);
        sqlite3_bind_int(stmt, 18, meta.compilation.boolValue ? 1 : 0);

        // artworkHash matches the ImageController cache key for the same data blob.
        NSString* artworkHash = meta.artworkHash;
        if (meta.artwork != nil && artworkHash.length > 0) {
            NSString* defaultHash = [MediaMetaData defaultArtworkData].shortSHA256;
            NSAssert(![artworkHash isEqualToString:defaultHash], @"LibraryStore: default artwork should not be persisted for %@", meta.location);
            if ([artworkHash isEqualToString:defaultHash]) {
                artworkHash = nil;
            }
        }

        if (meta.artwork != nil && artworkHash.length > 0) {
            sqlite3_reset(artStmt);
            sqlite3_clear_bindings(artStmt);
            sqlite3_bind_text(artStmt, 1, artworkHash.UTF8String, -1, SQLITE_TRANSIENT);
            sqlite3_bind_int(artStmt, 2, meta.artworkFormat.intValue);
            sqlite3_bind_blob(artStmt, 3, meta.artwork.bytes, (int) meta.artwork.length, SQLITE_TRANSIENT);
            int artRc = sqlite3_step(artStmt);
            if (artRc != SQLITE_DONE) {
                if (error) {
                    *error = [NSError errorWithDomain:@"LibraryStore" code:artRc userInfo:@{NSLocalizedDescriptionKey : @"Failed to insert artwork"}];
                }
                sqlite3_finalize(stmt);
                sqlite3_finalize(artStmt);
                return NO;
            }
        }

        sqlite3_bind_text(stmt, 19, artworkHash.UTF8String, -1, SQLITE_TRANSIENT);
        sqlite3_bind_text(stmt, 20, meta.artworkLocation.absoluteString.UTF8String, -1, SQLITE_TRANSIENT);
        double now = [NSDate date].timeIntervalSince1970;
        double addedAt = meta.added ? meta.added.timeIntervalSince1970 : now;
        // addedAt bind is at index 21; lastSeen is 22.
        sqlite3_bind_double(stmt, 21, addedAt);
        sqlite3_bind_double(stmt, 22, now);
        sqlite3_bind_text(stmt, 23, meta.appleLocation.absoluteString.UTF8String, -1, SQLITE_TRANSIENT);

        rc = sqlite3_step(stmt);
        if (rc != SQLITE_DONE) {
            if (error) {
                *error = [NSError errorWithDomain:@"LibraryStore" code:rc userInfo:@{NSLocalizedDescriptionKey : @"Failed to insert row"}];
            }
            sqlite3_finalize(stmt);
            sqlite3_finalize(artStmt);
            return NO;
        }
    }

    sqlite3_finalize(stmt);
    sqlite3_finalize(artStmt);
    return YES;
}

- (NSArray<MediaMetaData*>* _Nullable)loadAllMediaItems:(NSError**)error
{
    if (![self open:error]) {
        return nil;
    }

    const char* sql = "SELECT url,title,artist,album,albumArtist,genre,year,trackNumber,trackCount,discNumber,discCount,duration,bpm,key,rating,comment,tags,compilation,artworkHash,artworkLocation,addedAt,lastSeen,appleLocation FROM tracks";
    sqlite3_stmt* stmt = NULL;
    int rc = sqlite3_prepare_v2(self.db, sql, -1, &stmt, NULL);
    if (rc != SQLITE_OK) {
        if (error) {
            *error = [NSError errorWithDomain:@"LibraryStore" code:rc userInfo:@{NSLocalizedDescriptionKey : @"Failed to prepare select"}];
        }
        return nil;
    }

    sqlite3_stmt* artStmt = NULL;
    rc = sqlite3_prepare_v2(self.db, "SELECT data, format FROM artwork WHERE hash = ?", -1, &artStmt, NULL);
    if (rc != SQLITE_OK) {
        if (error) {
            *error = [NSError errorWithDomain:@"LibraryStore" code:rc userInfo:@{NSLocalizedDescriptionKey : @"Failed to prepare artwork select"}];
        }
        sqlite3_finalize(stmt);
        return nil;
    }

    NSMutableArray<MediaMetaData*>* result = [NSMutableArray array];

    while ((rc = sqlite3_step(stmt)) == SQLITE_ROW) {
        MediaMetaData* meta = [MediaMetaData new];

        const char* url = (const char*) sqlite3_column_text(stmt, 0);

        meta.location = url ? [NSURL URLWithString:@(url)] : nil;
        meta.title = sqlite3_column_text(stmt, 1) ? @((const char*) sqlite3_column_text(stmt, 1)) : nil;
        meta.artist = sqlite3_column_text(stmt, 2) ? @((const char*) sqlite3_column_text(stmt, 2)) : nil;
        meta.album = sqlite3_column_text(stmt, 3) ? @((const char*) sqlite3_column_text(stmt, 3)) : nil;
        meta.albumArtist = sqlite3_column_text(stmt, 4) ? @((const char*) sqlite3_column_text(stmt, 4)) : nil;
        meta.genre = sqlite3_column_text(stmt, 5) ? @((const char*) sqlite3_column_text(stmt, 5)) : nil;
        meta.year = @(sqlite3_column_int(stmt, 6));
        meta.track = @(sqlite3_column_int(stmt, 7));
        meta.tracks = @(sqlite3_column_int(stmt, 8));
        meta.disk = @(sqlite3_column_int(stmt, 9));
        meta.disks = @(sqlite3_column_int(stmt, 10));
        meta.duration = @(sqlite3_column_double(stmt, 11));
        meta.tempo = @(sqlite3_column_double(stmt, 12));
        meta.key = sqlite3_column_text(stmt, 13) ? @((const char*) sqlite3_column_text(stmt, 13)) : nil;
        meta.rating = @(sqlite3_column_int(stmt, 14));
        meta.comment = sqlite3_column_text(stmt, 15) ? @((const char*) sqlite3_column_text(stmt, 15)) : nil;
        meta.tags = sqlite3_column_text(stmt, 16) ? @((const char*) sqlite3_column_text(stmt, 16)) : nil;
        meta.compilation = @(sqlite3_column_int(stmt, 17) != 0);
        const char* artHash = (const char*) sqlite3_column_text(stmt, 18);
        const char* artLoc = (const char*) sqlite3_column_text(stmt, 19);
        meta.artworkLocation = artLoc ? [NSURL URLWithString:@(artLoc)] : nil;
        double addedAt = sqlite3_column_double(stmt, 20);
        if (addedAt > 0.0) {
            meta.added = [NSDate dateWithTimeIntervalSince1970:addedAt];
        }
        const char* appleLoc = (const char*) sqlite3_column_text(stmt, 22);
        meta.appleLocation = appleLoc ? [NSURL URLWithString:@(appleLoc)] : nil;

        if (artHash) {
            sqlite3_reset(artStmt);
            sqlite3_clear_bindings(artStmt);
            sqlite3_bind_text(artStmt, 1, artHash, -1, SQLITE_TRANSIENT);
            int artRc = sqlite3_step(artStmt);
            if (artRc == SQLITE_ROW) {
                const void* data = sqlite3_column_blob(artStmt, 0);
                int length = sqlite3_column_bytes(artStmt, 0);
                if (data && length > 0) {
                    meta.artwork = [NSData dataWithBytes:data length:length];
                }
                meta.artworkFormat = @(sqlite3_column_int(artStmt, 1));
            }
        }

        [result addObject:meta];
    }

    sqlite3_finalize(stmt);
    sqlite3_finalize(artStmt);

    return result;
}

- (void)importFileURLs:(NSArray<NSURL*>*)urls completion:(void (^)(NSArray<MediaMetaData*>* _Nullable metas, NSError* _Nullable error))completion
{
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSMutableArray<MediaMetaData*>* metas = [NSMutableArray array];
        MetaController* loader = [MetaController new];
        dispatch_group_t group = dispatch_group_create();
        dispatch_queue_t mergeQueue = dispatch_queue_create("PlayEm.LibraryStore.ImportMerge", DISPATCH_QUEUE_SERIAL);

        for (NSURL* url in urls) {
            dispatch_group_enter(group);
            [loader loadAsyncWithPath:url.path
                             callback:^(MediaMetaData* meta) {
                                 if (meta) {
                                     dispatch_async(mergeQueue, ^{
                                         [metas addObject:meta];
                                     });
                                 } else {
                                     NSLog(@"LibraryStore: failed to read metadata for %@", url);
                                 }
                                 dispatch_group_leave(group);
                             }];
        }

        dispatch_group_wait(group, DISPATCH_TIME_FOREVER);

        NSError* err = nil;
        if (metas.count > 0) {
            [self importMediaItems:metas preferExisting:NO error:&err];
        }
        if (err) {
            NSLog(@"LibraryStore: importMediaItems failed: %@", err.localizedDescription);
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) {
                completion(metas.count > 0 ? [metas copy] : @[], err);
            }
        });
    });
}

// Read metadata from files without touching the database.
- (void)readFileURLs:(NSArray<NSURL*>*)urls completion:(void (^)(NSArray<MediaMetaData*>* _Nullable metas, NSError* _Nullable error))completion
{
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSMutableArray<MediaMetaData*>* metas = [NSMutableArray array];
        MetaController* loader = [MetaController new];
        dispatch_group_t group = dispatch_group_create();
        dispatch_queue_t mergeQueue = dispatch_queue_create("PlayEm.LibraryStore.ReadMerge", DISPATCH_QUEUE_SERIAL);

        for (NSURL* url in urls) {
            dispatch_group_enter(group);
            [loader loadAsyncWithPath:url.path
                             callback:^(MediaMetaData* meta) {
                                 if (meta) {
                                     dispatch_async(mergeQueue, ^{
                                         [metas addObject:meta];
                                     });
                                 } else {
                                     NSLog(@"LibraryStore: failed to read metadata for %@", url);
                                 }
                                 dispatch_group_leave(group);
                             }];
        }

        dispatch_group_wait(group, DISPATCH_TIME_FOREVER);

        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) {
                completion(metas.count > 0 ? [metas copy] : @[], nil);
            }
        });
    });
}

- (void)reconcileLibraryWithCompletion:(void (^)(NSArray<MediaMetaData*>* _Nullable refreshedMetas,
                                                 NSArray<MediaMetaData*>* _Nullable changedMetas,
                                                 NSArray<NSURL*>* missingFiles,
                                                 NSError* _Nullable error))completion
{
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSError* loadError = nil;
        NSArray<MediaMetaData*>* existing = [self loadAllMediaItems:&loadError];
        if (!existing) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (completion) {
                    completion(nil, nil, @[], loadError);
                }
            });
            return;
        }

        NSMutableDictionary<NSString*, MediaMetaData*>* existingByURL = [NSMutableDictionary dictionary];
        NSMutableArray<NSURL*>* existingURLs = [NSMutableArray array];
        NSMutableArray<NSURL*>* missing = [NSMutableArray array];
        NSFileManager* fm = [NSFileManager defaultManager];

        for (MediaMetaData* meta in existing) {
            NSURL* url = meta.location;
            if (url == nil) {
                continue;
            }
            BOOL isDir = NO;
            if (![fm fileExistsAtPath:url.path isDirectory:&isDir] || isDir) {
                [missing addObject:url];
                continue;
            }
            existingByURL[url.absoluteString] = meta;
            [existingURLs addObject:url];
        }

        [self readFileURLs:existingURLs
                  completion:^(NSArray<MediaMetaData*>* _Nullable metas, NSError* _Nullable importErr) {
                      dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
                          NSArray<MediaMetaData*>* refreshed = metas ?: @[];
                          NSMutableArray<MediaMetaData*>* changed = [NSMutableArray array];
                          NSMutableArray<MediaMetaData*>* toUpdate = [NSMutableArray array];
                          if (importErr) {
                              NSLog(@"LibraryStore: reconcile read error: %@", importErr.localizedDescription);
                          }

                          NSArray<NSString*>* writableKeys = @[
                              @"title",
                              @"artist",
                              @"album",
                              @"albumArtist",
                              @"genre",
                              @"comment",
                              @"tags",
                              @"key",
                              @"year",
                              @"track",
                              @"tracks",
                              @"disk",
                              @"disks",
                              @"tempo",
                              @"rating",
                              @"compilation",
                              @"artwork",
                              @"artworkFormat",
                              @"artworkLocation",
                              @"appleLocation",
                          ];

                          for (MediaMetaData* meta in refreshed) {
                              MediaMetaData* old = existingByURL[meta.location.absoluteString];
                              if (old && old.added) {
                                  meta.added = old.added;
                              }
                              if (old && old.duration) {
                                  meta.duration = old.duration;
                              }
                              // Avoid overwriting good metadata with obvious mojibake.
                              if (old) {
                                  NSArray<NSString*>* textKeys = @[ @"title", @"artist", @"album", @"albumArtist", @"genre", @"comment", @"tags", @"key" ];
                                  for (NSString* key in textKeys) {
                                      NSString* newVal = [meta valueForKey:key];
                                      if (newVal.length > 0) {
                                          NSString* sanitized = [newVal sanitizedMetadataString];
                                          if (![sanitized isEqualToString:newVal]) {
                                              [meta setValue:sanitized forKey:key];
                                              newVal = sanitized;
                                          }
                                      }
                                      NSString* oldVal = [old valueForKey:key];
                                      if ([newVal isLikelyMojibakeMetadata]) {
                                          if (oldVal.length > 0) {
                                              [meta setValue:oldVal forKey:key];
                                          } else {
                                              [meta setValue:@"" forKey:key];
                                          }
                                      }
                                  }
                              }
                              if (old && ![old isSemanticallyEqualToMeta:meta]) {
                                  [changed addObject:meta];

                                  MediaMetaData* merged = [old copy];
                                  for (NSString* key in writableKeys) {
                                      id newValue = [meta valueForKey:key];
                                      if (newValue != nil) {
                                          [merged setValue:newValue forKey:key];
                                      }
                                  }
                                  [toUpdate addObject:merged];
                              }
                          }

                          NSError* updateErr = nil;
                          if (toUpdate.count > 0) {
                              [self importMediaItems:toUpdate preferExisting:NO error:&updateErr];
                          }

                          dispatch_async(dispatch_get_main_queue(), ^{
                              if (completion) {
                                  completion(refreshed, changed, missing, updateErr ?: importErr);
                              }
                          });
                      });
                  }];
    });
}

- (BOOL)hasEntryForURL:(NSURL*)url error:(NSError**)error
{
    if (![self open:error]) {
        return NO;
    }

    const char* sql = "SELECT 1 FROM tracks WHERE url = ? LIMIT 1";
    sqlite3_stmt* stmt = NULL;
    int rc = sqlite3_prepare_v2(self.db, sql, -1, &stmt, NULL);
    if (rc != SQLITE_OK) {
        if (error) {
            *error = [NSError errorWithDomain:@"LibraryStore" code:rc userInfo:@{NSLocalizedDescriptionKey : @"Failed to prepare exists query"}];
        }
        return NO;
    }
    sqlite3_bind_text(stmt, 1, url.absoluteString.UTF8String, -1, SQLITE_TRANSIENT);
    rc = sqlite3_step(stmt);
    BOOL exists = (rc == SQLITE_ROW);
    sqlite3_finalize(stmt);
    return exists;
}

- (void)removeEntriesForURLs:(NSArray<NSURL*>*)urls completion:(void (^)(BOOL success, NSError* _Nullable error))completion
{
    if (urls.count == 0) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) {
                completion(YES, nil);
            }
        });
        return;
    }

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSError* openError = nil;
        if (![self open:&openError]) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (completion) {
                    completion(NO, openError);
                }
            });
            return;
        }

        const char* sql = "DELETE FROM tracks WHERE url = ?";
        sqlite3_stmt* stmt = NULL;
        int rc = sqlite3_prepare_v2(self.db, sql, -1, &stmt, NULL);
        if (rc != SQLITE_OK) {
            NSError* err = [NSError errorWithDomain:@"LibraryStore" code:rc userInfo:@{NSLocalizedDescriptionKey : @"Failed to prepare delete"}];
            dispatch_async(dispatch_get_main_queue(), ^{
                if (completion) {
                    completion(NO, err);
                }
            });
            return;
        }

        BOOL success = YES;
        NSError* stmtError = nil;
        for (NSURL* url in urls) {
            sqlite3_reset(stmt);
            sqlite3_clear_bindings(stmt);
            sqlite3_bind_text(stmt, 1, url.absoluteString.UTF8String, -1, SQLITE_TRANSIENT);
            rc = sqlite3_step(stmt);
            if (rc != SQLITE_DONE) {
                success = NO;
                stmtError = [NSError errorWithDomain:@"LibraryStore" code:rc userInfo:@{NSLocalizedDescriptionKey : @"Failed to delete row"}];
                break;
            }
        }

        sqlite3_finalize(stmt);

        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) {
                completion(success, stmtError);
            }
        });
    });
}

@end
