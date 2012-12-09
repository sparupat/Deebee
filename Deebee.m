//
//  Deebee.m
//  v 0.3 ß
//
//  Created by Will Flagello. MIT License.
//  ----------------------------------------------------------------------------------------------------
//  Special thanks to Chris Hulbert and his CHBgDropboxSync.
//
//  github.com/flvgello/deebee
//
//  For Dropbox iOS SDK 1.3
//

// ----------------------------------------------------------------------------------------------------------
// TO DO
// ----------------------------------------------------------------------------------------------------------
// - Implement a better way to handle sync errors. At the moment, if any error, sync never ends.
//   both for progress and sync itself.
// - Better progress.
// - IF lastAbstractLocalItems has items, AND currentAbstractLocalItems has no item?
// - IF lastAbstractLocalItems has items, AND currentAbstractLocalItems has no item OR Dropbox has no item?
// ----------------------------------------------------------------------------------------------------------

#import <QuartzCore/QuartzCore.h>
#import "Deebee.h"

#define DeebeeIsFirstSync                 @"DeebeeIsFirstSync"
#define DeebeeRemoteFoldersToSync         @"DeebeeRemoteFoldersToSync"
#define DeebeeRemoteItemsToDownload       @"DeebeeRemoteItemsToDownload"
#define DeebeeRemoteItemsToDelete         @"DeebeeRemoteItemsToDelete"
#define DeebeeLocalItemsToUpload          @"DeebeeLocalItemsToUpload"
#define DeebeeLocalItemsToDelete          @"DeebeeLocalItemsToDelete"
#define DeebeeCurrentAbstractLocalItems   @"DeebeeCurrentAbstractLocalItems"        // Abstract representation of current local files and folders. (DeebeeItem)
#define DeebeeLastPhysicalLocalItems      @"DeebeeLastPhysicalLocalItems"           // Physical representation of last sync local files and folders. (NSFileManager)
#define DeebeeLastAbstractLocalItems      @"DeebeeLastAbstractLocalItems"           // Abstract representation of last sync local files and folders. (DeebeeItem)

@interface Deebee()
{
    BOOL                    isDefaultLocalRootPath;
    BOOL                    isDefaultRemoteRootPath;
    BOOL                    isFirstSync;
    BOOL                    isMetadataComplete;
    BOOL                    isSyncComplete;
    int                     itemsToSync;
    NSMutableArray          *foldersToUpdateLocally;
    NSArray                 *validImageExtensions;
    DBRestClient            *DBClient;
}

@end


@implementation Deebee

#pragma mark ----------------------------------------------------------------------------------------------
#pragma mark Setup 
#pragma mark ----------------------------------------------------------------------------------------------

- (id)init
{
    self = [super init];
    if (self){
        if (![[NSUserDefaults standardUserDefaults] objectForKey:DeebeeIsFirstSync]){
            [[NSUserDefaults standardUserDefaults] setBool:YES forKey:DeebeeIsFirstSync];
            [[NSUserDefaults standardUserDefaults] synchronize];
        }
    }
    
    return self;
}

- (void)initDefaults
{
    [[NSUserDefaults standardUserDefaults] setObject:[NSKeyedArchiver archivedDataWithRootObject:[NSArray array]] forKey:DeebeeRemoteFoldersToSync];
    [[NSUserDefaults standardUserDefaults] setObject:[NSKeyedArchiver archivedDataWithRootObject:[NSArray array]] forKey:DeebeeRemoteItemsToDownload];
    [[NSUserDefaults standardUserDefaults] setObject:[NSKeyedArchiver archivedDataWithRootObject:[NSArray array]] forKey:DeebeeRemoteItemsToDelete];
    [[NSUserDefaults standardUserDefaults] setObject:[NSKeyedArchiver archivedDataWithRootObject:[NSArray array]] forKey:DeebeeLocalItemsToUpload];
    [[NSUserDefaults standardUserDefaults] setObject:[NSKeyedArchiver archivedDataWithRootObject:[NSArray array]] forKey:DeebeeLocalItemsToDelete];
    [[NSUserDefaults standardUserDefaults] setObject:[NSKeyedArchiver archivedDataWithRootObject:[NSArray array]] forKey:DeebeeLastAbstractLocalItems];
    [[NSUserDefaults standardUserDefaults] setObject:[NSKeyedArchiver archivedDataWithRootObject:[NSArray array]] forKey:DeebeeCurrentAbstractLocalItems];
    [[NSUserDefaults standardUserDefaults] setObject:[NSKeyedArchiver archivedDataWithRootObject:[NSDictionary dictionary]] forKey:DeebeeLastPhysicalLocalItems];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

- (void)eraseDefaults
{
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:DeebeeRemoteFoldersToSync];
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:DeebeeRemoteItemsToDownload];
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:DeebeeRemoteItemsToDelete];
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:DeebeeLocalItemsToUpload];
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:DeebeeLocalItemsToDelete];
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:DeebeeLastAbstractLocalItems];
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:DeebeeCurrentAbstractLocalItems];
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:DeebeeLastPhysicalLocalItems];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

- (void)initDeebee
{
    if (DBClient) return;
    
    DBClient = [[DBRestClient alloc] initWithSession:[DBSession sharedSession]];
    DBClient.delegate = self;
    
    isMetadataComplete = YES;
    isSyncComplete = YES;
    
    if ([_localRootPath length] == 0) isDefaultLocalRootPath = YES;
    if ([_remoteRootPath length] == 0) isDefaultRemoteRootPath = YES;
    if ([_thumbnailsSize length] == 0) _thumbnailsSize = @"l";
    if ([_syncableFileExtensions count] == 0) _syncableFileExtensions = nil;
    if (isDefaultLocalRootPath) _localRootPath = [self localRootDirectory];
    if (isDefaultRemoteRootPath) _remoteRootPath = @"/";
    if (_syncImagesOnly) validImageExtensions = [NSArray arrayWithObjects:@"jpg", @"jpeg", @"png", nil];
    
    _localRootPath = [self localRootDirectory];
    
    NSLog(@"Local Root Path —— %@", _localRootPath);
    NSLog(@"Remote Root Path —— %@", _remoteRootPath);
    NSLog(@"Default Root Path? —— %i", isDefaultLocalRootPath);
    NSLog(@"Default Remote Path? —— %i", isDefaultRemoteRootPath);
    NSLog(@"Sync First Level Only? —— %i", _syncFirstLevelOnly);
    NSLog(@"Sync Files Only? —— %i", _syncFilesOnly);
    NSLog(@"Sync Images Only? —— %i", _syncImagesOnly);
    NSLog(@"Sync Thumbnails Only? —— %i", _syncThumbnailsOnly);
    NSLog(@"Thumbnails Size: %@", _thumbnailsSize);
    NSLog(@"Escape Root Files? —— %i", _escapeRootFiles);
    NSLog(@"Syncable File Extensions: %@", _syncableFileExtensions);
   
    [self.delegate didStartLoadingMetadata];
    [DBClient loadMetadata:_remoteRootPath];
}


