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
#include <sys/param.h>
#include <sys/stat.h>
#include <unistd.h>
#include <fcntl.h>
#include <stdio.h>
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

int KNReadDataAtPath(const char *path, size_t chunkSize, uint64_t *ioSize, void **outBuffer, int uncached) {
	if (!path || !ioSize || !outBuffer) return EINVAL;

	//A symlink's own data fork holds the path it points at, and that -- not the file at the other
	//end -- is what the File Manager's fork read returned. KNGetFileInfoAtPath describes the link
	//itself for the same reason, so reading through the link here would leave a note's contents and
	//its metadata describing two different files.
	struct stat linkInfo;
	if (lstat(path, &linkInfo) == 0 && S_ISLNK(linkInfo.st_mode)) {
		char *linkBuffer = (char *)valloc((size_t)linkInfo.st_size + 1);
		if (!linkBuffer) return ENOMEM;

		ssize_t linkLength = readlink(path, linkBuffer, (size_t)linkInfo.st_size + 1);
		if (linkLength < 0) {
			int linkError = errno ? errno : EIO;
			free(linkBuffer);
			return linkError;
		}

		*outBuffer = linkBuffer;
		*ioSize = (uint64_t)linkLength;
		return 0;
	}

	int fd = open(path, O_RDONLY);
	if (fd < 0) return errno ? errno : EIO;

	//the fork read this replaces took noCacheMask for data it did not expect to want again
	if (uncached) (void)fcntl(fd, F_NOCACHE, 1);

	off_t size = (off_t)*ioSize;
	if (size < 1) {
		struct stat sb;
		if (fstat(fd, &sb) != 0) {
			int statError = errno ? errno : EIO;
			close(fd);
			return statError;
		}
		size = sb.st_size;
	}

	//page-aligned, as the fork read was, and freed by the caller with free()
	char *buffer = (char *)valloc(size > 0 ? (size_t)size : 1);
	if (!buffer) {
		close(fd);
		return ENOMEM;
	}

	const size_t chunk = chunkSize ? chunkSize : (16 * 1024);
	off_t total = 0;
	int readError = 0;

	while (total < size) {
		ssize_t got = read(fd, buffer + total, (size_t)MIN((off_t)chunk, size - total));
		if (got < 0) {
			if (EINTR == errno) continue;
			readError = errno ? errno : EIO;
			break;
		}
		//end of file before the expected size: report what was there, which is what eofErr meant
		if (got == 0) break;
		total += got;
	}
	close(fd);

	if (readError) {
		free(buffer);
		return readError;
	}

	*outBuffer = buffer;
	*ioSize = (uint64_t)total;
	return 0;
}

int KNWriteDataToDescriptor(int fd, size_t chunkSize, uint64_t size, const void *buffer) {
	if (fd < 0 || (size && !buffer)) return EINVAL;

	const size_t chunk = chunkSize ? chunkSize : (16 * 1024);
	uint64_t total = 0;

	while (total < size) {
		ssize_t put = write(fd, (const char *)buffer + total, (size_t)MIN((uint64_t)chunk, size - total));
		if (put < 0) {
			if (EINTR == errno) continue;
			return errno ? errno : EIO;
		}
		total += put;
	}

	if (ftruncate(fd, (off_t)size) != 0) return errno ? errno : EIO;

	return 0;
}

int KNWriteDataAtPath(const char *path, size_t chunkSize, uint64_t size, const void *buffer) {
	if (!path) return EINVAL;

	int fd = open(path, O_WRONLY | O_CREAT, 0644);
	if (fd < 0) return errno ? errno : EIO;

	int writeError = KNWriteDataToDescriptor(fd, chunkSize, size, buffer);
	if (close(fd) != 0 && !writeError) writeError = errno ? errno : EIO;

	return writeError;
}

int KNCreateFileIfNotPresentAtPath(const char *path, int *outCreated) {
	if (!path) return EINVAL;

	if (outCreated) *outCreated = 0;

	int fd = open(path, O_WRONLY | O_CREAT | O_EXCL, 0644);
	if (fd >= 0) {
		if (outCreated) *outCreated = 1;
		close(fd);
		return 0;
	}
	if (EEXIST == errno) return 0;

	return errno ? errno : EIO;
}

int KNReplaceItemAtPath(const char *tempPath, const char *destPath) {
	if (!tempPath || !destPath) return EINVAL;

	//The exchange this replaces swapped two files' contents and left both catalog entries alone, so
	//the destination's permissions and creation date survived a save. A rename cannot do that -- the
	//destination becomes the file that was just written -- so carry those two across first and let
	//the rename be the single atomic step. renameatx_np(RENAME_SWAP) would not help: it swaps the
	//directory entries, so the destination's inode changes exactly as it does here, and it leaves the
	//old file behind under the temporary name for someone to delete.
	struct stat destInfo;
	if (lstat(destPath, &destInfo) == 0) {
		(void)chmod(tempPath, destInfo.st_mode & 07777);

		struct attrlist alist;
		struct timespec createTime = destInfo.st_birthtimespec;

		memset(&alist, 0, sizeof(alist));
		alist.bitmapcount = ATTR_BIT_MAP_COUNT;
		alist.commonattr = ATTR_CMN_CRTIME;
		(void)setattrlist(tempPath, &alist, &createTime, sizeof(createTime), FSOPT_NOFOLLOW);
	}

	//rename(2) replaces the destination and unlinks what was there in one step, so a save that
	//finishes never leaves a scratch file behind -- only one interrupted before this point can
	if (rename(tempPath, destPath) != 0) return errno ? errno : EIO;

	return 0;
}

OSStatus KNOSStatusFromErrno(int posixError) {
	switch (posixError) {
		case 0:				return noErr;
		case ENOENT:
		case ENOTDIR:		return fnfErr;
		case EEXIST:		return dupFNErr;
		case ENOSPC:
		case EDQUOT:		return dskFulErr;
		case EACCES:
		case EPERM:			return afpAccessDenied;
		case EROFS:			return wrPermErr;
		case EBUSY:
		case ETXTBSY:		return fBsyErr;
		case ENAMETOOLONG:	return bdNamErr;
		case EINVAL:		return paramErr;
		case ENOMEM:		return memFullErr;
		default:			return ioErr;
	}
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
		const char *nameBytes = ((const char *)ref) + ref->attr_dataoffset;

		name = CFStringCreateWithCString(kCFAllocatorDefault, nameBytes, kCFStringEncodingUTF8);
		if (!name) {
			//The name the File Manager reported came back as UniChars and so could never fail to
			//decode. Falling back to a single-byte encoding keeps that guarantee: an entry with no
			//name is dropped from the catalog, and a note missing from the catalog reads as deleted.
			name = CFStringCreateWithCString(kCFAllocatorDefault, nameBytes, kCFStringEncodingMacRoman);
		}
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
