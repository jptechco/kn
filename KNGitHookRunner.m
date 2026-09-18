#import "KNGitHookRunner.h"

static int KNRunGit(NSString *directory, NSArray *arguments, NSString **capturedOutput) {
	NSTask *task = [[[NSTask alloc] init] autorelease];
	[task setLaunchPath:@"/usr/bin/git"];
	[task setCurrentDirectoryPath:directory];
	[task setArguments:arguments];

	NSMutableDictionary *environment = [NSMutableDictionary dictionaryWithDictionary:
		[[NSProcessInfo processInfo] environment]];
	[environment setObject:@"0" forKey:@"GIT_TERMINAL_PROMPT"];
	[environment setObject:@"C" forKey:@"LC_ALL"];
	[task setEnvironment:environment];

	NSPipe *outputPipe = nil;
	if (capturedOutput) {
		outputPipe = [NSPipe pipe];
		[task setStandardOutput:outputPipe];
		[task setStandardError:outputPipe];
	} else {
		NSFileHandle *nullHandle = [NSFileHandle fileHandleWithNullDevice];
		[task setStandardOutput:nullHandle];
		[task setStandardError:nullHandle];
	}

	@try {
		[task launch];
		NSData *outputData = capturedOutput ? [[outputPipe fileHandleForReading] readDataToEndOfFile] : nil;
		[task waitUntilExit];
		if (capturedOutput) {
			*capturedOutput = [[[NSString alloc] initWithData:outputData encoding:NSUTF8StringEncoding]
				autorelease];
		}
		return [task terminationStatus];
	} @catch (NSException *exception) {
		NSLog(@"Automatic Git hook could not launch git: %@", exception);
		return -1;
	}
}

static NSString *KNCanonicalPath(NSString *path) {
	return [[path stringByStandardizingPath] stringByResolvingSymlinksInPath];
}

@implementation KNGitHookRunner

+ (void)scheduleCommitAndPushForNotesDirectory:(NSString *)directory {
	if (![directory length]) return;

	static dispatch_queue_t gitQueue = NULL;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		gitQueue = dispatch_queue_create("org.kineticnotes.git-hooks", DISPATCH_QUEUE_SERIAL);
	});

	NSString *directoryCopy = [directory copy];
	dispatch_async(gitQueue, ^{
		NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
		NSString *repositoryRoot = nil;
		int status = KNRunGit(directoryCopy,
			[NSArray arrayWithObjects:@"rev-parse", @"--show-toplevel", nil], &repositoryRoot);
		repositoryRoot = [repositoryRoot stringByTrimmingCharactersInSet:
			[NSCharacterSet whitespaceAndNewlineCharacterSet]];

		//Do not touch a parent repository: enabling this setting authorizes Git operations only when
		//the selected notes folder is itself the repository root.
		if (status != 0 || ![KNCanonicalPath(repositoryRoot) isEqualToString:KNCanonicalPath(directoryCopy)]) {
			[pool drain];
			[directoryCopy release];
			return;
		}

		//Never fold a user's explicitly staged work into an automatic commit.
		status = KNRunGit(directoryCopy,
			[NSArray arrayWithObjects:@"diff", @"--cached", @"--quiet", nil], NULL);
		if (status == 1) {
			NSLog(@"Automatic Git hook skipped %@ because the repository already has staged changes",
				directoryCopy);
			[pool drain];
			[directoryCopy release];
			return;
		}
		if (status != 0) {
			NSLog(@"Automatic Git hook could not inspect the repository index in %@", directoryCopy);
			[pool drain];
			[directoryCopy release];
			return;
		}

		status = KNRunGit(directoryCopy,
			[NSArray arrayWithObjects:@"add", @"-A", @"--", @".", nil], NULL);
		if (status != 0) {
			NSLog(@"Automatic Git hook could not stage note changes in %@", directoryCopy);
			[pool drain];
			[directoryCopy release];
			return;
		}

		status = KNRunGit(directoryCopy,
			[NSArray arrayWithObjects:@"diff", @"--cached", @"--quiet", @"--", @".", nil], NULL);
		if (status == 0) {
			[pool drain];
			[directoryCopy release];
			return;
		}
		if (status != 1) {
			NSLog(@"Automatic Git hook could not inspect staged note changes in %@", directoryCopy);
			[pool drain];
			[directoryCopy release];
			return;
		}

		status = KNRunGit(directoryCopy,
			[NSArray arrayWithObjects:@"commit", @"-m", @"Update notes from Kinetic Notes", nil], NULL);
		if (status != 0) {
			NSLog(@"Automatic Git hook could not commit note changes in %@", directoryCopy);
			[pool drain];
			[directoryCopy release];
			return;
		}

		status = KNRunGit(directoryCopy, [NSArray arrayWithObject:@"push"], NULL);
		if (status != 0)
			NSLog(@"Automatic Git hook committed changes but could not push %@", directoryCopy);

		[pool drain];
		[directoryCopy release];
	});
}

@end