#pragma mark ----------------------------------------------------------------------------------------------
#pragma mark The End, as only the most breathtaking films can deliver.
#pragma mark ----------------------------------------------------------------------------------------------

- (void)endWithHappiness
{
    [self releaseClient];
    
    NSError *error = nil;
    if ([self.delegate respondsToSelector:@selector(syncDidEndWithResult:andError:)])
        [self.delegate didEndSyncingWithResult:@"withHappiness" andError:error];
}

- (void)endWithPartialHappiness
{
    [self releaseClient];
    
    NSError *error = [NSError errorWithDomain:@"Deebee Sync Error: some files weren't synced."
                                         code:1 userInfo:nil];
    if ([self.delegate respondsToSelector:@selector(syncDidEndWithResult:andError:)])
        [self.delegate didEndSyncingWithResult:@"withPartialHappiness" andError:error];
}

- (void)endWithForce
{
    [self releaseClient];
    
    NSError *error = [NSError errorWithDomain:@"Deebee Sync Error"
                                         code:2 userInfo:nil];
    if ([self.delegate respondsToSelector:@selector(syncDidEndWithResult:andError:)])
        [self.delegate didEndSyncingWithResult:@"withForce" andError:error];
}

- (void)endWithFail
{
    [self releaseClient];
    
    NSError *error = [NSError errorWithDomain:@"Deebee Sync Error"
                                         code:3 userInfo:nil];
    if ([self.delegate respondsToSelector:@selector(syncDidEndWithResult:andError:)])
        [self.delegate didEndSyncingWithResult:@"withEpicFail" andError:error];
}

- (void)releaseClient
{
    __autoreleasing DBRestClient *autoreleaseClient = DBClient;
    [autoreleaseClient description];
    
    DBClient.delegate = nil;
    DBClient = nil;
}



#pragma mark ----------------------------------------------------------------------------------------------
#pragma mark Out of the (Drop)box callbacks
#pragma mark ----------------------------------------------------------------------------------------------

