//
//  Deebee.m
//  v 0.1
//
//  Extended by Will Flagello, sublicensed with Evey License.
//  ----------------------------------------------------------------------------------------------------
//  Created by Chris Hulbert — github.com/chrishulbert — under the name CHBgDropboxSync, MIT License.
//
//  github.com/flvgello/deebee
//
//  Tested successfully with DropboxSDK 1.3
//

#import <QuartzCore/QuartzCore.h>
#import "Deebee.h"

#define syncSetup       @"DeebeeSetup"
#define syncStatusKey   @"DeebeeStatus"
#define syncCursor      @"DeebeeCursor"


// ----------------------------------------------------------------------------
// TO DO
// ----------------------------------------------------------------------------
// v 1.0
// ----------------------------------------------------------------------------
// MISC - Test thoroughly.
// MISC - Better Readme.
// ----------------------------------------------------------------------------
// v 1.1
// ----------------------------------------------------------------------------
// ADD - Comments.
// ADD - Progress.
// MISC - Improve Logs.
// ----------------------------------------------------------------------------
// v 2.0
// ----------------------------------------------------------------------------
// ADD - Core Data (optional).
// ADD - Delta check instead of Metadata.
// IMPROVE - Delegates.
// MISC - Refactor.
// ----------------------------------------------------------------------------


@interface Deebee()
{
    BOOL                    isDefaultLocalRootPath;
    BOOL                    isDefaultRemoteRootPath;
    BOOL                    hasReachedFirstLevel;
    BOOL                    hasReadAllFolders;
    NSArray                 *validExtensions;
    NSMutableString         *currentSyncingPath;
    NSMutableDictionary     *lastFolderModificationDate;
    DBRestClient            *client;
}

@end


@implementation Deebee

#pragma mark ----------------------------------------------------------------------------------------------
#pragma mark Startup
#pragma mark ----------------------------------------------------------------------------------------------

- (id)init
{
    self = [super init];
    if (self)
        [[NSUserDefaults standardUserDefaults] setBool:YES forKey:syncSetup];

    return self;
}

- (void)letTheHackingBegin
{
    if (client) return; // Already started
    
    client = [[DBRestClient alloc] initWithSession:[DBSession sharedSession]];
    client.delegate = self;
    
    if ([_localRootPath length] == 0)  isDefaultLocalRootPath = YES;
    if ([_remoteRootPath length] == 0) isDefaultRemoteRootPath = YES;
    if (isDefaultLocalRootPath) _localRootPath = [self localRootDirectory];
    if (isDefaultRemoteRootPath) _remoteRootPath = @"/";
    if (_syncImagesOnly) validExtensions = [NSArray arrayWithObjects:@"jpg", @"jpeg", @"png", @"gif", nil];
    if ([_thumbnailsSize length] == 0) _thumbnailsSize = @"l";
    
    NSLog(@"isDefaultLocalRootPath = %i", isDefaultLocalRootPath);
    NSLog(@"isDefaultRemoteRootPath = %i", isDefaultRemoteRootPath);
    NSLog(@"syncFilesOnly = %i", _syncFilesOnly);
    NSLog(@"syncImagesOnly = %i", _syncImagesOnly);
    NSLog(@"syncThumbnailsOnly = %i", _syncThumbnailsOnly);
    NSLog(@"escapeRootFiles = %i", _escapeRootFiles);
    
    hasReachedFirstLevel = NO;
    hasReadAllFolders = NO;
    lastFolderModificationDate = [NSMutableDictionary dictionary];
    
    /*
    if ([self.delegate respondsToSelector:@selector(syncShouldStart)])
        [self.delegate syncShouldStart];
    */
    
    [client loadMetadata:_remoteRootPath];
}

#pragma mark ----------------------------------------------------------------------------------------------
#pragma mark Sync Status - A permanent status of what's synced locally
#pragma mark ----------------------------------------------------------------------------------------------

- (void)syncStatusSetup
{
    [[NSUserDefaults standardUserDefaults] setObject:[NSDictionary dictionary] forKey:syncStatusKey];
    [[NSUserDefaults standardUserDefaults] setObject:[NSString string] forKey:syncCursor];
}

