//
//  KNFileInfo.c
//  Kinetic Notes
//
//  Kinetic Notes is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.

#include "KNFileInfo.h"
#include "BufferUtils.h"

#include <sys/attr.h>
#include <sys/vnode.h>
#include <sys/errno.h>
#include <unistd.h>
#include <fcntl.h>
#include <string.h>
#include <stdlib.h>
#include <stddef.h>
#include <math.h>

//seconds between 1904-01-01 and 1970-01-01, and between 1904-01-01 and 2001-01-01
#define KN_SECONDS_1904_TO_1970 2082844800LL
#define KN_SECONDS_1904_TO_2001 3061152000LL

//the persisted layout, spelled out so that a stray alignment change cannot silently rewrite archives
_Static_assert(sizeof(KNFileTime) == 8, "KNFileTime must stay 8 bytes");
_Static_assert(offsetof(KNFileTime, highSeconds) == 0, "KNFileTime.highSeconds must stay at offset 0");
_Static_assert(offsetof(KNFileTime, lowSeconds) == 2, "KNFileTime.lowSeconds must stay at offset 2");
_Static_assert(offsetof(KNFileTime, fraction) == 6, "KNFileTime.fraction must stay at offset 6");

static KNFileTime KNMakeFileTime(int64_t seconds, uint16_t fraction) {
	KNFileTime t;
	t.highSeconds = (uint16_t)((seconds >> 32) & 0xFFFF);
	t.lowSeconds = (uint32_t)(seconds & 0xFFFFFFFF);
	t.fraction = fraction;
	return t;
}

static int64_t KNSecondsFromFileTime(KNFileTime t) {
	return ((int64_t)t.highSeconds << 32) | (int64_t)t.lowSeconds;
}

KNFileTime KNFileTimeFromTimespec(struct timespec ts) {
	//65535 rather than 65536 is not a typo; see the comment in KNFileInfo.h
	return KNMakeFileTime((int64_t)ts.tv_sec + KN_SECONDS_1904_TO_1970,
						  (uint16_t)(((int64_t)ts.tv_nsec * 65535) / 1000000000LL));
}

KNFileTime KNFileTimeFromCFAbsoluteTime(CFAbsoluteTime absoluteTime) {
	double total = absoluteTime + (double)KN_SECONDS_1904_TO_2001;
	double whole = floor(total);
	int64_t seconds = (int64_t)whole;
	uint32_t fraction = (uint32_t)((total - whole) * 65536.0 + 0.5);

	//Carbon truncated this overflow into 16 bits and so lost a whole second roughly once in
	//200,000 conversions; carrying is both cheaper to explain and correct.
	if (fraction > 0xFFFF) {
		fraction = 0;
		seconds++;
	}
	return KNMakeFileTime(seconds, (uint16_t)fraction);
}

CFAbsoluteTime KNCFAbsoluteTimeFromFileTime(KNFileTime fileTime) {
	return (CFAbsoluteTime)(KNSecondsFromFileTime(fileTime) - KN_SECONDS_1904_TO_2001) +
		   (double)fileTime.fraction / 65536.0;
}

struct timespec KNTimespecFromCFAbsoluteTime(CFAbsoluteTime absoluteTime) {
	double unixTime = absoluteTime + kCFAbsoluteTimeIntervalSince1970;
	double whole = floor(unixTime);
	struct timespec ts;

	ts.tv_sec = (time_t)whole;
	ts.tv_nsec = (long)((unixTime - whole) * 1.0e9);
	if (ts.tv_nsec > 999999999) ts.tv_nsec = 999999999;
	if (ts.tv_nsec < 0) ts.tv_nsec = 0;
	return ts;
}

//getattrlist(2) returns attributes packed in ascending order of their bits in <sys/attr.h>,
//with every common attribute preceding every file attribute -- not in the order they are
//requested. The structs below spell out that order for the attribute sets used here.

struct KNFileInfoAttrBuf {
	uint32_t length;
	struct timespec createTime;
	struct timespec modTime;
	struct timespec changeTime;
	uint64_t fileID;
	off_t dataLength;
} __attribute__((aligned(4), packed));