- (void)restClient:(DBRestClient *)client loadedMetadata:(DBMetadata *)metadata
{
    if (!isSyncComplete || !isMetadataComplete) return;
    
    isMetadataComplete = NO;
    NSString *remotePath = metadata.path;
    NSLog(@"Current Metadata: %@", remotePath);
    
    foldersToUpdateLocally = [NSMutableArray array];
    NSMutableArray *folders = [NSMutableArray array];
    NSMutableArray *files = [NSMutableArray array];
    
    for (DBMetadata *item in metadata.contents){
        if (item.isDirectory){
            if (_syncFilesOnly)
                continue;
            
            if (_syncFirstLevelOnly)
                if (![remotePath isEqualToString:@"/"])
                    continue;
            
            NSMutableString *localPath = [NSMutableString stringWithString:[NSString stringWithFormat:@"%@%@", [self localRootDirectory], item.path]];
            DeebeeItem *folder = [DeebeeItem initFromMetadata:item withLocalPath:localPath];
            [folders addObject:folder];
        } else {
            if (_escapeRootFiles && [remotePath isEqualToString:@"/"])
                continue;
            
            NSString *extension = [[item.path pathExtension] lowercaseString];
            
            if (_syncImagesOnly)
                if ([validImageExtensions indexOfObject:extension] == NSNotFound)
                    continue;
            
            if ([_syncableFileExtensions count] != 0)
                if ([_syncableFileExtensions indexOfObject:extension] == NSNotFound)
                    continue;
            
            NSMutableString *localPath = [NSMutableString stringWithString:[NSString stringWithFormat:@"%@%@", [self localRootDirectory], item.path]];
            DeebeeItem *file = [DeebeeItem initFromMetadata:item withLocalPath:localPath];
            [files addObject:file];
        }
    }
        
    NSArray *previousRemoteItemsToDownload = [NSKeyedUnarchiver unarchiveObjectWithData:[[NSUserDefaults standardUserDefaults] objectForKey:DeebeeRemoteItemsToDownload]];
    NSArray *previousLocalItemsToUpload = [NSKeyedUnarchiver unarchiveObjectWithData:[[NSUserDefaults standardUserDefaults] objectForKey:DeebeeLocalItemsToUpload]];
    NSArray *previousLocalItemsToDelete = [NSKeyedUnarchiver unarchiveObjectWithData:[[NSUserDefaults standardUserDefaults] objectForKey:DeebeeLocalItemsToDelete]];
    NSArray *previousRemoteItemsToDelete = [NSKeyedUnarchiver unarchiveObjectWithData:[[NSUserDefaults standardUserDefaults] objectForKey:DeebeeRemoteItemsToDelete]];
    
    NSMutableArray *remoteItemsToDownload = [NSMutableArray array];
    NSMutableArray *remoteItemsToDelete = [NSMutableArray array];
    NSMutableArray *localItemsToUpload = [NSMutableArray array];
    NSMutableArray *localItemsToDelete = [NSMutableArray array];
        
    [folders addObjectsFromArray:[NSKeyedUnarchiver unarchiveObjectWithData:[[NSUserDefaults standardUserDefaults] objectForKey:DeebeeRemoteFoldersToSync]]];
    [[NSUserDefaults standardUserDefaults] setObject:[NSKeyedArchiver archivedDataWithRootObject:folders] forKey:DeebeeRemoteFoldersToSync];
    [[NSUserDefaults standardUserDefaults] setObject:[NSKeyedArchiver archivedDataWithRootObject:[self getCurrentAbstractLocalItems]]
                                              forKey:DeebeeCurrentAbstractLocalItems];
    [[NSUserDefaults standardUserDefaults] synchronize];
        
    NSArray *lastAbstractLocalItems = [NSKeyedUnarchiver unarchiveObjectWithData:[[NSUserDefaults standardUserDefaults] objectForKey:DeebeeLastAbstractLocalItems]];
    NSArray *currentAbstractLocalItems = [NSKeyedUnarchiver unarchiveObjectWithData:[[NSUserDefaults standardUserDefaults] objectForKey:DeebeeCurrentAbstractLocalItems]];

    remoteItemsToDownload = [NSMutableArray arrayWithArray:[remoteItemsToDownload arrayByAddingObjectsFromArray:previousRemoteItemsToDownload]];
    remoteItemsToDownload = [NSMutableArray arrayWithArray:[remoteItemsToDownload arrayByAddingObjectsFromArray:folders]];
    remoteItemsToDownload = [NSMutableArray arrayWithArray:[remoteItemsToDownload arrayByAddingObjectsFromArray:files]];
    remoteItemsToDelete = [NSMutableArray arrayWithArray:[remoteItemsToDelete arrayByAddingObjectsFromArray:previousRemoteItemsToDelete]];
    localItemsToUpload = [NSMutableArray arrayWithArray:[localItemsToUpload arrayByAddingObjectsFromArray:previousLocalItemsToUpload]];
    localItemsToDelete = [NSMutableArray arrayWithArray:[localItemsToDelete arrayByAddingObjectsFromArray:previousLocalItemsToDelete]];
    
    // 1. The first step is comparing lastAbstractLocalItems and currentAbstractLocalItems.
    // IF a currentAbstractLocalItems' item IS in lastAbstractLocalItems BUT it is NOT in remoteItemsToDownload, put it in localItemsToDelete.
    // IF a currentAbstractLocalItems' item is NOT in lastAbstractLocalItems, put it in localItemsToUpload.
    // IF a currentAbstractLocalItems' item is NEWER that the one in lastAbstractLocalItems, put it in localItemsToUpload.
    // IF a lastAbstractLocalItems' item is NOT in currentAbstractLocalItems AND it is in remoteItemsToDownload, put it in remoteItemsToDelete.
    // IF it's the same, do nothing.
    
    if ([lastAbstractLocalItems count] > 0 && [currentAbstractLocalItems count] > 0){
        if ([remoteItemsToDownload count] > 0){
            for (DeebeeItem *currentItem in currentAbstractLocalItems){
                if ([lastAbstractLocalItems containsObject:currentItem]){
                    DeebeeItem *lastItem = [lastAbstractLocalItems objectAtIndex:[lastAbstractLocalItems indexOfObject:currentItem]];
                    
                    if (![remoteItemsToDownload containsObject:currentItem]){
                        [localItemsToDelete addObject:currentItem];
                        continue;
                    }
                    
                    if (currentItem.lastModified.timeIntervalSinceReferenceDate > lastItem.lastModified.timeIntervalSinceReferenceDate){
                        if (!currentItem.isDirectory){
                            [localItemsToUpload addObject:currentItem];
                            continue;
                        }
                    }
                }
                
                if (![lastAbstractLocalItems containsObject:currentItem]){
                    if (!currentItem.isDirectory){
                        [localItemsToUpload addObject:currentItem];
                        continue;
                    }
                }
            }
            
            for (DeebeeItem *lastItem in lastAbstractLocalItems){
                if (![currentAbstractLocalItems containsObject:lastItem] && [remoteItemsToDownload containsObject:lastItem]){
                    [remoteItemsToDelete addObject:lastItem];
                }
            }
        }
    }

    // 2. The second and most important step is comparing currentAbstractLocalItems to remoteItemsToDownload.
    // IF item IS in both, and has the SAME lastModified date, REMOVE it from remoteItemsToDownload.
    // This will create a incredibly narrower array that will basically be a delta.
    
    if ([currentAbstractLocalItems count] > 0 && [remoteItemsToDownload count] > 0){
        for (DeebeeItem *currentItem in currentAbstractLocalItems){
            if ([remoteItemsToDownload containsObject:currentItem]){
                DeebeeItem *remoteItem = [remoteItemsToDownload objectAtIndex:[remoteItemsToDownload indexOfObject:currentItem]];
                
                if (currentItem.lastModified.timeIntervalSinceReferenceDate == remoteItem.lastModified.timeIntervalSinceReferenceDate){
                    [remoteItemsToDownload removeObject:remoteItem];
                    continue;
                }
            }
        }
    }
    
    // 3. The third, final step is comparing the arrays we populated earlier (IF any update) with remoteItemsToDownload, to avoid conflicts.
    // IF one of those array's items APPEARS in remoteItemsToDownload, we compare the lastModified date.
    // IF lastModified is newer in LOCAL, we DO NOT download that specific file from Dropbox, and hence we remove it from that array.
    // IF lastModified is newer in DROPBOX, we delete that item from localItemsToUpload/remoteItemsToDelete/localItemsToDelete AND
    // leave it in remoteItemsToDownload.
    // IF lastModified is the same, nothing to do, delete item from both arrays.
    
    if (([localItemsToDelete count] > 0 || [localItemsToUpload count] > 0 || [remoteItemsToDelete count] > 0) && [remoteItemsToDownload count] > 0){
        if ([localItemsToDelete count] > 0){
            for (DeebeeItem *localItem in localItemsToDelete){
                if ([remoteItemsToDownload containsObject:localItem]){
                    DeebeeItem *remoteItem = [remoteItemsToDownload objectAtIndex:[remoteItemsToDownload indexOfObject:localItem]];
                    
                    if (localItem.lastModified.timeIntervalSinceReferenceDate > remoteItem.lastModified.timeIntervalSinceReferenceDate){
                        [remoteItemsToDownload removeObject:remoteItem];
                        continue;
                    }
                    
                    if (localItem.lastModified.timeIntervalSinceReferenceDate < remoteItem.lastModified.timeIntervalSinceReferenceDate){
                        [localItemsToDelete removeObject:localItem];
                        continue;
                    }
                    
                    if (localItem.lastModified.timeIntervalSinceReferenceDate == remoteItem.lastModified.timeIntervalSinceReferenceDate){
                        [localItemsToDelete removeObject:localItem];
                        [remoteItemsToDownload removeObject:remoteItem];
                        continue;
                    }
                }
            }
        }
        
        if ([localItemsToUpload count] > 0){
            for (DeebeeItem *localItem in localItemsToUpload){
                if ([remoteItemsToDownload containsObject:localItem]){
                    DeebeeItem *remoteItem = [remoteItemsToDownload objectAtIndex:[remoteItemsToDownload indexOfObject:localItem]];
                    
                    if (localItem.lastModified.timeIntervalSinceReferenceDate > remoteItem.lastModified.timeIntervalSinceReferenceDate){
                        [remoteItemsToDownload removeObject:remoteItem];
                        continue;
                    }
                    
                    if (localItem.lastModified.timeIntervalSinceReferenceDate < remoteItem.lastModified.timeIntervalSinceReferenceDate){
                        [localItemsToUpload removeObject:localItem];
                        continue;
                    }
                    
                    if (localItem.lastModified.timeIntervalSinceReferenceDate == remoteItem.lastModified.timeIntervalSinceReferenceDate){
                        [localItemsToUpload removeObject:localItem];
                        [remoteItemsToDownload removeObject:remoteItem];
                        continue;
                    }
                }
            }
        }
        
        if ([remoteItemsToDelete count] > 0){
            for (DeebeeItem *localItem in remoteItemsToDelete){
                if ([remoteItemsToDownload containsObject:localItem]){
                    DeebeeItem *remoteItem = [remoteItemsToDownload objectAtIndex:[remoteItemsToDownload indexOfObject:localItem]];
                    
                    if (localItem.lastModified.timeIntervalSinceReferenceDate > remoteItem.lastModified.timeIntervalSinceReferenceDate){
                        [remoteItemsToDownload removeObject:remoteItem];
                        continue;
                    }
                    
                    if (localItem.lastModified.timeIntervalSinceReferenceDate < remoteItem.lastModified.timeIntervalSinceReferenceDate){
                        [remoteItemsToDelete removeObject:localItem];
                        continue;
                    }
                    
                    if (localItem.lastModified.timeIntervalSinceReferenceDate == remoteItem.lastModified.timeIntervalSinceReferenceDate){
                        [remoteItemsToDelete removeObject:localItem];
                        [remoteItemsToDownload removeObject:remoteItem];
                        continue;
                    }
                }
            }
        }
    }
    
    // Special Cases - TO DO
    // IF lastAbstractLocalItems has items, AND currentAbstractLocalItems has no item?
    // IF lastAbstractLocalItems has items, AND currentAbstractLocalItems has no item OR Dropbox has no item?
    
    // Store the updated arrays into NSUserDefaults.
    [[NSUserDefaults standardUserDefaults] setObject:[NSKeyedArchiver archivedDataWithRootObject:localItemsToDelete] forKey:DeebeeLocalItemsToDelete];
    [[NSUserDefaults standardUserDefaults] setObject:[NSKeyedArchiver archivedDataWithRootObject:localItemsToUpload] forKey:DeebeeLocalItemsToUpload];
    [[NSUserDefaults standardUserDefaults] setObject:[NSKeyedArchiver archivedDataWithRootObject:remoteItemsToDelete] forKey:DeebeeRemoteItemsToDelete];
    [[NSUserDefaults standardUserDefaults] setObject:[NSKeyedArchiver archivedDataWithRootObject:remoteItemsToDownload] forKey:DeebeeRemoteItemsToDownload];
    [[NSUserDefaults standardUserDefaults] synchronize];
    
    // Local Folders to update later.
    for (DeebeeItem *item in remoteItemsToDownload)
        if (item.isDirectory)
            [foldersToUpdateLocally addObject:item];
    
    // A check to see if there's nothing to sync.
    if ([localItemsToDelete count] == 0 && [localItemsToUpload count] == 0 && [remoteItemsToDelete count] == 0 && [remoteItemsToDownload count] == 0){
        NSLog(@"Nothing to sync.");
        isMetadataComplete = YES;
        isSyncComplete = YES;
        if (isFirstSync) isFirstSync = NO;
        
        [self.delegate didLoadMetadataWithItemsToSync:0];
        [self endWithHappiness];
        
        return;
    }
    
    int remainingItemsToSync = [localItemsToDelete count] + [localItemsToUpload count] + [remoteItemsToDelete count] + [remoteItemsToDownload count];
    if (isFirstSync) remainingItemsToSync = [remoteItemsToDownload count];
    itemsToSync = remainingItemsToSync;
    
    [self.delegate didLoadMetadataWithItemsToSync:itemsToSync];
    
    [self.delegate didStartSyncing];
    [self performSyncOperations];
}