- (void)syncStatusScan
{
    [[NSUserDefaults standardUserDefaults] setObject:[self getAllLocalFoldersAndFiles] forKey:syncStatusKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

- (void)syncStatusClear
{
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:syncStatusKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

- (BOOL)syncStatusExistsForItem:(NSString *)item
{
    return [[[NSUserDefaults standardUserDefaults] arrayForKey:syncStatusKey] containsObject:item];
}

- (void)syncStatusRemoveForItem:(NSString *)item
{
    NSMutableArray *syncStatusFoldersAndFiles = [NSMutableArray arrayWithArray:[[NSUserDefaults standardUserDefaults] arrayForKey:syncStatusKey]];
    [syncStatusFoldersAndFiles removeObject:item];
    [[NSUserDefaults standardUserDefaults] setObject:syncStatusFoldersAndFiles forKey:syncStatusKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
}



#pragma mark ----------------------------------------------------------------------------------------------
#pragma mark Completion / Shutdown
#pragma mark ----------------------------------------------------------------------------------------------

- (void)loadMetadataAgain
{
    [client performSelector:@selector(loadMetadata:) withObject:currentSyncingPath afterDelay:.05];
}

- (void)internalCommonShutdown
{
    __autoreleasing DBRestClient* autoreleaseClient = client;
    [autoreleaseClient description];
    
    client.delegate = nil;
    client = nil;
}

- (void)internalShutdownForced
{
    /*
    if ([self.delegate respondsToSelector:@selector(syncShouldEnd)])
        [self.delegate syncShouldEnd];
     */
    
    [self internalCommonShutdown];
    
    if ([self.delegate respondsToSelector:@selector(syncDidEnd:)])
        [self.delegate syncDidEnd:@"withForce"];
}

- (void)internalShutdownSuccess
{
    /*
    if ([self.delegate respondsToSelector:@selector(syncShouldEnd)])
        [self.delegate syncShouldEnd];
    */
    
    [self syncStatusScan];
    [self internalCommonShutdown];
    
    NSLog(@"FDB in Defaults: %@", [[NSUserDefaults standardUserDefaults] objectForKey:syncStatusKey]);
    NSLog(@"All Local Files And Folders: %@", [self getAllLocalFoldersAndFiles]);
    
    if ([self.delegate respondsToSelector:@selector(syncDidEnd:)])
        [self.delegate syncDidEnd:@"withHappiness"];
}

- (void)internalShutdownFailed
{
    /*
    if ([self.delegate respondsToSelector:@selector(syncShouldEnd)])
        [self.delegate syncShouldEnd];
    */
    
    [self internalCommonShutdown];
    
    if ([self.delegate respondsToSelector:@selector(syncDidEnd:)])
        [self.delegate syncDidEnd:@"withFail"];
}



#pragma mark ----------------------------------------------------------------------------------------------
#pragma mark Async Dropbox Operations
#pragma mark ----------------------------------------------------------------------------------------------

// --------------------------------------------------------------------------------------------------------
// Upload
// --------------------------------------------------------------------------------------------------------

- (void)uploadFile:(NSString*)file fromPath:(NSString *)localPath atPath:(NSString *)remotePath withRev:(NSString*)rev
{
    NSLog(@"Sync: Uploading File %@, %@", file, rev?@"overwriting":@"new");
    [client uploadFile:file toPath:[NSString stringWithFormat:@"/%@", remotePath] withParentRev:rev fromPath:[localPath stringByAppendingPathComponent:file]];
}

- (void)restClient:(DBRestClient *)client uploadedFile:(NSString *)destPath from:(NSString *)srcPath metadata:(DBMetadata *)metadata
{
    NSDictionary *attr = [NSDictionary dictionaryWithObject:metadata.lastModifiedDate forKey:NSFileModificationDate];
    [[NSFileManager defaultManager] setAttributes:attr ofItemAtPath:srcPath error:nil];
    
    if ([self.delegate respondsToSelector:@selector(uploadedFile:atPath:)])
        [self.delegate uploadedFile:metadata atPath:destPath];
    
    [self loadMetadataAgain];
}

- (void)restClient:(DBRestClient*)client uploadFileFailedWithError:(NSError*)error
{
    NSLog(@"ERROR: %@, %@", error, [error userInfo]);
    [self internalShutdownFailed];
}

// --------------------------------------------------------------------------------------------------------
// Download
// --------------------------------------------------------------------------------------------------------

- (void)downloadFile:(NSString *)file toPath:(NSString *)localPath
{
    NSLog(@"Sync: Downloading file %@ to Path: %@", file, localPath);
    [client loadFile:[NSString stringWithFormat:@"/%@", file] intoPath:[[self localRootDirectory] stringByAppendingPathComponent:file]];
}

- (void)restClient:(DBRestClient *)client loadedFile:(NSString *)destPath contentType:(NSString *)contentType metadata:(DBMetadata *)metadata
{
    NSLog(@"Downloaded >%@<, its DB date is: %@", destPath, [metadata.lastModifiedDate descriptionWithLocale:[NSLocale currentLocale]]);
    NSDictionary *attr = [NSDictionary dictionaryWithObject:metadata.lastModifiedDate forKey:NSFileModificationDate];
    NSError *error = nil;
    if (![[NSFileManager defaultManager] setAttributes:attr ofItemAtPath:destPath error:&error])
        NSLog(@"ERROR: %@, %@", error, [error userInfo]);
    
    // Update folder's NSFileModificationDate to match the one on Dropbox if it's different from the parent folder.
    // Obviously, do not modify anything if we are syncing files in root.
    NSString *folder = [[lastFolderModificationDate allKeys] objectAtIndex:0];
    NSDictionary *attrForFolder = [NSDictionary dictionaryWithObject:[lastFolderModificationDate objectForKey:folder] forKey:NSFileModificationDate];
    if (![currentSyncingPath isEqualToString:@"/"])
        if (![[lastFolderModificationDate objectForKey:folder] isEqualToDate:metadata.lastModifiedDate])
            if (![[NSFileManager defaultManager] setAttributes:attrForFolder ofItemAtPath:[NSString stringWithFormat:@"%@%@", _localRootPath, folder] error:&error])
                NSLog(@"ERROR: %@, %@", error, [error userInfo]);
    
    if ([self.delegate respondsToSelector:@selector(downloadedFile:atPath:isThumbnail:)])
        [self.delegate downloadedFile:metadata atPath:destPath isThumbnail:NO];
        
    [self loadMetadataAgain];
}

- (void)restClient:(DBRestClient *)client loadFileFailedWithError:(NSError *)error
{
    NSLog(@"ERROR: %@, %@", error, [error userInfo]);
    [self internalShutdownFailed];
}

- (void)downloadThumbnailForImage:(NSString *)image toPath:(NSString *)localPath
{
    NSLog(@"Sync: Downloading Thumbnail %@ to Path: %@", image, localPath);
    [client loadThumbnail:[NSString stringWithFormat:@"/%@", image] ofSize:_thumbnailsSize intoPath:[localPath stringByAppendingPathComponent:image]];
}

- (void)restClient:(DBRestClient *)client loadedThumbnail:(NSString *)destPath metadata:(DBMetadata *)metadata
{
    NSLog(@"Downloaded Thumbnail >%@<, its DB date is: %@", destPath, [metadata.lastModifiedDate descriptionWithLocale:[NSLocale currentLocale]]);
    NSDictionary *attr = [NSDictionary dictionaryWithObject:metadata.lastModifiedDate forKey:NSFileModificationDate];
    NSError *error = nil;
    if (![[NSFileManager defaultManager] setAttributes:attr ofItemAtPath:destPath error:&error])
        NSLog(@"ERROR: %@, %@", error, [error userInfo]);
    
    // Update folder's NSFileModificationDate to match the one on Dropbox if it's different from the parent folder.
    // Obviously, do not modify anything if we are syncing files in root.
    NSString *folder = [[lastFolderModificationDate allKeys] objectAtIndex:0];
    NSDictionary *attrForFolder = [NSDictionary dictionaryWithObject:[lastFolderModificationDate objectForKey:folder] forKey:NSFileModificationDate];
    if (![currentSyncingPath isEqualToString:@"/"])
        if (![[lastFolderModificationDate objectForKey:folder] isEqualToDate:metadata.lastModifiedDate])
            if (![[NSFileManager defaultManager] setAttributes:attrForFolder ofItemAtPath:[NSString stringWithFormat:@"%@%@", _localRootPath, folder] error:&error])
                NSLog(@"ERROR: %@, %@", error, [error userInfo]);
    
    if ([self.delegate respondsToSelector:@selector(downloadedFile:atPath:isThumbnail:)])
        [self.delegate downloadedFile:metadata atPath:destPath isThumbnail:YES];
    
    [self loadMetadataAgain];
}

- (void)restClient:(DBRestClient *)client loadThumbnailFailedWithError:(NSError *)error
{
    NSLog(@"ERROR: %@, %@", error, [error userInfo]);
    [self internalShutdownFailed];
}

// --------------------------------------------------------------------------------------------------------
// Delete
// --------------------------------------------------------------------------------------------------------

- (void)deleteRemoteContent:(NSString *)content withType:(NSString *)contentType
{
    if ([contentType isEqualToString:@"folder"]){
        NSLog(@"Sync: Deleting remote folder %@", content);
    } else {
        NSLog(@"Sync: Deleting remote file %@", content);
    }
    
    [client deletePath:[NSString stringWithFormat:@"%@", content]];
    [self loadMetadataAgain];
}

- (void)restClient:(DBRestClient *)client deletedPath:(NSString *)path
{
    [self.delegate deletedFileAtPath:path wasRemote:YES];
    [self loadMetadataAgain];
}

- (void)restClient:(DBRestClient *)client deletePathFailedWithError:(NSError *)error
{
    NSLog(@"ERROR: %@, %@", error, [error userInfo]);
    [self internalShutdownFailed];
}

- (void)deleteLocalContent:(NSString *)content withType:(NSString *)contentType atPath:(NSString *)path
{
    NSError *error = nil;
    if ([contentType isEqualToString:@"folder"]){
        NSLog(@"Sync: Deleting local folder %@", content);
        if(![[NSFileManager defaultManager] removeItemAtPath:path error:&error])
            NSLog(@"ERROR: %@, %@", error, [error userInfo]);
    } else {
        NSLog(@"Sync: Deleting local file %@", content);
        if(![[NSFileManager defaultManager] removeItemAtPath:[path stringByAppendingPathComponent:content] error:&error])
            NSLog(@"ERROR: %@, %@", error, [error userInfo]);
    }
    
    if ([self.delegate respondsToSelector:@selector(deletedFileAtPath:wasRemote:)])
        [self.delegate deletedFileAtPath:path wasRemote:NO];
    
    [self loadMetadataAgain];
}



#pragma mark ----------------------------------------------------------------------------------------------
#pragma mark Local Files & Folders Operations
#pragma mark ----------------------------------------------------------------------------------------------

- (NSDictionary *)getLocalStatusForFoldersAtPath:(NSString *)path
{
    if (_syncFilesOnly) return nil;
    
    NSMutableDictionary *localFolders = [NSMutableDictionary dictionary];
    for (__strong NSString *item in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:path error:nil]){
        // Skip hidden/system folders.
        if ([item hasPrefix:@"."]) continue;
        
        // Get the full path and attribs
        NSString *itemPath = [path stringByAppendingPathComponent:item];
        NSDictionary *attribs = [[NSFileManager defaultManager] attributesOfItemAtPath:itemPath error:nil];
        BOOL isFolder = [attribs.fileType isEqual:NSFileTypeDirectory];
        if (!isFolder) continue;
        
        NSLog(@"Pre Folder Item: %@", item);

        item = [NSString stringWithFormat:@"/%@", item];
        
        NSLog(@"Post Folder Item: %@", item);
        
        [localFolders setObject:attribs.fileModificationDate forKey:item];
    }
    
    return localFolders;
}

- (NSDictionary *)getLocalStatusForFilesAtPath:(NSString *)path
{
    NSMutableDictionary *localFiles = [NSMutableDictionary dictionary];
    for (__strong NSMutableString *item in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:path error:nil]){
        // Skip hidden/system files.
        if ([item hasPrefix:@"."]) continue;
        if (![item pathExtension]) continue;
            
        NSString *itemExtension = [[item pathExtension] lowercaseString];
        if (_syncImagesOnly)
            if ([validExtensions indexOfObject:itemExtension] == NSNotFound)
                continue;
        
        if (_escapeRootFiles)
            if ([currentSyncingPath isEqualToString:@"/"])
                continue;
        
        NSLog(@"Item Path: %@", path);
        
        NSString *itemPath = [path stringByAppendingPathComponent:item];
        NSDictionary *attribs = [[NSFileManager defaultManager] attributesOfItemAtPath:itemPath error:nil];
        BOOL isFile = [attribs.fileType isEqual:NSFileTypeRegular];
        if (!isFile) continue;
        
        NSLog(@"Pre Item: %@", item);
        NSLog(@"Current SyncPath: %@", currentSyncingPath);
        
        item = [NSMutableString stringWithFormat:@"%@/%@", path, item];
        item = [NSMutableString stringWithString:[item stringByReplacingOccurrencesOfString:_localRootPath withString:@""]];
        
        if ([currentSyncingPath isEqualToString:@"/"])
            item = [NSMutableString stringWithString:[item substringFromIndex:1]];
                
        NSLog(@"Post Item: %@", item);
        
        [localFiles setObject:attribs.fileModificationDate forKey:item];
    }
    
    return localFiles;
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
            if (isFile && [validExtensions indexOfObject:itemExtension] == NSNotFound)
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



#pragma mark ----------------------------------------------------------------------------------------------
#pragma mark Syncs
#pragma mark ----------------------------------------------------------------------------------------------

- (BOOL)syncForLocalPath:(NSString *)localPath andRemotePath:(NSString *)remotePath withRemoteFolders:(NSDictionary *)remoteFolders
          andFoldersRevs:(NSDictionary *)remoteFoldersRevs plusRemoteFiles:(NSDictionary *)remoteFiles remoteFilesRevs:(NSDictionary *)remoteFilesRevs andRemoteFilesThumbnails:(NSDictionary *)remoteFilesThumbnails
{    
    currentSyncingPath = [NSMutableString stringWithString:remotePath];
    
    NSDictionary *localFolders = [self getLocalStatusForFoldersAtPath:localPath];
    NSDictionary *localFiles = [self getLocalStatusForFilesAtPath:localPath];
    
    NSLog(@"Local Path: %@", localPath);
    NSLog(@"localFolders: %@", localFolders);
    NSLog(@"localFiles: %@", localFiles);
    
    NSMutableDictionary *syncStatus = [NSMutableDictionary dictionaryWithDictionary:[[NSUserDefaults standardUserDefaults] objectForKey:syncStatusKey]];
        
    for (NSString *folder in localFolders)
        if (![syncStatus objectForKey:folder])
            [syncStatus setObject:[localFolders objectForKey:folder] forKey:folder];
    
    for (NSString *file in localFiles)
        if (![syncStatus objectForKey:file])
            [syncStatus setObject:[localFiles objectForKey:file] forKey:file];
    
    [[NSUserDefaults standardUserDefaults] setObject:syncStatus forKey:syncStatusKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
             
    NSMutableSet *allFolders = [NSMutableSet set];
    NSMutableSet *allFiles = [NSMutableSet set];
    
    [allFolders addObjectsFromArray:localFolders.allKeys];
    [allFolders addObjectsFromArray:remoteFolders.allKeys];
    [allFiles addObjectsFromArray:localFiles.allKeys];
    [allFiles addObjectsFromArray:remoteFiles.allKeys];
    
    BOOL hasFinishedInRoot = NO;
    BOOL hasFinished = NO;    
    BOOL hasFinishedSyncingFiles = NO;
    BOOL hasFinishedSyncingFolders = [self syncFolders:allFolders withLocalFolders:localFolders andRemoteFolders:remoteFolders
                                          forLocalPath:localPath andRemotePath:remotePath];

    if (hasFinishedSyncingFolders)
        hasFinishedSyncingFiles = [self syncFiles:allFiles withLocalFiles:localFiles andRemoteFiles:remoteFiles plusRemoteFilesRevs:remoteFilesRevs
                         andRemoteFilesThumbnails:remoteFilesThumbnails forLocalPath:localPath andRemotePath:remotePath];
    
    if ([currentSyncingPath isEqualToString:@"/"] && [localFiles count] == [remoteFiles count])
        hasFinishedInRoot = YES;
     
    NSLog(@"hasFinishedSyncingFolders: %i", hasFinishedSyncingFolders);
    NSLog(@"hasFinishedSyncingFiles: %i", hasFinishedSyncingFiles);
    NSLog(@"hasReachedFirstLevel: %i", hasReachedFirstLevel);
    NSLog(@"hasReadAllFolders: %i", hasReadAllFolders);
    NSLog(@"hasFinishedInRoot: %i", hasFinishedInRoot);
    
    if (hasFinishedSyncingFolders && hasFinishedSyncingFiles && hasReachedFirstLevel && (!hasReadAllFolders || !hasFinishedInRoot))
        [client loadMetadata:_remoteRootPath];
        
    if (hasFinishedSyncingFolders && hasFinishedSyncingFiles && hasReachedFirstLevel && hasReadAllFolders && hasFinishedInRoot)
        hasFinished = YES; else hasFinished = NO;
        
    NSLog(@"hasFinished: %i", hasFinished);
    return hasFinished;
}

- (BOOL)syncFolders:(NSMutableSet *)folders withLocalFolders:(NSDictionary *)localFolders andRemoteFolders:(NSDictionary *)remoteFolders
            forLocalPath:(NSString *)currentLocalPath andRemotePath:(NSString *)currentRemotePath
{    
    NSLog(@"CURRENT REMOTE PATH: %@ ––––––––––– REMOTE ROOT PATH: %@", currentRemotePath, _remoteRootPath);
    
    int numberOfFolders = [folders count];
    int currentFolder = 0;
    
    if (!hasReachedFirstLevel || (!hasReadAllFolders && [currentRemotePath isEqual:_remoteRootPath])){
        for (NSString *folder in folders){
            currentFolder++;
            NSDate *local = [localFolders objectForKey:folder];
            NSDate *remote = [remoteFolders objectForKey:folder];
            BOOL isFolderInSyncStatus = [self syncStatusExistsForItem:folder];
                                                
            NSLog(@"Folders Read: %i out of %i", currentFolder, numberOfFolders);
            
            NSLog(@"FOLDER: %@", folder);
            NSLog(@"LOCAL FOLDER: %@", local);
            NSLog(@"REMOTE FOLDER: %@", remote);
            NSLog(@"LAST SYNC EXISTS FOR FOLDER: %i", isFolderInSyncStatus);
            
            hasReachedFirstLevel = YES;
            if (currentFolder == numberOfFolders)
                hasReadAllFolders = YES;
            
            if (local && remote){
                double delta = local.timeIntervalSinceReferenceDate - remote.timeIntervalSinceReferenceDate;
                BOOL same = ABS(delta) < 2; // If they're within 2 seconds, that's close enough to be the same
                if (!same){
                    [client loadMetadata:folder];
                    return  NO;
                }
            } else {
                if (remote && !local) {
                    if (isFolderInSyncStatus){
                        [self syncStatusRemoveForItem:folder];
                        [self deleteRemoteContent:folder withType:@"folder"];
                        return NO;
                    } else {
                        NSLog(@"Creating Folder at Path: %@%@", [self localRootDirectory], folder);
                        NSError *error = nil;
                        NSDictionary *attr = [NSDictionary dictionaryWithObject:remote forKey:NSFileModificationDate];
                        if(![[NSFileManager defaultManager] createDirectoryAtPath:[NSString stringWithFormat:@"%@%@", [self localRootDirectory], folder]
                                                      withIntermediateDirectories:NO attributes:attr error:&error])
                            NSLog(@"ERROR: %@, %@", error, [error userInfo]);
                        
                        NSLog(@"FOLDER ATTR: %@", attr);
                        lastFolderModificationDate = [NSMutableDictionary dictionaryWithObject:remote forKey:folder];
                        
                        [client loadMetadata:folder];
                        return NO;
                    }
                }
                if (local && !remote) {
                    if (isFolderInSyncStatus){
                        [self syncStatusRemoveForItem:folder];
                        [self deleteLocalContent:folder withType:@"folder" atPath:currentLocalPath];
                        return NO;
                    } else {                        
                        [client loadMetadata:folder];
                        return NO;
                    }
                }
            }
        }
    }
    
    return YES;
}

- (BOOL)syncFiles:(NSMutableSet *)files withLocalFiles:(NSDictionary *)localFiles andRemoteFiles:(NSDictionary*)remoteFiles plusRemoteFilesRevs:(NSDictionary*)remoteRevs
        andRemoteFilesThumbnails:(NSDictionary *)remoteFilesThumbnails forLocalPath:(NSString *)currentLocalPath andRemotePath:(NSString *)currentRemotePath
{
    for (NSString *file in files) {
        NSLog(@"File: %@", file);
        
        NSDate *local = [localFiles objectForKey:file];
        NSDate *remote = [remoteFiles objectForKey:file];
        BOOL isFileInSyncStatus = [self syncStatusExistsForItem:file];
        
        NSLog(@"Local: %@", local);
        NSLog(@"Remote: %@", remote);
        
        if (local && remote) {
            double delta = local.timeIntervalSinceReferenceDate - remote.timeIntervalSinceReferenceDate;
            BOOL same = ABS(delta) < 2; // If they're within 2 seconds, that's close enough to be the same
            if (!same){
                if (local.timeIntervalSinceReferenceDate > remote.timeIntervalSinceReferenceDate){
                    [self uploadFile:file fromPath:currentLocalPath atPath:currentRemotePath withRev:[remoteRevs objectForKey:file]];
                    return NO;
                } else {
                    if ([[remoteFilesThumbnails objectForKey:file] intValue] == 1){
                        if (_syncThumbnailsOnly)
                            [self downloadThumbnailForImage:file toPath:_localRootPath];
                        else [self downloadFile:file toPath:currentLocalPath];
                    } else {
                        [self downloadFile:file toPath:currentLocalPath];
                    }
                    return NO;
                }
            }
        } else {
            if (remote && !local){
                if (isFileInSyncStatus){
                    [self syncStatusRemoveForItem:file];
                    [self deleteRemoteContent:file withType:@"file"];
                    return NO;
                } else {
                    if ([[remoteFilesThumbnails objectForKey:file] intValue] == 1){
                        if (_syncThumbnailsOnly)
                            [self downloadThumbnailForImage:file toPath:_localRootPath];
                        else [self downloadFile:file toPath:currentLocalPath];
                    } else {
                        [self downloadFile:file toPath:currentLocalPath];
                    }
                    
                    return NO;
                }
            }
            
            if (local && !remote) {
                if (isFileInSyncStatus){
                    [self syncStatusRemoveForItem:file]; // Clear the 'last sync' for just this file, so we don't try deleting it again
                    [self deleteLocalContent:file withType:@"file" atPath:currentLocalPath];
                    return NO;
                } else {                    
                    [self uploadFile:file fromPath:currentLocalPath atPath:currentRemotePath withRev:nil];
                    return NO;
                }
            }
        }       
    }
    
    return YES;
}



#pragma mark ----------------------------------------------------------------------------------------------
#pragma mark Callbacks for the load-remote-folder-contents
#pragma mark ----------------------------------------------------------------------------------------------

// ------------------------------------------------------------------------------------
// Metadata
// ------------------------------------------------------------------------------------

- (void)restClient:(DBRestClient *)restClient loadedMetadata:(DBMetadata *)metadata
{
    NSLog(@"Loaded Metadata: %@", metadata.path);
    
    if ([self.delegate respondsToSelector:@selector(syncDidStart)])
        [self.delegate syncDidStart];
    
    NSString *localPath = [NSString stringWithFormat:@"%@%@", [self localRootDirectory], metadata.path];
    NSString *remotePath = metadata.path;
    
    NSMutableDictionary *remoteFolders = [NSMutableDictionary dictionary];
    NSMutableDictionary *remoteFoldersRevs = [NSMutableDictionary dictionary];
    NSMutableDictionary *remoteFiles = [NSMutableDictionary dictionary];
    NSMutableDictionary *remoteFilesRevs = [NSMutableDictionary dictionary];
    NSMutableDictionary *remoteFilesThumbnails = [NSMutableDictionary dictionary];
        
    for (DBMetadata *item in metadata.contents){
        NSLog(@"Loaded Item: %@", item.path);
        if (item.isDirectory && !_syncFilesOnly){
            [remoteFolders setObject:item.lastModifiedDate forKey:item.path];
            [remoteFoldersRevs setObject:item.rev forKey:item.path];
        } else {
            if ([remotePath isEqualToString:@"/"] && _escapeRootFiles)
                continue;
                
            if (_syncImagesOnly){
                NSString *extension = [[item.path pathExtension] lowercaseString];
                if ([validExtensions indexOfObject:extension] != NSNotFound){
                    [remoteFiles setObject:item.lastModifiedDate forKey:item.path];
                    [remoteFilesRevs setObject:item.rev forKey:item.path];
                }
            } else {
                [remoteFiles setObject:item.lastModifiedDate forKey:item.path];
                [remoteFilesRevs setObject:item.rev forKey:item.path];
                [remoteFilesThumbnails setObject:[NSNumber numberWithBool:item.thumbnailExists] forKey:item.path];
            }
        }
    }
    
    NSLog(@"Loaded Files: %@", remoteFiles);
    
    BOOL hasFinished = [self syncForLocalPath:localPath andRemotePath:remotePath withRemoteFolders:remoteFolders andFoldersRevs:remoteFoldersRevs
                              plusRemoteFiles:remoteFiles remoteFilesRevs:remoteFilesRevs andRemoteFilesThumbnails:remoteFilesThumbnails];
    
    if (hasFinished)
        [self internalShutdownSuccess];
}

- (void)restClient:(DBRestClient*)client metadataUnchangedAtPath:(NSString*)path
{
    [self internalShutdownFailed];
}

- (void)restClient:(DBRestClient*)client loadMetadataFailedWithError:(NSError*)error
{
    NSLog(@"ERROR WITH METADATA: %@, %@", error, [error userInfo]);
    [self internalShutdownFailed];
}

// ------------------------------------------------------------------------------------
// Delta --- TO BE IMPLEMENTED
// ------------------------------------------------------------------------------------

- (void)restClient:(DBRestClient*)client loadedDeltaEntries:(NSArray *)entries reset:(BOOL)shouldReset cursor:(NSString *)cursor hasMore:(BOOL)hasMore
{
    if (shouldReset)
        [[NSUserDefaults standardUserDefaults] setObject:cursor forKey:syncCursor];
    
    BOOL hasFinished = 0;
    
    if (hasMore && hasFinished){
        // [self syncWithDelta:cursor];
    }
        
}

- (void)restClient:(DBRestClient*)client loadDeltaFailedWithError:(NSError *)error
{
    // TO BE IMPLEMENTED.
}



#pragma mark ----------------------------------------------------------------------------------------------
#pragma mark Methods to access from your app
#pragma mark ----------------------------------------------------------------------------------------------

- (void)initWithSync
{
    if (![[DBSession sharedSession] isLinked]) return; // Not linked, so nothing to do
    BOOL isFirstSync = [[NSUserDefaults standardUserDefaults] boolForKey:syncSetup];
    if (!isFirstSync) return;
    
    dispatch_async(dispatch_get_main_queue(), ^{
        [self syncStatusClear];
        [self syncStatusSetup];
        [self letTheHackingBegin];
    });
}

// IMPORTANT!! --------------------------------------------------------------------------------
// ------------ TEMP METHOD TO USE INSTEAD OF syncWithDelta. Would be more appropriate
// ------------ but some parts would need to be completely rewritten. I'll think about it.
// --------------------------------------------------------------------------------------------
- (void)syncWithMetadata
{
    [self letTheHackingBegin];
}

/*
// DO NOT USE THE FOLLOWING --- USE THE ONE ABOVE.
- (void)syncWithDelta:cursor
{
    if (![[DBSession sharedSession] isLinked]) return; // Not linked, so nothing to do
    BOOL isFirstSync = [[NSUserDefaults standardUserDefaults] boolForKey:syncSetup];
    if (isFirstSync) return;
    
    // NSString *cursor = [[NSUserDefaults standardUserDefaults] objectForKey:syncCursor];
 
    dispatch_async(dispatch_get_main_queue(), ^{
        [client loadDelta:cursor];
    });
}
 */

// Erases all local files and folders but not those on Dropbox.
- (void)unlinkDropboxAndPermanentlyEraseAllLocalFoldersAndFiles
{
    if (![[DBSession sharedSession] isLinked]) return;
    
    [self internalShutdownForced];
    [self syncStatusClear];
    [[DBSession sharedSession] unlinkAll];
    
    NSError *error = nil;
    NSArray *contentsOfPath = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:[self localRootDirectory] error:&error];
    
    dispatch_async(dispatch_get_main_queue(), ^{
        for (NSString *path in contentsOfPath){
            NSError *errorForRemove = nil;
            if (![[NSFileManager defaultManager] removeItemAtPath:path error:&errorForRemove])
                NSLog(@"ERROR unlinkDropboxAndPermanentlyEraseAllLocalFoldersAndFiles: %@, %@", error, [error userInfo]);
        }
    });
}

#pragma mark ----------------------------------------------------------------------------------------------
#pragma mark Misc
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

@end
