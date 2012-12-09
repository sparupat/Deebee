//
//  Deebee.m
//  v 1.0
//
//  Created by Will Flagello, licensed with Evey License.
//  ----------------------------------------------------------------------------------------------------
//  Special thanks to Chris Hulbert and his CHBgDropboxSync.
//
//  github.com/flvgello/deebee
//
//  Tested with Dropbox 1.3
//

// ----------------------------------------------------------------------------
// TO DO
// ----------------------------------------------------------------------------
// -
// ----------------------------------------------------------------------------
// CHANGES
// ----------------------------------------------------------------------------
// Move download, upload, delete et al in a method that has a similar behaviour of the one in CHBg…
// Why checking for metadata without syncing?
// Hence, check for metadata AND sync just after.
// The basic implementation remains the same, because loadMetadata has some good processes to look for
// changes et al. What needs to be changed is the way we sync things.
// In the download/upload/delete callbacks we do what's being done now, and then we
// laod another method that process only and solely the next thing. Given that we remove things from
// the original arrays, we don't need to do anything else but load the objects stored in NSUserDefaults
// every single time.
// This way we'll also have a better way to calculate progress.
// ----------------------------------------------------------------------------

#import <QuartzCore/QuartzCore.h>
#import "Deebee.h"
#import "NSTimer+Blocks.h"

#define DeebeeIsFirstSync                 @"DeebeeIsFirstSync"
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
    NSArray                 *validImageExtensions;
    NSOperationQueue        *operationsQueue;
    DBRestClient            *client;
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
    if (client) return;
    
    client = [[DBRestClient alloc] initWithSession:[DBSession sharedSession]];
    client.delegate = self;
    
    isMetadataComplete = YES;
    isSyncComplete = YES;
    
    operationsQueue = [NSOperationQueue mainQueue];
    operationsQueue.maxConcurrentOperationCount = 2;
    
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
    NSLog(@"Sync Files Only? —— %i", _syncFilesOnly);
    NSLog(@"Sync Images Only? —— %i", _syncImagesOnly);
    NSLog(@"Sync Thumbnails Only? —— %i", _syncThumbnailsOnly);
    NSLog(@"Thumbnails Size: %@", _thumbnailsSize);
    NSLog(@"Escape Root Files? —— %i", _escapeRootFiles);
    NSLog(@"Syncable File Extensions: %@", _syncableFileExtensions);
   
    [self.delegate didStartLoadingMetadata];
    [client loadMetadata:_remoteRootPath];
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
    __autoreleasing DBRestClient* autoreleaseClient = client;
    [autoreleaseClient description];
    
    client.delegate = nil;
    client = nil;
}



#pragma mark ----------------------------------------------------------------------------------------------
#pragma mark Out of the (Drop)box callbacks
#pragma mark ----------------------------------------------------------------------------------------------

