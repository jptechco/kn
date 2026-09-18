#import <Foundation/Foundation.h>

@interface KNGitHookRunner : NSObject

+ (void)scheduleCommitAndPushForNotesDirectory:(NSString *)directory;

@end
