//
//  Deebee.h
//  v 0.1
//
//  Extended by Will Flagello, sublicensed with Evey License.
//  ----------------------------------------------------------------------------------------------------
//  Created by Chris Hulbert — github.com/chrishulbert — under the name CHBgDropboxSync, MIT License.
//
//  github.com/flvgello/deebee
//

#import <Foundation/Foundation.h>
#import <DropboxSDK/DropboxSDK.h>

@class Deebee;

@protocol DeebeeDelegate <NSObject>

@optional
- (void)syncDidStart;
- (void)syncDidEnd:(NSString *)syncResult;
- (void)uploadedFile:(DBMetadata *)fileMetadata atPath:(NSString *)path;
- (void)downloadedFile:(DBMetadata *)fileMetadata atPath:(NSString *)path isThumbnail:(BOOL)isThumbnail;
- (void)deletedFileAtPath:(NSString *)path wasRemote:(BOOL)wasRemote;

@end


@interface Deebee : NSObject <DBRestClientDelegate>

@property (strong, nonatomic) id <DeebeeDelegate> delegate;

@property (readwrite, strong, nonatomic) NSString           *localRootPath;
@property (readwrite, strong, nonatomic) NSString           *remoteRootPath;

@property (readwrite, assign, nonatomic) BOOL               syncFilesOnly;               // Sync All Files, No Folders
@property (readwrite, assign, nonatomic) BOOL               syncImagesOnly;              // Sync All Images, All Folders (First-Level Only)
@property (readwrite, assign, nonatomic) BOOL               syncThumbnailsOnly;          // Sync All Thumbnails, No Images
@property (readwrite, assign, nonatomic) BOOL               escapeRootFiles;             // Escape files in your app's root folder. (Dropbox & Local)
@property (readwrite, strong, nonatomic) NSString           *thumbnailsSize;             // WARNING: MUST follow Dropbox's naming conventions for thumbnails.

- (void)initWithSync;
- (void)syncWithMetadata; // Temp, read in .m
// - (void)syncWithDelta:(NSString *)cursor; // TO BE IMPLEMENTED
- (void)unlinkDropboxAndPermanentlyEraseAllLocalFoldersAndFiles;

@end