int KNGetFileInfoAtPath(const char *path, KNFileInfo *outInfo) {
	struct attrlist alist;
	struct KNFileInfoAttrBuf buf;

	if (!path || !outInfo) return EINVAL;

	memset(&alist, 0, sizeof(alist));
	alist.bitmapcount = ATTR_BIT_MAP_COUNT;
	alist.commonattr = ATTR_CMN_CRTIME | ATTR_CMN_MODTIME | ATTR_CMN_CHGTIME | ATTR_CMN_FILEID;
	alist.fileattr = ATTR_FILE_DATALENGTH;

	if (getattrlist(path, &alist, &buf, sizeof(buf), FSOPT_NOFOLLOW) != 0)
		return errno ? errno : EIO;

	outInfo->createDate = KNFileTimeFromTimespec(buf.createTime);
	outInfo->contentModDate = KNFileTimeFromTimespec(buf.modTime);
	outInfo->attributeModDate = KNFileTimeFromTimespec(buf.changeTime);
	outInfo->nodeID = buf.fileID;
	outInfo->dataLogicalSize = (uint64_t)buf.dataLength;

	return 0;
}

struct KNFileDatesAttrBuf {
	struct timespec createTime;
	struct timespec modTime;
} __attribute__((aligned(4), packed));

int KNSetFileDatesAtPath(const char *path, CFAbsoluteTime createdDate, CFAbsoluteTime modifiedDate) {
	struct attrlist alist;
	struct KNFileDatesAttrBuf buf;

	if (!path) return EINVAL;

	memset(&alist, 0, sizeof(alist));
	alist.bitmapcount = ATTR_BIT_MAP_COUNT;
	alist.commonattr = ATTR_CMN_CRTIME | ATTR_CMN_MODTIME;

	buf.createTime = KNTimespecFromCFAbsoluteTime(createdDate);
	buf.modTime = KNTimespecFromCFAbsoluteTime(modifiedDate);

	if (setattrlist(path, &alist, &buf, sizeof(buf), FSOPT_NOFOLLOW) != 0)
		return errno ? errno : EIO;

	return 0;
}

struct KNBulkAttrBuf {
	uint32_t length;
	attribute_set_t returned;
	attrreference_t name;
	fsobj_type_t objType;
	struct timespec modTime;
	struct timespec changeTime;
	char finderInfo[32];
	uint64_t fileID;
	off_t dataLength;
} __attribute__((aligned(4), packed));

//Reads one entry out of a getattrlistbulk() buffer. Returns the number of bytes the entry
//occupies, so the caller can step to the next one, and fills in *outEntry unless the item is a
//directory or the kernel reported an error for it, in which case *outSkip is set.
static uint32_t KNReadBulkEntry(const char *field, NoteCatalogEntry *outEntry, int *outSkip) {
	const char *cursor = field;
	uint32_t length = *(const uint32_t *)cursor;
	attribute_set_t returned;

	cursor += sizeof(uint32_t);
	returned = *(const attribute_set_t *)cursor;
	cursor += sizeof(attribute_set_t);

	*outSkip = 1;

	CFStringRef name = NULL;
	if (returned.commonattr & ATTR_CMN_NAME) {
		const attrreference_t *ref = (const attrreference_t *)cursor;
		name = CFStringCreateWithCString(kCFAllocatorDefault, ((const char *)ref) + ref->attr_dataoffset,
										 kCFStringEncodingUTF8);
		cursor += sizeof(attrreference_t);
	}
	if (returned.commonattr & ATTR_CMN_OBJTYPE) {
		if (*(const fsobj_type_t *)cursor == VDIR) {
			if (name) CFRelease(name);
			return length;
		}
		cursor += sizeof(fsobj_type_t);
	}
	if (returned.commonattr & ATTR_CMN_MODTIME) {
		outEntry->lastModified = KNFileTimeFromTimespec(*(const struct timespec *)cursor);
		cursor += sizeof(struct timespec);
	}
	if (returned.commonattr & ATTR_CMN_CHGTIME) {
		outEntry->lastAttrModified = KNFileTimeFromTimespec(*(const struct timespec *)cursor);
		cursor += sizeof(struct timespec);
	}
	if (returned.commonattr & ATTR_CMN_FNDRINFO) {
		//The first four bytes of a file's Finder info are its HFS type code, stored big-endian.
		//The Carbon File Manager swapped it into host order before handing it back in
		//FileInfo.fileType, and that is the order the allowed-type list is built in
		//(UTGetOSTypeFromString), so it has to be swapped here too.
		//A symlink has no Finder info, so this reports 0 where the File Manager synthesized 'slnk'.
		//Neither value appears in any allowed-type list, so both are rejected alike -- and a symlink
		//whose extension is allowed is accepted on the extension before the type is ever consulted.
		uint32_t fileType = 0;
		memcpy(&fileType, cursor, sizeof(fileType));
		outEntry->fileType = CFSwapInt32BigToHost(fileType);
		cursor += 32;
	}
	if (returned.commonattr & ATTR_CMN_FILEID) {
		//the inode, truncated to the width this field has always had on disk
		outEntry->nodeID = (uint32_t)(*(const uint64_t *)cursor & 0xFFFFFFFF);
		cursor += sizeof(uint64_t);
	}
	if (returned.commonattr & ATTR_CMN_ERROR) {
		if (*(const uint32_t *)cursor != 0) {
			if (name) CFRelease(name);
			return length;
		}
		cursor += sizeof(uint32_t);
	}
	if (returned.fileattr & ATTR_FILE_DATALENGTH) {
		outEntry->logicalSize = (uint32_t)(*(const off_t *)cursor & 0xFFFFFFFF);
		cursor += sizeof(off_t);
	}

	if (!name) return length;

	CFIndex nameLength = CFStringGetLength(name);
	if (nameLength > 255) nameLength = 255;

	ResizeArray(&(outEntry->filenameChars), (unsigned int)nameLength, &(outEntry->filenameCharCount));
	CFStringGetCharacters(name, CFRangeMake(0, nameLength), outEntry->filenameChars);
	CFRelease(name);

	if (!outEntry->filename) {
		outEntry->filename = CFStringCreateMutableWithExternalCharactersNoCopy(NULL, outEntry->filenameChars,
																			  nameLength, outEntry->filenameCharCount,
																			  kCFAllocatorNull);
	} else {
		CFStringSetExternalCharactersNoCopy(outEntry->filename, outEntry->filenameChars,
											nameLength, outEntry->filenameCharCount);
	}
	//normalize so that names with international characters are found regardless of the
	//decomposed form the filesystem hands back
	CFStringNormalize(outEntry->filename, kCFStringNormalizationFormC);

	*outSkip = 0;
	return length;
}

