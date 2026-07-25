/*Copyright (c) 2010, Zachary Schneirov. All rights reserved.
    This file is part of Notational Velocity.

    Notational Velocity is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    Notational Velocity is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with Notational Velocity.  If not, see <http://www.gnu.org/licenses/>. */


#import "URLGetter.h"
#import "KNAlert.h"

@implementation URLGetter

- (id)initWithURL:(NSURL*)aUrl delegate:(id)aDelegate userData:(id)someObj {
	if (!aUrl || [aUrl isFileURL]) {
		return nil;
	}
	if ([super init]) {
		maxExpectedByteCount = 0;
		isImporting = isIndicating = NO;
		delegate = aDelegate;
		url = [aUrl retain];
		userData = [someObj retain];
		
		//NSURLDownload delivered its callbacks on the run loop that started it; asking for the main
		//queue here keeps that guarantee, so the progress window and the import delegate are still
		//only ever touched from the main thread
		session = [[NSURLSession sessionWithConfiguration:[NSURLSessionConfiguration defaultSessionConfiguration]
												 delegate:self delegateQueue:[NSOperationQueue mainQueue]] retain];
		downloadTask = [[session downloadTaskWithRequest:[NSURLRequest requestWithURL:url]] retain];
		[downloadTask resume];

		[self startProgressIndication:self];
	}

	return self;
}

- (void)dealloc {
	[session release];
	[downloadTask release];
	[downloadPath release];
	[tempDirectory release];
	[url release];
	[userData release];

	[super dealloc];
}

- (NSURL*)url {
	return url;
}

- (id)userData {
	return userData;
}

- (IBAction)cancelDownload:(id)sender {
	[downloadTask cancel];

	//end straight away rather than waiting for the cancellation to come back through the session, so
	//the progress window closes on the click; -endDownloadWithPath: ignores the later callback
	[self endDownloadWithPath:nil];
}

- (void)stopProgressIndication {
	[window close];
	[progress stopAnimation:nil];
	
	isImporting = isIndicating = NO;
}

- (void)startProgressIndication:(id)sender {
	if (!window) {
		if (![NSBundle loadNibNamed:@"URLGetter" owner:self])  {
			NSLog(@"Failed to load URLGetter.nib");
			NSBeep();
			return;
		}
		[progress setUsesThreadedAnimation:YES];
	}
	
	[progress setIndeterminate:YES];
	[progress startAnimation:nil];
	
	[cancelButton setEnabled:YES];
	[progressStatus setStringValue:NSLocalizedString(@"Download: waiting to begin.", @"download dialog status message")];
	[objectURLStatus setStringValue:[url absoluteString]];
	
	[window center];
	[window makeKeyAndOrderFront:sender];
	
	isIndicating = YES;
}

- (void)updateProgress {
	if (isIndicating) {
		[progress setIndeterminate:!maxExpectedByteCount || isImporting];
		[progress setMaxValue:(double)maxExpectedByteCount];
		
		[progress setDoubleValue:(double)totalReceivedByteCount];
		if (isImporting) {
			[progressStatus setStringValue:NSLocalizedString(@"Importing content...", @"Status message after downloading a URL")];
		} else if (maxExpectedByteCount > 0) {
			[progressStatus setStringValue:[NSString stringWithFormat:NSLocalizedString(@"%.0lf KB of %.0lf KB", nil), 
				(double)totalReceivedByteCount / 1024.0, (double)maxExpectedByteCount / 1024.0]];
		} else {
			[progressStatus setStringValue:[NSString stringWithFormat:NSLocalizedString(@"%.0lf KB received",nil), (double)totalReceivedByteCount / 1024.0]];
		}
	}
}

- (void)URLSession:(NSURLSession *)aSession downloadTask:(NSURLSessionDownloadTask *)aTask
	  didWriteData:(int64_t)bytesWritten totalBytesWritten:(int64_t)totalBytesWritten