- (void)restClient:(DBRestClient *)client metadataUnchangedAtPath:(NSString *)path
{
    NSLog(@"Metadata Unchanged At Path: %@", path);
    [self endWithHappiness];
}

- (void)restClient:(DBRestClient *)client loadMetadataFailedWithError:(NSError *)error
{
    [self.delegate didLoadMetadataFailWithError:error];
    NSLog(@"ERROR — Load Metadata Failed With Error: %@, %@", error, [error userInfo]);
    [self endWithFail];
}

// --------------------------------------------------------------------------------------------------------
// Upload
// --------------------------------------------------------------------------------------------------------

- (void)restClient:(DBRestClient *)client uploadedFile:(NSString *)destPath from:(NSString *)srcPath metadata:(DBMetadata *)metadata
{
    NSLog(@"Successfully Uploaded File: %@", destPath);

    // Update the local lastModified data of the file to match the one on Dropbox.
    NSError *error = nil;
    NSDictionary *attr = [NSDictionary dictionaryWithObject:metadata.lastModifiedDate forKey:NSFileModificationDate];
    if (![[NSFileManager defaultManager] setAttributes:attr ofItemAtPath:srcPath error:&error])
        NSLog(@"ERROR — Modifying File's Modification Date After Upload: %@, %@", error, [error userInfo]);
        
    // Let's remove the uploaded item from DeebeeLocalItemsToUpload
    NSMutableString *localPath = [NSMutableString stringWithString:[NSString stringWithFormat:@"%@%@", [self localRootDirectory], metadata.path]];
    DeebeeItem *item = [DeebeeItem initFromMetadata:metadata withLocalPath:localPath];
    
    NSMutableArray *localItemsToUpload = [NSMutableArray arrayWithArray:[NSKeyedUnarchiver unarchiveObjectWithData:[[NSUserDefaults standardUserDefaults] objectForKey:DeebeeLocalItemsToUpload]]];
    if ([localItemsToUpload containsObject:item]){
        [localItemsToUpload removeObject:item];
        [[NSUserDefaults standardUserDefaults] setObject:[NSKeyedArchiver archivedDataWithRootObject:localItemsToUpload] forKey:DeebeeLocalItemsToUpload];
        [[NSUserDefaults standardUserDefaults] synchronize];
    } else {
        NSLog(@"ERROR — Removing Object from DeebeeLocalItemsToUpload");
    }
    
    itemsToSync--;
    [self.delegate didChangeSyncingWithItemsToSync:itemsToSync];
    
    [self performSyncOperations];
}