ssize_t KNScanDirectoryForCatalogEntries(const char *dirPath, NoteCatalogEntry **entries, size_t *entryCapacity) {
	if (!dirPath || !entries || !entryCapacity) {
		errno = EINVAL;
		return -1;
	}

	int fd = open(dirPath, O_RDONLY | O_DIRECTORY);
	if (fd < 0) return -1;

	struct attrlist alist;
	memset(&alist, 0, sizeof(alist));
	alist.bitmapcount = ATTR_BIT_MAP_COUNT;
	alist.commonattr = ATTR_CMN_RETURNED_ATTRS | ATTR_CMN_NAME | ATTR_CMN_OBJTYPE | ATTR_CMN_MODTIME |
					   ATTR_CMN_CHGTIME | ATTR_CMN_FNDRINFO | ATTR_CMN_FILEID | ATTR_CMN_ERROR;
	alist.fileattr = ATTR_FILE_DATALENGTH;

	//large enough that a directory of a few hundred notes is read in one or two calls
	char buffer[64 * 1024];
	size_t count = 0;
	int itemCount = 0;

	while ((itemCount = getattrlistbulk(fd, &alist, buffer, sizeof(buffer), 0)) > 0) {
		const char *field = buffer;

		for (int i = 0; i < itemCount; i++) {
			if (count >= *entryCapacity) {
				size_t oldCapacity = *entryCapacity;
				size_t newCapacity = oldCapacity ? oldCapacity * 2 : 64;
				NoteCatalogEntry *grown = (NoteCatalogEntry *)realloc(*entries, newCapacity * sizeof(NoteCatalogEntry));

				if (!grown) {
					close(fd);
					errno = ENOMEM;
					return -1;
				}
				//clear the new space so that filename and filenameChars start out NULL
				memset(grown + oldCapacity, 0, (newCapacity - oldCapacity) * sizeof(NoteCatalogEntry));
				*entries = grown;
				*entryCapacity = newCapacity;
			}

			int skip = 0;
			field += KNReadBulkEntry(field, (*entries) + count, &skip);
			if (!skip) count++;
		}
	}

	int scanError = (itemCount < 0) ? errno : 0;
	close(fd);

	if (scanError) {
		errno = scanError;
		return -1;
	}
	return (ssize_t)count;
}
