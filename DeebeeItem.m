//
//  DeebeeItem.m
//  Forma
//
//  Created by Will Flagello on 12/5/12.
//  Copyright (c) 2012 Will Flagello. All rights reserved.
//

#import "DeebeeItem.h"

@implementation DeebeeItem

+ (NSDateFormatter *)dateFormatter
{
    NSMutableDictionary *dictionary = [[NSThread currentThread] threadDictionary];
    static NSString *dateFormatterKey = @"DeebeeFolderDateFormatter";
    
    NSDateFormatter *dateFormatter = [dictionary objectForKey:dateFormatterKey];
    if (dateFormatter == nil){
        dateFormatter = [NSDateFormatter new];
        dateFormatter.locale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"];
        dateFormatter.dateFormat = @"EEE, dd MMM yyyy HH:mm:ss Z";
        [dictionary setObject:dateFormatter forKey:dateFormatterKey];
    }
    
    return dateFormatter;
}
 
- (id)initWithDictionary:(NSDictionary *)dictionary
{
    if ((self = [super init])){
        if ([dictionary objectForKey:@"modified"])
            lastModified = [[DeebeeItem dateFormatter] dateFromString:[dictionary objectForKey:@"modified"]];
        
        ID = [dictionary objectForKey:@"ID"];

        path = [dictionary objectForKey:@"path"];
        localPath = [dictionary objectForKey:@"localPath"];
        rev = [dictionary objectForKey:@"rev"];
        
        extension = [dictionary objectForKey:@"extension"];
        hasThumbnail = [[dictionary objectForKey:@"hasThumbnail"] boolValue];
        isDirectory = [[dictionary objectForKey:@"isDirectory"] boolValue];

        if ([dictionary objectForKey:@"contents"]){
            NSArray *contentsOfFolder = [dictionary objectForKey:@"contents"];
            NSMutableArray *mutableFiles = [[NSMutableArray alloc] initWithCapacity:[contentsOfFolder count]];
            for (NSDictionary *item in contentsOfFolder){
                DeebeeItem *content = [[DeebeeItem alloc] initWithDictionary:item];
                [mutableFiles addObject:content];
            }
            contentsOfFolder = mutableFiles;
        }
    }
    return self;
}

- (BOOL)isEqual:(id)object
{
    if (object == self) return YES;
    if (![object isKindOfClass:[DeebeeItem class]]) return NO;
    
    DeebeeItem *other = (DeebeeItem *)object;
    return [self.ID isEqualToString:other.ID];
}

- (NSMutableString *)name
{
    if (name == nil)
        name = [NSMutableString stringWithString:[path lastPathComponent]];
    
    return name;
}

- (NSMutableString *)extension
{
    if (extension == nil && contents == nil)
        extension = [NSMutableString stringWithString:[path pathExtension]];
    
    return extension;
}

+ (DeebeeItem *)initFromMetadata:(DBMetadata *)metadata withLocalPath:(NSMutableString *)itemLocalPath
{
    DeebeeItem *item = [[DeebeeItem alloc] init];
    item.ID = metadata.path;
    item.path = [NSMutableString stringWithString:metadata.path];
    item.rev = [NSMutableString stringWithString:metadata.rev];
    item.name = [NSMutableString stringWithString:metadata.filename]; // Check if it has extension or not
    item.localPath = itemLocalPath;
    item.lastModified = metadata.lastModifiedDate;
    item.hasThumbnail = metadata.thumbnailExists;
    item.isDirectory = metadata.isDirectory;

    if (metadata.isDirectory){
        item.contents = [NSMutableArray arrayWithArray:metadata.contents];
        item.extension = nil;
    } else {
        item.contents = nil;
        item.extension = [NSMutableString stringWithString:[[metadata.path pathExtension] lowercaseString]];
    }
    
    return item;
}

+ (DeebeeItem *)initFromLocalItemAtPath:(NSString *)path withLastModifiedDate:(NSDate *)lastModified andLocalRootPath:(NSString *)localRootPath
{
    DeebeeItem *item = [[DeebeeItem alloc] init];
    item.ID = path;
    item.lastModified = lastModified;
    item.name = [NSMutableString stringWithString:[path lastPathComponent]];
    item.path = [NSMutableString stringWithString:[path stringByReplacingOccurrencesOfString:localRootPath withString:@""]];
    item.localPath = [NSMutableString stringWithString:path];
    item.rev = nil;
    
    NSDictionary *attribs = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:nil];
    BOOL isPathDirectory = [attribs.fileType isEqual:NSFileTypeDirectory];
    BOOL isPathFile = [attribs.fileType isEqual:NSFileTypeRegular];
    
    item.isDirectory = isPathDirectory;
    if (isPathDirectory) item.extension = nil;
    if (isPathFile) item.extension = [NSMutableString stringWithString:[[path pathExtension] lowercaseString]];
    
    if (item.extension){
        item.contents = nil;
        NSArray *validImageExtensions = [NSArray arrayWithObjects:@"jpg", @"jpeg", @"png", nil];
        if ([validImageExtensions indexOfObject:item.extension] != NSNotFound){
            item.hasThumbnail = YES;
        } else {
            item.hasThumbnail = NO;
        }
    }
    
    return item;
}

@synthesize name;
@synthesize path;
@synthesize localPath;
@synthesize ID;
@synthesize contents;
@synthesize rev;
@synthesize isDirectory;
@synthesize extension;
@synthesize lastModified;
@synthesize hasThumbnail;

#pragma mark -------------------------------------------------------------------------------
#pragma mark NSCoding Methods
#pragma mark -------------------------------------------------------------------------------

- (id)initWithCoder:(NSCoder *)coder
{
    if ((self = [super init])){
        lastModified = [coder decodeObjectForKey:@"lastModified"];
        path = [coder decodeObjectForKey:@"path"];
        localPath = [coder decodeObjectForKey:@"localPath"];
        contents = [coder decodeObjectForKey:@"contents"];
        ID = [coder decodeObjectForKey:@"ID"];
        extension = [coder decodeObjectForKey:@"extension"];
        rev = [coder decodeObjectForKey:@"rev"];
        hasThumbnail = [coder decodeBoolForKey:@"hasThumbnail"];
        isDirectory = [coder decodeBoolForKey:@"isDirectory"];
    }
    return self;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
    [coder encodeObject:lastModified forKey:@"lastModified"];
    [coder encodeObject:path forKey:@"path"];
    [coder encodeObject:localPath forKey:@"localPath"];
    [coder encodeObject:contents forKey:@"contents"];
    [coder encodeObject:ID forKey:@"ID"];
    [coder encodeObject:extension forKey:@"extension"];
    [coder encodeObject:rev forKey:@"rev"];
    [coder encodeBool:hasThumbnail forKey:@"hasThumbnail"];
    [coder encodeBool:isDirectory forKey:@"isDirectory"];
}

@end
