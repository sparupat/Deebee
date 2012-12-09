//
//  Deebee.h
//  v 1.0
//
//  Created by Will Flagello, licensed with Evey License.
//  ----------------------------------------------------------------------------------------------------
//  Special thanks to Chris Hulbert and his CHBgDropboxSync.
//
//  github.com/flvgello/deebee
//

#import <Foundation/Foundation.h>
#import <DropboxSDK/DropboxSDK.h>
#import "DeebeeItem.h"

@class DeebeeItem;
@protocol DeebeeDelegate;

@interface Deebee : NSObject <DBRestClientDelegate>

@property (assign, nonatomic) id <DeebeeDelegate> delegate;

@property (readwrite, strong, nonatomic) NSString           *localRootPath;
@property (readwrite, strong, nonatomic) NSString           *remoteRootPath;
@property (readwrite, assign, nonatomic) BOOL               escapeRootFiles;             // Escape files in your app's root folder. (Dropbox & Local)
@property (readwrite, assign, nonatomic) BOOL               syncFirstLevelOnly;          // Sync Root + First Level Folders Only.
@property (readwrite, assign, nonatomic) BOOL               syncFilesOnly;               // Sync All Files, No Folders
@property (readwrite, assign, nonatomic) BOOL               syncImagesOnly;              // Sync All Images, All Folders (First-Level Only)
@property (readwrite, assign, nonatomic) BOOL               syncThumbnailsOnly;          // Sync All Thumbnails, No Images
@property (readwrite, assign, nonatomic) NSArray            *syncableFileExtensions;     // Syncs Only the files with the extensions in this array.
@property (readwrite, strong, nonatomic) NSString           *thumbnailsSize;             // WARNING: MUST follow Dropbox's naming conventions for thumbnails.

- (void)initWithSync;
- (void)performSync;
- (void)performLoadMetadata;
- (void)unlinkDropboxAndEraseAllLocalData;

@end


@protocol DeebeeDelegate <NSObject>

- (void)didStartLoadingMetadata;
- (void)didLoadMetadataWithItemsToSync:(int)remainingItems;
- (void)didLoadMetadataFailWithError:(NSError *)error;
- (void)didStartSyncing;
- (void)didChangeSyncingWithItemsToSync:(int)remainingItems;
- (void)didEndSyncingWithResult:(NSString *)result andError:(NSError *)error;

@optional
- (void)didUploadItem:(DeebeeItem *)item;
- (void)didDownloadItem:(DeebeeItem *)item;
- (void)itemDownloadFailedWithError:(NSError *)error;
- (void)itemUploadFailedWithError:(NSError *)error;
- (void)remoteItemDeleteFailedWithError:(NSError *)error;
- (void)localItemDeleteFailedWithError:(NSError *)error;

@end