- (void)restClient:(DBRestClient *)client uploadFileFailedWithError:(NSError *)error
{
    if ([self.delegate respondsToSelector:@selector(itemUploadFailedWithError:)])
        [self.delegate itemUploadFailedWithError:error];
    NSLog(@"ERROR — Upload Failed With Error: %@, %@", error, [error userInfo]);
}

// --------------------------------------------------------------------------------------------------------
// Download
// --------------------------------------------------------------------------------------------------------

- (void)restClient:(DBRestClient *)client loadedFile:(NSString *)destPath contentType:(NSString *)contentType metadata:(DBMetadata *)metadata
{
    NSLog(@"Successfully Downloaded File: %@", destPath);
    
    // Update the local lastModified data of the file to match the one on Dropbox.
    NSError *error = nil;
    NSDictionary *attr = [NSDictionary dictionaryWithObject:metadata.lastModifiedDate forKey:NSFileModificationDate];
    if (![[NSFileManager defaultManager] setAttributes:attr ofItemAtPath:destPath error:&error])
        NSLog(@"ERROR — Modifying File's Modification Date After Download: %@, %@", error, [error userInfo]);
    
    // Let's remove the downloaded item from DeebeeRemoteItemsToDownload
    NSMutableString *localPath = [NSMutableString stringWithString:[NSString stringWithFormat:@"%@%@", [self localRootDirectory], metadata.path]];
    DeebeeItem *item = [DeebeeItem initFromMetadata:metadata withLocalPath:localPath];
    
    NSMutableArray *remoteItemsToDownload = [NSMutableArray arrayWithArray:[NSKeyedUnarchiver unarchiveObjectWithData:[[NSUserDefaults standardUserDefaults] objectForKey:DeebeeRemoteItemsToDownload]]];
    if ([remoteItemsToDownload containsObject:item]){
        [remoteItemsToDownload removeObject:item];
        [[NSUserDefaults standardUserDefaults] setObject:[NSKeyedArchiver archivedDataWithRootObject:remoteItemsToDownload] forKey:DeebeeRemoteItemsToDownload];
        [[NSUserDefaults standardUserDefaults] synchronize];
    } else {
        NSLog(@"ERROR — Removing Object from DeebeeRemoteItemsToDownload");
    }
    
    itemsToSync--;
    [self.delegate didChangeSyncingWithItemsToSync:itemsToSync];
    
    [self performSyncOperations];
}

- (void)restClient:(DBRestClient *)client loadFileFailedWithError:(NSError *)error
{
    if ([self.delegate respondsToSelector:@selector(itemDownloadFailedWithError:)])
        [self.delegate itemDownloadFailedWithError:error];
    NSLog(@"ERROR — Download Failed With Error: %@, %@", error, [error userInfo]);
}

- (void)restClient:(DBRestClient *)client loadedThumbnail:(NSString *)destPath metadata:(DBMetadata *)metadata
{
    NSLog(@"Successfully Downloaded Thumbnail: %@", destPath);
    
    // Update the local lastModified data of the file to match the one on Dropbox.
    NSError *error = nil;
    NSDictionary *attr = [NSDictionary dictionaryWithObject:metadata.lastModifiedDate forKey:NSFileModificationDate];
    if (![[NSFileManager defaultManager] setAttributes:attr ofItemAtPath:destPath error:&error])
        NSLog(@"ERROR — Modifying File's Modification Date After Download: %@, %@", error, [error userInfo]);
    
    // Let's remove the downloaded thumbnail from DeebeeRemoteItemsToDownload
    NSMutableString *localPath = [NSMutableString stringWithString:[NSString stringWithFormat:@"%@%@", [self localRootDirectory], metadata.path]];
    DeebeeItem *item = [DeebeeItem initFromMetadata:metadata withLocalPath:localPath];
    
    NSMutableArray *remoteItemsToDownload = [NSMutableArray arrayWithArray:[NSKeyedUnarchiver unarchiveObjectWithData:[[NSUserDefaults standardUserDefaults] objectForKey:DeebeeRemoteItemsToDownload]]];
    if ([remoteItemsToDownload containsObject:item]){
        [remoteItemsToDownload removeObject:item];
        [[NSUserDefaults standardUserDefaults] setObject:[NSKeyedArchiver archivedDataWithRootObject:remoteItemsToDownload] forKey:DeebeeRemoteItemsToDownload];
        [[NSUserDefaults standardUserDefaults] synchronize];
    } else {
        NSLog(@"ERROR — Removing Object from DeebeeRemoteItemsToDownload");
    }
    
    itemsToSync--;
    [self.delegate didChangeSyncingWithItemsToSync:itemsToSync];
    
    [self performSyncOperations];
}

