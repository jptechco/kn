
/*
 * Cryptography here is provided by CommonCrypto, which is part of libSystem --
 * no external library is needed to build or run this.  The AES-256-CBC output
 * is byte-identical to the OpenSSL EVP_aes_256_cbc() implementation this
 * originally used, so databases encrypted by older versions still open.
 */
/* NSData_crypto.h */

#import <Foundation/Foundation.h>
#include <CommonCrypto/CommonCryptor.h>
#include <CommonCrypto/CommonDigest.h>

@interface NSData (NVUtilities)

- (NSMutableData *) compressedData;
- (NSMutableData *) compressedDataAtLevel:(int)level;
- (NSMutableData *) uncompressedData;
- (BOOL) isCompressedFormat;

+ (NSMutableData *)randomDataOfLength:(int)len;
- (NSMutableData*)derivedKeyOfLength:(int)len salt:(NSData*)salt iterations:(int)count;
- (unsigned long)CRC32;
- (NSData*)SHA1Digest;
- (NSData*)BrokenMD5Digest;

- (NSString*)pathURLFromWebArchive;

//The notes directory is recorded as an NSURL bookmark. Databases pointed at before that recorded
//Alias Manager data instead, and Notational Velocity's own preferences will never record anything
//else, so -pathFromLegacyAliasData stays indefinitely -- it is the last Alias Manager call left.
+ (NSData*)bookmarkDataForPath:(NSString*)path;
- (NSString*)pathFromBookmarkDataIsStale:(BOOL*)outIsStale;
- (NSString*)pathFromLegacyAliasData;
- (NSMutableString*)newStringUsingBOMReturningEncoding:(NSStringEncoding*)encoding;
+ (NSData*)uncachedDataFromFile:(NSString*)filename;

- (NSString *)encodeBase64;
- (NSString *)encodeBase64WithNewlines:(BOOL)encodeWithNewlines;

@end

@interface NSMutableData (NVCryptoRelated)
- (void)reverseBytes;
- (void)alignForBlockSize:(int)alignedBlockSize;

- (BOOL)encryptAESDataWithKey:(NSData*)key iv:(NSData*)iv;
- (BOOL)decryptAESDataWithKey:(NSData*)key iv:(NSData*)iv;

- (BOOL)cryptAESDataWithKey:(NSData*)key iv:(NSData*)iv operation:(CCOperation)operation;

@end
