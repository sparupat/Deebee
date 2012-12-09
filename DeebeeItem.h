//
//  DeebeeItem.h
//  Forma
//
//  Created by Will Flagello on 12/5/12.
//  Copyright (c) 2012 Will Flagello. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <DropboxSDK/DropboxSDK.h>
#import "Deebee.h"

@interface DeebeeItem : NSObject <NSCoding>
{
    NSMutableString *name;
    NSDate *lastModified;
    NSMutableString *path;
    NSMutableString *localPath;
    NSMutableString *rev;
    BOOL isDirectory;

    // Folder
    NSMutableArray *contents;
    
    // File
    BOOL hasThumbnail;
    NSMutableString *extension;
}

@property (strong, nonatomic) NSString *ID;
// Since there's no way to create a unique id, we use the path.
// It lets us verify changes correctly even it's more like a workaround.

@property (readwrite, strong, nonatomic) NSMutableString *name;
@property (readwrite, strong, nonatomic) NSDate *lastModified;
@property (readwrite, strong, nonatomic) NSMutableString *path;             // Remote Path. It's great to idendify the important part of the local path.
@property (readwrite, strong, nonatomic) NSMutableString *localPath;        // Complete Local Path.
@property (readwrite, strong, nonatomic) NSMutableString *rev;
@property (readwrite, assign, nonatomic) BOOL isDirectory;

// Folder
@property (readwrite, strong, nonatomic) NSMutableArray *contents;

// File
@property (readwrite, assign, nonatomic) BOOL hasThumbnail;
@property (readwrite, strong, nonatomic) NSMutableString *extension;


- (id)initWithDictionary:(NSDictionary *)dictionary;
+ (DeebeeItem *)initFromMetadata:(DBMetadata *)metadata withLocalPath:(NSMutableString *)itemLocalPath;
+ (DeebeeItem *)initFromLocalItemAtPath:(NSString *)path withLastModifiedDate:(NSDate *)lastModified andLocalRootPath:(NSString *)localRootPath;

@end