- (void)restClient:(DBRestClient *)client loadThumbnailFailedWithError:(NSError *)error
{
    if ([self.delegate respondsToSelector:@selector(itemDownloadFailedWithError:)])
        [self.delegate itemDownloadFailedWithError:error];
    NSLog(@"ERROR — Thumbnail Download Failed With Error: %@, %@", error, [error userInfo]);
}

// --------------------------------------------------------------------------------------------------------
// Delete
// --------------------------------------------------------------------------------------------------------

- (void)restClient:(DBRestClient *)client deletedPath:(NSString *)path
{
    // Let's remove the removed item from DeebeeRemoteItemsToDelete
    NSMutableString *localPath = [NSMutableString stringWithString:[NSString stringWithFormat:@"%@%@", [self localRootDirectory], path]];
    DeebeeItem *item = [[DeebeeItem alloc] init];
    item.path = [NSMutableString stringWithString:path];
    item.localPath = localPath;
    item.ID = path;
    
    NSMutableArray *remoteItemsToDelete = [NSMutableArray arrayWithArray:[NSKeyedUnarchiver unarchiveObjectWithData:[[NSUserDefaults standardUserDefaults] objectForKey:DeebeeRemoteItemsToDelete]]];
    if ([remoteItemsToDelete containsObject:item]){
        [remoteItemsToDelete removeObject:item];
        [[NSUserDefaults standardUserDefaults] setObject:[NSKeyedArchiver archivedDataWithRootObject:remoteItemsToDelete] forKey:DeebeeRemoteItemsToDelete]; // check if mutable array goes with array, here.
        [[NSUserDefaults standardUserDefaults] synchronize];
    } else {
        NSLog(@"ERROR — Removing Object from DeebeeRemoteItemsToDelete");
    }
    
    itemsToSync--;
    [self.delegate didChangeSyncingWithItemsToSync:itemsToSync];
    
    [self performSyncOperations];
}

- (void)restClient:(DBRestClient *)client deletePathFailedWithError:(NSError *)error
{
    if ([self.delegate respondsToSelector:@selector(remoteItemDeleteFailedWithError:)])
        [self.delegate remoteItemDeleteFailedWithError:error];
    NSLog(@"ERROR — Remote Delete Failed With Error: %@, %@", error, [error userInfo]);
}



#pragma mark ----------------------------------------------------------------------------------------------
#pragma mark Sync Ops, AKA: Tomorrow Never Dies — & Virgin Sync (or: There's a First Time for Everything)
#pragma mark ----------------------------------------------------------------------------------------------