- (void)restClient:(DBRestClient *)restClient loadedMetadata:(DBMetadata *)metadata
{
    if (!isSyncComplete) return;
    if (!isMetadataComplete) return;
    
    isMetadataComplete = NO;
    NSString *remotePath = metadata.path;
    NSLog(@"Current Metadata: %@", remotePath);
    
    NSMutableArray *folders = [NSMutableArray array];
    NSMutableArray *files = [NSMutableArray array];
    
    for (DBMetadata *item in metadata.contents){
        if (item.isDirectory){
            if (_syncFilesOnly)
                continue;
            
            NSMutableString *localPath = [NSMutableString stringWithString:[NSString stringWithFormat:@"%@%@", [self localRootDirectory], item.path]];
            DeebeeItem *folder = [DeebeeItem initFromMetadata:item withLocalPath:localPath];
            [folders addObject:folder];
            
            // IT HAS TO BE REWRITTEN WITH LOAD METADATA.
            if ([remotePath isEqualToString:@"/"]){
                NSLog(@"We are going through.");
                for (DBMetadata *itemInFolder in item.contents){
                    NSLog(@"item.contents: %@", item.contents);
                    if (itemInFolder.isDirectory)
                        continue;
                    
                    NSString *extension = [[itemInFolder.path pathExtension] lowercaseString];
                    
                    if (_syncImagesOnly)
                        if ([validImageExtensions indexOfObject:extension] == NSNotFound)
                            continue;
                    
                    if (_syncableFileExtensions)
                        if ([_syncableFileExtensions indexOfObject:extension] == NSNotFound)
                            continue;
                    
                    DeebeeItem *file = [DeebeeItem initFromMetadata:itemInFolder withLocalPath:localPath];
                    [files addObject:file];
                }
            }
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
                        [localItemsToUpload addObject:currentItem];
                        continue;
                    }
                }
                
                if (![lastAbstractLocalItems containsObject:currentItem]){
                    [localItemsToUpload addObject:currentItem];
                    continue;
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
    
    [self.delegate didLoadMetadataWithItemsToSync:remainingItemsToSync];
    
    if (isFirstSync){
        BOOL isFirstSyncCompleted = [self performInitSyncWithItems:remoteItemsToDownload];
        
        if (isFirstSyncCompleted){
            isMetadataComplete = YES;
            isFirstSync = NO;
            [[NSUserDefaults standardUserDefaults] setBool:isFirstSync forKey:DeebeeIsFirstSync];
            [[NSUserDefaults standardUserDefaults] synchronize];
            return;
        }
    } else {
        isMetadataComplete = YES;
        return;
    }
}

- (void)restClient:(DBRestClient*)client metadataUnchangedAtPath:(NSString*)path
{
    NSLog(@"Metadata Unchanged At Path: %@", path);
    [self endWithHappiness];
}

- (void)restClient:(DBRestClient*)client loadMetadataFailedWithError:(NSError*)error
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
}

- (void)restClient:(DBRestClient *)client deletePathFailedWithError:(NSError *)error
{
    if ([self.delegate respondsToSelector:@selector(remoteItemDeleteFailedWithError:)])
        [self.delegate remoteItemDeleteFailedWithError:error];
    NSLog(@"ERROR — Remote Delete Failed With Error: %@, %@", error, [error userInfo]);
}



#pragma mark ----------------------------------------------------------------------------------------------
#pragma mark Virgin Sync (Or: There's a First Time for Everyone)
#pragma mark ----------------------------------------------------------------------------------------------

