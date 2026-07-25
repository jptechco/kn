//
//  KNFileInfo.h
//  Kinetic Notes
//
//  File metadata without the Carbon File Manager: timestamps, per-file attributes,
//  and bulk directory enumeration, all on top of getattrlist(2)/getattrlistbulk(2).
//
//  Kinetic Notes is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.

#ifndef KNFileInfo_h
#define KNFileInfo_h

#include <CoreFoundation/CoreFoundation.h>
#include <sys/types.h>
#include <time.h>

//Layout-identical stand-in for Carbon's UTCDateTime: 48-bit seconds since 1904-01-01 GMT
//split across two fields, plus a sub-second fraction. This is a persisted layout -- it is
//archived as a raw int64 and named in the type-encoded string "{UTCDateTime=SIS}" that the
//non-keyed unarchiver still reads -- so neither the field order nor the packing may change.
#pragma pack(push, 2)
typedef struct KNFileTime {
	uint16_t highSeconds;
	uint32_t lowSeconds;
	uint16_t fraction;
} KNFileTime;
#pragma pack(pop)

#define KNFileTimeIsEmpty(__T) (*(int64_t*)&((__T)) == 0LL)

//The two scalings below are deliberately different, because the Carbon File Manager's own two
//paths disagreed and both are baked into existing databases:
//  * dates read off the disk had their sub-second remainder scaled by 65535 (KNFileTimeFromTimespec),
//  * dates converted to and from CFAbsoluteTime scaled it by 65536 (UCConvert*DateTime).
//Measured against a real 286-file database, matching the first exactly is what keeps notes from
//all looking externally modified on the first launch after this change.
KNFileTime KNFileTimeFromTimespec(struct timespec ts);
KNFileTime KNFileTimeFromCFAbsoluteTime(CFAbsoluteTime absoluteTime);
CFAbsoluteTime KNCFAbsoluteTimeFromFileTime(KNFileTime fileTime);
struct timespec KNTimespecFromCFAbsoluteTime(CFAbsoluteTime absoluteTime);

//The subset of the old FSCatalogInfo that this program ever asked for.
typedef struct KNFileInfo {
	KNFileTime createDate;
	KNFileTime contentModDate;
	KNFileTime attributeModDate;
	uint64_t dataLogicalSize;
	uint64_t nodeID;
} KNFileInfo;

//Both return 0 on success or an errno value.
int KNGetFileInfoAtPath(const char *path, KNFileInfo *outInfo);
int KNSetFileDatesAtPath(const char *path, CFAbsoluteTime createdDate, CFAbsoluteTime modifiedDate);

typedef struct _NoteCatalogEntry {
	KNFileTime lastModified;
	KNFileTime lastAttrModified;
	uint32_t logicalSize;
	uint32_t fileType;
	uint32_t nodeID;
	unsigned int filenameCharCount;
	UniChar *filenameChars;
	CFMutableStringRef filename;
} NoteCatalogEntry;

//Enumerates dirPath, appending one entry per non-directory item. *entries is grown as needed and
//*entryCapacity updated to match; both may start as NULL/0 and are owned by the caller, which must
//keep them across calls so the per-entry filename buffers can be reused. Returns the number of
//entries filled in, or -1 on error (with errno set).
ssize_t KNScanDirectoryForCatalogEntries(const char *dirPath, NoteCatalogEntry **entries, size_t *entryCapacity);

#endif