- (void)performSyncOperations
{    
    NSMutableArray *folders = [NSMutableArray array];
    NSMutableArray *deletedLocalItems = [NSMutableArray array];
    NSMutableArray *localItemsToDelete = [NSMutableArray arrayWithArray:[NSKeyedUnarchiver unarchiveObjectWithData:[[NSUserDefaults standardUserDefaults] objectForKey:DeebeeLocalItemsToDelete]]];
    NSMutableArray *localItemsToUpload = [NSMutableArray arrayWithArray:[NSKeyedUnarchiver unarchiveObjectWithData:[[NSUserDefaults standardUserDefaults] objectForKey:DeebeeLocalItemsToUpload]]];
    NSArray *remoteItemsToDelete = [NSKeyedUnarchiver unarchiveObjectWithData:[[NSUserDefaults standardUserDefaults] objectForKey:DeebeeRemoteItemsToDelete]];
    NSMutableArray *remoteItemsToDownload = [NSMutableArray arrayWithArray:[NSKeyedUnarchiver unarchiveObjectWithData:[[NSUserDefaults standardUserDefaults] objectForKey:DeebeeRemoteItemsToDownload]]];
    
    int numberOfLocalItemsToDelete = [localItemsToDelete count];
    int numberOfLocalItemsToUpload = [localItemsToUpload count];
    int numberOfRemoteItemsToDelete = [remoteItemsToDelete count];
    int numberOfRemoteItemsToDownload = [remoteItemsToDownload count];
    
    // We'll need to update NSUserDefaults with the synced items. All the other arrays will be treated
    // with methods that have a Dropbox callback. In this way, if an item is successfully synced, we
    // delete it from its array in NSUserDefaults. If not, and hence we got an error, we do nothing
    // so that we can sync it later, in the next call.
    // But… localItemsToDelete doesn't use a Dropbox method since it removes items locally.
    // Therefore we need to work on another solution, that is exploiting the NSError:
    // if error, do nothing, we retry later; if successfully deleted, we remove the item from the array.
    
    if (!isFirstSync){
        if (numberOfLocalItemsToDelete > 0){
            for (DeebeeItem *item in localItemsToDelete){
                NSError *error = nil;
                NSLog(@"Deleting Local Item: %@", item.path);
                if(![[NSFileManager defaultManager] removeItemAtPath:item.localPath error:&error]){
                    if ([self.delegate respondsToSelector:@selector(localItemDeleteFailedWithError:)])
                        [self.delegate localItemDeleteFailedWithError:error];
                    NSLog(@"ERROR — Deleting Local Item: %@, %@", error, [error userInfo]);
                    // We got an error, the item couldn't be deleted either because it's not there
                    // or because there was another kind of error.
                    // We do nothing, leave the record in the array, and try to repeat the operation in the next sync.
                } else {
                    if ([[NSKeyedUnarchiver unarchiveObjectWithData:[[NSUserDefaults standardUserDefaults] objectForKey:DeebeeLocalItemsToDelete]] containsObject:item])
                        [deletedLocalItems addObject:item];
                    // If the item was successfully deleted, we add it to the array that contains the deleted items
                    // so that we can remove them all later from the original array, localItemsToDelete.
                    
                    itemsToSync--;
                    [self.delegate didChangeSyncingWithItemsToSync:itemsToSync];
                }
            }
            
            [localItemsToDelete removeObjectsInArray:deletedLocalItems];
            [[NSUserDefaults standardUserDefaults] setObject:[NSKeyedArchiver archivedDataWithRootObject:localItemsToDelete] forKey:DeebeeLocalItemsToDelete];
            [[NSUserDefaults standardUserDefaults] synchronize];
        }
        
        if (numberOfLocalItemsToUpload > 0){
            DeebeeItem *nextItemToUpload = [localItemsToUpload objectAtIndex:0];
            NSLog(@"Uploading File: %@", nextItemToUpload.path);
            [DBClient uploadFile:[NSMutableString stringWithString:nextItemToUpload.name]
                          toPath:[NSMutableString stringWithString:[nextItemToUpload.path stringByDeletingLastPathComponent]]
                   withParentRev:nil
                        fromPath:[NSMutableString stringWithString:nextItemToUpload.localPath]];
            return;
        }
        
        if (numberOfRemoteItemsToDelete > 0){
            DeebeeItem *nextItemToDelete = [remoteItemsToDelete objectAtIndex:0];
            NSLog(@"Deleting Remote Item: %@", nextItemToDelete.path);
            [DBClient deletePath:nextItemToDelete.path];
            return;
        }
    }
       
    if (numberOfRemoteItemsToDownload > 0){
        DeebeeItem *nextItemToDownload = [remoteItemsToDownload objectAtIndex:0];
        while (nextItemToDownload.isDirectory){
            [folders addObject:nextItemToDownload];
            [remoteItemsToDownload removeObject:nextItemToDownload];
            [[NSUserDefaults standardUserDefaults] setObject:[NSKeyedArchiver archivedDataWithRootObject:remoteItemsToDownload] forKey:DeebeeRemoteItemsToDownload];
            [[NSUserDefaults standardUserDefaults] synchronize];
            
            // TO DO - Think about a better way to handle errors.
            NSLog(@"Creating Folder at Path: %@", nextItemToDownload.localPath);
            NSError *error = nil;
            NSDictionary *attr = [NSDictionary dictionaryWithObject:nextItemToDownload.lastModified forKey:NSFileModificationDate];
            if(![[NSFileManager defaultManager] createDirectoryAtPath:[NSMutableString stringWithString:nextItemToDownload.localPath]
                                          withIntermediateDirectories:NO attributes:attr error:&error]){
                NSLog(@"ERROR — Creating Folder: %@, %@", error, [error userInfo]);
            } else {
                itemsToSync--;
                [self.delegate didChangeSyncingWithItemsToSync:itemsToSync];
            }
                            
            if ([remoteItemsToDownload count] == 0){
                nextItemToDownload = nil;
                break;
            }
            
            nextItemToDownload = [remoteItemsToDownload objectAtIndex:0];
        }
        
        if (nextItemToDownload){
            if (nextItemToDownload.hasThumbnail && _syncThumbnailsOnly){
                NSLog(@"Downloading Thumbnail: %@", nextItemToDownload.path);
                [DBClient loadThumbnail:nextItemToDownload.path ofSize:_thumbnailsSize intoPath:nextItemToDownload.localPath];
                return;
            } else {
                NSLog(@"Downloading File: %@", nextItemToDownload.path);
                [DBClient loadFile:nextItemToDownload.path intoPath:nextItemToDownload.localPath];
                return;
            }
        }
    }
    
    // TO DO - MUST IMPLEMENT A BETTER WAY TO HANDLE SYNC.
    // At the moment we only endWithHappiness, and if there are any errors, sync never ends.
    if (itemsToSync == 0){
        // Since we put files in folders, they'll have a different lastModified date.
        // Hence, update with the ones on Dropbox.
        if ([foldersToUpdateLocally count] > 0){
            for (DeebeeItem *item in foldersToUpdateLocally){
                NSError *error = nil;
                NSDictionary *attr = [NSDictionary dictionaryWithObject:item.lastModified forKey:NSFileModificationDate];
                if (![[NSFileManager defaultManager] setAttributes:attr ofItemAtPath:item.localPath error:&error]){
                    NSLog(@"ERROR — Modifying Folder's Modification Date: %@, %@", error, [error userInfo]);
                } else {
                    [foldersToUpdateLocally removeObject:item];
                }
            }
        }
        
        isMetadataComplete = YES;
        isSyncComplete = YES;
        
        // If there's any folder to sync, we go through and loadMetadata for it.
        NSMutableArray *remoteFoldersToSync = [NSKeyedUnarchiver unarchiveObjectWithData:[[NSUserDefaults standardUserDefaults] objectForKey:DeebeeRemoteFoldersToSync]];
        if ([remoteFoldersToSync count] > 0){
            DeebeeItem *nextFolderToSync = [remoteFoldersToSync objectAtIndex:0];
            [remoteFoldersToSync removeObject:nextFolderToSync];
            [[NSUserDefaults standardUserDefaults] setObject:[NSKeyedArchiver archivedDataWithRootObject:remoteFoldersToSync] forKey:DeebeeRemoteFoldersToSync];
            [[NSUserDefaults standardUserDefaults] synchronize];
            
            [DBClient loadMetadata:nextFolderToSync.path];
            
            return;
        }
        
        if (isFirstSync){
            isFirstSync = NO;
            [[NSUserDefaults standardUserDefaults] setBool:isFirstSync forKey:DeebeeIsFirstSync];
            [[NSUserDefaults standardUserDefaults] synchronize];
        }
        
        NSLog(@"Sync Complete — Nothing left to sync.");
        
        // Update LastLocalItems
        [[NSUserDefaults standardUserDefaults] setObject:[NSKeyedArchiver archivedDataWithRootObject:[self getCurrentPhysicalLocalItems]]
                                                  forKey:DeebeeLastPhysicalLocalItems];
        [[NSUserDefaults standardUserDefaults] setObject:[NSKeyedArchiver archivedDataWithRootObject:[self getCurrentAbstractLocalItems]]
                                                  forKey:DeebeeLastAbstractLocalItems];
        [[NSUserDefaults standardUserDefaults] synchronize];
        
        [self endWithHappiness];
        return;
    }
}


#pragma mark ----------------------------------------------------------------------------------------------
#pragma mark Useful Local Methods = GOODNESS. Gimme a bear! YES, a BEAR.
#pragma mark ----------------------------------------------------------------------------------------------