- (BOOL)performInitSyncWithItems:(NSArray *)remoteItemsToDownload
{
    if (!isFirstSync) return YES;
    
    isSyncComplete = NO;
    [self.delegate didStartSyncing];
    
    int initialNumberOfRemoteItemsToDownload = [remoteItemsToDownload count];
    NSMutableArray *folders = [NSMutableArray array];
    NSMutableArray *files = [NSMutableArray array];
    
    for (DeebeeItem *item in remoteItemsToDownload){
        if (item.isDirectory){
            [folders addObject:item];
        } else {
            [files addObject:item];
        }
    }
    
    for (DeebeeItem *item in folders){
        NSLog(@"Creating Folder at Path: %@", item.localPath);
        NSError *error = nil;
        NSDictionary *attr = [NSDictionary dictionaryWithObject:item.lastModified forKey:NSFileModificationDate];
        if(![[NSFileManager defaultManager] createDirectoryAtPath:[NSMutableString stringWithString:item.localPath]
                                      withIntermediateDirectories:NO attributes:attr error:&error])
            NSLog(@"ERROR — Creating Folder: %@, %@", error, [error userInfo]);
    }
    int oopo = 0;
    
    for (DeebeeItem *item in files){
        oopo++;
        [operationsQueue addOperationWithBlock:^{
            if (item.hasThumbnail && _syncThumbnailsOnly){
                NSLog(@"Downloading Thumbnail: %@", item.path);
                [client loadThumbnail:item.path ofSize:_thumbnailsSize intoPath:item.localPath];
            } else {
                NSLog(@"Downloading File: %@", item.path);
                [client loadFile:item.path intoPath:item.localPath];
            }
        }];
    }
    
    NSLog(@"Times: %i", oopo);
    NSLog(@"OPERATIONS: %@", operationsQueue.operations);
    
    isSyncComplete = [self operationsProgress];
    
    if (isSyncComplete){        
        // Since we put files in folders, they'll have a different lastModified date.
        // Hence, update with the ones on Dropbox.
        for (DeebeeItem *item in folders){
            NSError *error = nil;
            NSDictionary *attr = [NSDictionary dictionaryWithObject:item.lastModified forKey:NSFileModificationDate];
            if (![[NSFileManager defaultManager] setAttributes:attr ofItemAtPath:item.localPath error:&error])
                NSLog(@"ERROR — Modifying Folder's Modification Date: %@, %@", error, [error userInfo]);
        }
        
        // There's no last if there's no first, right?
        // Set things up for the first time.         
        [[NSUserDefaults standardUserDefaults] setObject:[NSKeyedArchiver archivedDataWithRootObject:[self getCurrentPhysicalLocalItems]]
                                                  forKey:DeebeeLastPhysicalLocalItems];
        [[NSUserDefaults standardUserDefaults] setObject:[NSKeyedArchiver archivedDataWithRootObject:[self getCurrentAbstractLocalItems]]
                                                  forKey:DeebeeLastAbstractLocalItems];
        [[NSUserDefaults standardUserDefaults] synchronize];
        
        // We update the remoteItemsToDownload var after the sync. It'll let us perform some checks.
         NSArray *remoteItemsLeftToDownload = [NSKeyedUnarchiver unarchiveObjectWithData:[[NSUserDefaults standardUserDefaults] objectForKey:DeebeeRemoteItemsToDownload]];
        
        if ([remoteItemsLeftToDownload count] == 0){
            [self endWithHappiness];
        } else if ([remoteItemsLeftToDownload count] == initialNumberOfRemoteItemsToDownload){
            [self endWithFail];
        } else if ([remoteItemsLeftToDownload count] < initialNumberOfRemoteItemsToDownload){
            [self endWithPartialHappiness];
        }
        
        return isSyncComplete;
    }
    
    return NO;
}



#pragma mark ----------------------------------------------------------------------------------------------
#pragma mark Progress + Useful Local Methods = GOODNESS. Gimme a bear! YES, a BEAR.
#pragma mark ----------------------------------------------------------------------------------------------