totalBytesExpectedToWrite:(int64_t)totalBytesExpectedToWrite {

	//a server that sends no Content-Length reports NSURLSessionTransferSizeUnknown (-1); zero is what
	//-updateProgress reads as "no total known", which makes the bar indeterminate
	maxExpectedByteCount = totalBytesExpectedToWrite == NSURLSessionTransferSizeUnknown ? 0 : totalBytesExpectedToWrite;
	totalReceivedByteCount = totalBytesWritten;

	[self updateProgress];
}

- (void)URLSession:(NSURLSession *)aSession downloadTask:(NSURLSessionDownloadTask *)aTask
didFinishDownloadingToURL:(NSURL *)location {

	//NSURLSession deletes `location` as soon as this method returns, so the file has to be moved
	//here and now -- this is the one delegate callback that cannot be deferred
	NSString *name = [[aTask response] suggestedFilename];
	if (![name length]) name = [[[aTask originalRequest] URL] lastPathComponent];
	if (![name length]) name = @"download";

	[tempDirectory autorelease];
	tempDirectory = [[NSTemporaryDirectory() stringByAppendingPathComponent:[[NSProcessInfo processInfo] globallyUniqueString]] retain];

	NSFileManager *fileMan = [NSFileManager defaultManager];
	if (![fileMan createDirectoryAtPath:tempDirectory withIntermediateDirectories:YES attributes:nil error:NULL]) {
		NSLog(@"URLGetter: Couldn't create temporary directory!");
		[tempDirectory release];
		tempDirectory = nil;
		return;
	}

	[downloadPath autorelease];
	downloadPath = [[tempDirectory stringByAppendingPathComponent:name] retain];

	NSError *moveError = nil;
	if (![fileMan moveItemAtPath:[location path] toPath:downloadPath error:&moveError]) {
		NSLog(@"URLGetter: couldn't move the downloaded file into place: %@", moveError);
		[downloadPath release];
		downloadPath = nil;
	}
}

- (void)URLSession:(NSURLSession *)aSession task:(NSURLSessionTask *)aTask didCompleteWithError:(NSError *)error {

	//the sole completion funnel: it runs for success, for failure, and for the cancellation that
	//-cancelDownload: kicked off (which has already finished up, hence the didEndDownload guard)
	if (didEndDownload) return;

	if (error) {
		NSString *reason = [error localizedDescription];
		if (!reason) reason = NSLocalizedString(@"unknown error.", @"error description of last resort for why a URL couldn't be accessed");
		KNRunAlert([NSString stringWithFormat:NSLocalizedString(@"The URL quotemark%@quotemark could not be accessed: %@.", nil),
			[url absoluteString], reason], @"", NSLocalizedString(@"OK",nil), nil, nil);

		[self endDownloadWithPath:nil];
	} else {
		//nil when -URLSession:downloadTask:didFinishDownloadingToURL: could not keep the file
		[self endDownloadWithPath:downloadPath];
	}
}

- (void)endDownloadWithPath:(NSString*)path {
	if (didEndDownload) return;
	didEndDownload = YES;

	isImporting = YES;
	[self updateProgress];

	[self retain];
	[delegate URLGetter:self returnedDownloadedFile:path];

	//clean up after ourselves
	NSFileManager *fileMan = [NSFileManager defaultManager];
	if (downloadPath) {
		[fileMan removeItemAtPath:downloadPath error:NULL];
		[downloadPath release];
		downloadPath = nil;
	}

	if (tempDirectory) {
		//only remove temporary directory if there's nothing in it
		if (![[fileMan contentsOfDirectoryAtPath:tempDirectory error:NULL] count])
			[fileMan removeItemAtPath:tempDirectory error:NULL];
		else
			NSLog(@"note removing %@ because it still contains files!", tempDirectory);
		[tempDirectory release];
		tempDirectory = nil;
	}

	[self stopProgressIndication];

	//the session holds a strong reference to its delegate -- that is us -- until it is invalidated,
	//so without this the URLGetter would never be deallocated
	[session invalidateAndCancel];

	[self release];
}

- (NSString*)downloadPath {
	return downloadPath;
}

- (id)delegate {
	return delegate;
}
- (void)setDelegate:(id)aDelegate {
	delegate = aDelegate;
}

@end