- (NSDictionary *)getAllLocalFoldersAndFiles
{
    NSMutableDictionary *allLocalFoldersAndFiles = [NSMutableDictionary dictionary];
    NSDirectoryEnumerator *allLocalItems = [[NSFileManager defaultManager] enumeratorAtPath:_localRootPath];
    NSString *item = [NSString string];
    
    while (item = [allLocalItems nextObject]){
        if ([item hasPrefix:@"."]) continue;
        
        NSString *itemExtension = [[item pathExtension] lowercaseString];
        NSString* itemPath = [_localRootPath stringByAppendingPathComponent:item];
        NSDictionary* attribs = [[NSFileManager defaultManager] attributesOfItemAtPath:itemPath error:nil];
        
        BOOL isFile = [attribs.fileType isEqual:NSFileTypeRegular];
        BOOL isFolder = [attribs.fileType isEqual:NSFileTypeDirectory];
        
        if (isFile)
            if (![item pathExtension])
                continue;
        
        if (_syncFilesOnly)
            if (isFolder)
                continue;
        
        if (_syncImagesOnly)
            if (isFile && [validImageExtensions indexOfObject:itemExtension] == NSNotFound)
                continue;
        
        NSArray *arrayForFolderLevel = [item componentsSeparatedByString:@"/"];
        int folderLevel = [arrayForFolderLevel count] - 1;
        
        if (_escapeRootFiles)
            if (isFile && folderLevel == 0)
                continue;
        
        item = [NSString stringWithFormat:@"/%@", item];
        [allLocalFoldersAndFiles setObject:attribs.fileModificationDate forKey:item];
    }
    
    return allLocalFoldersAndFiles;
}

- (NSDictionary *)getCurrentPhysicalLocalItems
{
    NSMutableDictionary *currentPhysicalLocalItems = [NSMutableDictionary dictionary];
    NSDirectoryEnumerator *allLocalItems = [[NSFileManager defaultManager] enumeratorAtPath:_localRootPath];
    NSString *item = [NSString string];
    
    // Scan all local folders and files.
    while (item = [allLocalItems nextObject]){
        if ([item hasPrefix:@"."]) continue;
        
        NSString *itemExtension = [[item pathExtension] lowercaseString];
        NSString *itemPath = [_localRootPath stringByAppendingPathComponent:item];
        NSDictionary* attribs = [[NSFileManager defaultManager] attributesOfItemAtPath:itemPath error:nil];
        
        BOOL isFile = [attribs.fileType isEqual:NSFileTypeRegular];
        BOOL isFolder = [attribs.fileType isEqual:NSFileTypeDirectory];
        
        if (isFile)
            if (![item pathExtension])
                continue;
        
        if (_syncFilesOnly)
            if (isFolder)
                continue;
        
        if (_syncImagesOnly)
            if (isFile && [validImageExtensions indexOfObject:itemExtension] == NSNotFound)
                continue;
        
        if ([_syncableFileExtensions count] != 0)
            if (isFile && [_syncableFileExtensions indexOfObject:itemExtension] == NSNotFound)
                continue;
        
        NSArray *arrayForFolderLevel = [item componentsSeparatedByString:@"/"];
        int folderLevel = [arrayForFolderLevel count] - 1;
        
        if (_escapeRootFiles)
            if (isFile && folderLevel == 0)
                continue;
        
        item = [NSString stringWithFormat:@"/%@", item];
        [currentPhysicalLocalItems setObject:attribs.fileModificationDate forKey:item];
    }
    
    return currentPhysicalLocalItems;
}

- (NSArray *)getCurrentAbstractLocalItems
{
    NSDictionary *currentPhysicalLocalItems = [self getCurrentPhysicalLocalItems];
    NSMutableArray *currentAbstractLocalItems = [NSMutableArray array];
    
    for (NSString *path in currentPhysicalLocalItems){
        NSDate *physicalItemDate = [currentPhysicalLocalItems objectForKey:path];
        
        DeebeeItem *item = [DeebeeItem initFromLocalItemAtPath:path withLastModifiedDate:physicalItemDate andLocalRootPath:_localRootPath];
        [currentAbstractLocalItems addObject:item];
    }
    
    return currentAbstractLocalItems;
}



#pragma mark ----------------------------------------------------------------------------------------------
#pragma mark The One… everyone doens't give a shit about.
#pragma mark ----------------------------------------------------------------------------------------------

- (NSString *)localRootDirectory
{
    if (isDefaultLocalRootPath){
        return [NSString stringWithFormat:@"%@", [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) objectAtIndex:0]];
    } else {
        BOOL isDir = YES;
        if(![[NSFileManager defaultManager] fileExistsAtPath:_localRootPath isDirectory:&isDir])
            if(![[NSFileManager defaultManager] createDirectoryAtPath:_localRootPath withIntermediateDirectories:YES attributes:nil error:nil])
                NSLog(@"ERROR: Local Root Path folder creation failed.");
        
        return _localRootPath;
    }
}



#pragma mark ----------------------------------------------------------------------------------------------
#pragma mark «Get these in your app, NOW!»
#pragma mark ----------------------------------------------------------------------------------------------

- (void)initWithSync
{
    if (![[DBSession sharedSession] isLinked]) return;
    isFirstSync = [[NSUserDefaults standardUserDefaults] boolForKey:DeebeeIsFirstSync];
    if (!isFirstSync) return;
    
    dispatch_async(dispatch_get_main_queue(), ^{
        [self eraseDefaults];
        [self initDefaults];
        [self initDeebee];
    });
}

- (void)performSync
{
    [self.delegate didStartLoadingMetadata];
    [DBClient loadMetadata:_remoteRootPath];
}

// Erases all local files and folders but not those on Dropbox.
- (void)unlinkDropboxAndEraseAllLocalData
{
    if (![[DBSession sharedSession] isLinked]) return;
    
    [self endWithForce];
    [self eraseDefaults];
    [[DBSession sharedSession] unlinkAll];
    
    NSError *error = nil;
    NSArray *contentsOfPath = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:[self localRootDirectory] error:&error];
    
    dispatch_async(dispatch_get_main_queue(), ^{
        for (NSString *path in contentsOfPath){
            NSError *errorForRemove = nil;
            if (![[NSFileManager defaultManager] removeItemAtPath:path error:&errorForRemove])
                NSLog(@"ERROR — Unlink Dropbox And Erase All Local Data: %@, %@", error, [error userInfo]);
        }
    });
}

@end