- (BOOL)operationsProgress
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [NSTimer timerWithTimeInterval:7 block:^{
            NSLog(@"Operations Count: %i", operationsQueue.operationCount);
            [self.delegate didChangeSyncingWithItemsToSync:operationsQueue.operationCount];
        } repeats:YES];
    });
    
    if (operationsQueue.operationCount == 0)
        return YES;
    
    return NO;
}

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
    if (isFirstSync) return;
    if (!isSyncComplete) return;
        
    isSyncComplete = NO;
    [self.delegate didStartSyncing];
        
    NSMutableArray *folders = [NSMutableArray array];
    NSMutableArray *deletedLocalItems = [NSMutableArray array];
    NSMutableArray *localItemsToDelete = [NSKeyedUnarchiver unarchiveObjectWithData:[NSMutableArray arrayWithArray:[[NSUserDefaults standardUserDefaults] objectForKey:DeebeeLocalItemsToDelete]]];
    NSArray *localItemsToUpload = [NSKeyedUnarchiver unarchiveObjectWithData:[[NSUserDefaults standardUserDefaults] objectForKey:DeebeeLocalItemsToUpload]];
    NSArray *remoteItemsToDelete = [NSKeyedUnarchiver unarchiveObjectWithData:[[NSUserDefaults standardUserDefaults] objectForKey:DeebeeRemoteItemsToDelete]];
    NSArray *remoteItemsToDownload = [NSKeyedUnarchiver unarchiveObjectWithData:[[NSUserDefaults standardUserDefaults] objectForKey:DeebeeRemoteItemsToDownload]];
    
    int initialNumberOfLocalItemsToDelete = [localItemsToDelete count];
    int initialNumberOfLocalItemsToUpload = [localItemsToUpload count];
    int initialNumberOfRemoteItemsToDelete = [remoteItemsToDelete count];
    int initialNumberOfRemoteItemsToDownload = [remoteItemsToDownload count];

    if (initialNumberOfLocalItemsToDelete == 0 && initialNumberOfLocalItemsToUpload == 0 &&
        initialNumberOfRemoteItemsToDelete == 0 && initialNumberOfRemoteItemsToDownload == 0){
        NSLog(@"Nothing to sync.");
        [self endWithHappiness];
        return;
    }
    
    // We'll need to update NSUserDefaults with the synced items. All the other arrays will be treated
    // with methods that have a Dropbox callback. In this way, if an item is successfully synced, we
    // delete it from its array in NSUserDefaults. If not, and hence we got an error, we do nothing
    // so that we can sync it later, in the next call.
    // But… localItemsToDelete doesn't use a Dropbox method since it removes items locally.
    // Therefore we need to work on another solution, that is exploiting the NSError:
    // if error, do nothing, we retry later; if successfully deleted, we remove the item from the array.
    
    if (localItemsToDelete > 0){
        for (DeebeeItem *item in localItemsToDelete){
            [operationsQueue addOperationWithBlock:^{
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
                }
            }];
        }
        
        [localItemsToDelete removeObjectsInArray:deletedLocalItems];
        [[NSUserDefaults standardUserDefaults] setObject:[NSKeyedArchiver archivedDataWithRootObject:localItemsToDelete] forKey:DeebeeLocalItemsToDelete];
        [[NSUserDefaults standardUserDefaults] synchronize];
    }
    
    if (localItemsToUpload > 0){
        for (DeebeeItem *item in localItemsToUpload){
            // Do not upload entire folders, or even their entities only.
            if (item.isDirectory)
                continue;
            
            [operationsQueue addOperationWithBlock:^{
                NSLog(@"Uploading File: %@", item.path);
                [client uploadFile:[NSMutableString stringWithString:item.name]
                            toPath:[NSMutableString stringWithString:[item.path stringByDeletingLastPathComponent]]
                     withParentRev:nil
                          fromPath:[NSMutableString stringWithString:item.localPath]];
            }];
        }
    }
    
    if (remoteItemsToDelete > 0){
        for (DeebeeItem *item in remoteItemsToDelete){
            [operationsQueue addOperationWithBlock:^{
                NSLog(@"Deleting Remote Item: %@", item.path);
                [client deletePath:item.path];
            }];
        }
    }
    
    if (remoteItemsToDownload > 0){
        for (DeebeeItem *item in remoteItemsToDownload){
            if (item.isDirectory)
                [folders addObject:item];
            
            // Create directory if there's no local counterpart.
            [operationsQueue addOperationWithBlock:^{
                if (item.isDirectory){
                    NSLog(@"Creating Folder at Path: %@", item.localPath);
                    NSError *error = nil;
                    NSDictionary *attr = [NSDictionary dictionaryWithObject:item.lastModified forKey:NSFileModificationDate];
                    if(![[NSFileManager defaultManager] createDirectoryAtPath:[NSMutableString stringWithString:item.localPath]
                                                  withIntermediateDirectories:NO attributes:attr error:&error])
                        NSLog(@"ERROR — Creating Folder: %@, %@", error, [error userInfo]);
                }
            }];
            
            [operationsQueue addOperationWithBlock:^{
                if (item.hasThumbnail && _syncThumbnailsOnly){
                    NSLog(@"Downloading Thumbnail: %@", item.path);
                    [client loadThumbnail:item.path ofSize:_thumbnailsSize intoPath:item.localPath];
                } else {
                    NSLog(@"Downloading File: %@", item.path);
                    [client loadFile:item.path intoPath:item.localPath];
                }
            }];
        }
    }
    
    isSyncComplete = [self operationsProgress];
    if (isSyncComplete){
        // Since we put files in folders, they'll have a different lastModified date.
        // Hence, update the locals with the ones on Dropbox.
        for (DeebeeItem *item in folders){
            NSError *error = nil;
            NSDictionary *attr = [NSDictionary dictionaryWithObject:item.lastModified forKey:NSFileModificationDate];
            if (![[NSFileManager defaultManager] setAttributes:attr ofItemAtPath:item.localPath error:&error])
                NSLog(@"ERROR — Modifying Folder's Modification Date: %@, %@", error, [error userInfo]);
        }
        
        // Update LastLocalItems
        [[NSUserDefaults standardUserDefaults] setObject:[NSKeyedArchiver archivedDataWithRootObject:[self getCurrentPhysicalLocalItems]]
                                                  forKey:DeebeeLastPhysicalLocalItems];
        [[NSUserDefaults standardUserDefaults] setObject:[NSKeyedArchiver archivedDataWithRootObject:[self getCurrentAbstractLocalItems]]
                                                  forKey:DeebeeLastAbstractLocalItems];
        [[NSUserDefaults standardUserDefaults] synchronize];
        
        // We get the updated Defaults to check if there's some items that weren't synced, for one reason or another.
        // If any, we end the sync differently. If not, endWithHappiness.
        NSArray *localItemsLeftToDelete = [NSKeyedUnarchiver unarchiveObjectWithData:[[NSUserDefaults standardUserDefaults] objectForKey:DeebeeLocalItemsToDelete]];
        NSArray *localItemsLeftToUpload = [NSKeyedUnarchiver unarchiveObjectWithData:[[NSUserDefaults standardUserDefaults] objectForKey:DeebeeLocalItemsToUpload]];
        NSArray *remoteItemsLeftToDelete = [NSKeyedUnarchiver unarchiveObjectWithData:[[NSUserDefaults standardUserDefaults] objectForKey:DeebeeRemoteItemsToDelete]];
        NSArray *remoteItemsLeftToDownload = [NSKeyedUnarchiver unarchiveObjectWithData:[[NSUserDefaults standardUserDefaults] objectForKey:DeebeeRemoteItemsToDownload]];
        
        if ([remoteItemsLeftToDownload count] == 0 && [remoteItemsLeftToDelete count] == 0 &&
            [localItemsLeftToDelete count] == 0 && [localItemsLeftToUpload count] == 0){
            [self endWithHappiness];
        } else if ([remoteItemsLeftToDownload count] == initialNumberOfRemoteItemsToDownload && [remoteItemsLeftToDelete count] && initialNumberOfRemoteItemsToDelete &&
                     [localItemsLeftToDelete count] == initialNumberOfLocalItemsToDelete && [localItemsLeftToUpload count] == initialNumberOfLocalItemsToUpload){
                [self endWithFail];
        } else if ([remoteItemsLeftToDownload count] == initialNumberOfRemoteItemsToDownload || [remoteItemsLeftToDelete count] == initialNumberOfRemoteItemsToDelete ||
                   [localItemsLeftToDelete count] == initialNumberOfLocalItemsToDelete || [localItemsLeftToUpload count] == initialNumberOfLocalItemsToUpload){
            [self endWithPartialHappiness];
        } else if ([remoteItemsLeftToDownload count] < initialNumberOfRemoteItemsToDownload || [remoteItemsLeftToDelete count] < initialNumberOfRemoteItemsToDelete ||
                   [localItemsLeftToDelete count] < initialNumberOfLocalItemsToDelete || [localItemsLeftToUpload count] < initialNumberOfLocalItemsToUpload){
            [self endWithPartialHappiness];
        } else {
            // Temp.
            NSLog(@"END WITH FORCE, something went wrong."),
            [self endWithForce];
        }
    }
}

- (void)performLoadMetadata
{
    [self.delegate didStartLoadingMetadata];
    [client loadMetadata:_remoteRootPath];
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
