Deebee (ß)
============
Deebee is a wrapper for Dropbox iOS SDK 1.3. It aims to emulate Dropbox's desktop client's behaviour and to add more filters to help developers achieve their apps' goals. As of this beta, Deebee was entirely developed by me, and I'm a designer and have known Objective-C for two months, so please, make pull requests if you believe there's something wrong. I'm eager to learn more, and I'd really appreciate your help.  
  
I built Deebee because I needed it for some apps I conceived and designed. It's licensed with Evey License, which you can find here, on my GitHub.
It's important that you consider it as a beta, and hence as a work in progress. I'm constantly refining and improving it, but I haven't yet tested every functionality. Hence, no guarantees regarding the actual version, but every guarantee about my willingness to constantly improve it.

Have fun,  
Will. 

Features
============
+ Sync an entire Dropbox folder to a local folder. Both chosen by you.
+ Automatically performs folders creation, downloads, uploads, local and remote moves and deletions.
+ Has delegate! Therefore you'll have progress, loadMetadata start, sync start, sync change and sync completion. I've also temporarily overwritten Dropbox SDK's delegates for the basic operations like download, upload and delete.
+ Uses NSUserDefaults to cache loadMetadata and to perform checks to avoid conflicts and to create a delta.
+ Automatically creates a delta with cached data. No need to use Dropbox SDK's loadDelta.
+ Filter: escape root files both in Dropbox and local.
+ Filter: sync first level folders only, like iCloud's file system.
+ Filter: sync files only. At the moments syncs only files in the root.
+ Filter: sync images only. It will go through all folders and sync images only. The extensions supported are jpeg, jpg, png but you can obviously add whatever you want to.
+ Filter: sync thumbnails only. Whether you sync files only or images only, or everything, you can sync thumbnails only to speed up your app's responsiveness. You can later download the original image because we cache its original path, so it's perfect for apps that need to load a lot of images.
+ Filter: only sync a set of file extensions.
+ Filter: thumbnailSize corresponds to Dropbox SDK's thumbnailSize value. So be sure the value is one of those accepted by Dropbox.
+ (Not so) Magically creates an object of a file stored locally to match the one stored on Dropbox. The class is DeebeeItem. You can use it to load data into your app without touching NSFileManager for even a second.
+ Provides a method to unlink Dropbox and consequently erase every local item.
+ ARC.  

To Do
============
+ Implement a better way to handle sync errors. At the moment, if any error, sync never ends.
+ Better progress. At the moment you'll get a partial progress since Deebee returns the progress for folder that was loaded through loadMetadata.
+ IF lastAbstractLocalItems has items, AND currentAbstractLocalItems has no item?
+ IF lastAbstractLocalItems has items, AND currentAbstractLocalItems has no item OR Dropbox has no item?

The End
============
Special thanks to Chris Hulbert, who helped me to get started with [his CHBgDropboxSync](https://github.com/chrishulbert/CHBgDropboxSync).
