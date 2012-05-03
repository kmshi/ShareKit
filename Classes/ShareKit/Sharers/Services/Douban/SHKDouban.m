//
//  SHKDouban.m
//  ShareKit
//
//  Created by icyleaf on 12-03-16.
//  Copyright 2012 icyleaf.com. All rights reserved.

//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//  THE SOFTWARE.
//
//


#import "SHKDouban.h"
#import "SHKConfiguration.h"
#import "JSONKit.h"
#import "SHKXMLResponseParser.h"
#import "NSMutableDictionary+NSNullsToEmptyStrings.h"

static NSString *const kSHKDoubanUserInfo = @"kSHKDoubanUserInfo";

@interface SHKDouban ()

#pragma mark -
#pragma mark UI Implementation

- (void)showDoubanForm;

#pragma mark -
#pragma mark Share API Methods

- (void)sendStatus;
- (void)sendStatusTicket:(OAServiceTicket *)ticket didFinishWithData:(NSData *)data;
- (void)sendStatusTicket:(OAServiceTicket *)ticket didFailWithError:(NSError*)error;

- (void)sendUserInfo;
- (void)sendUserInfoTicket:(OAServiceTicket *)ticket didFinishWithData:(NSData *)data;
- (void)sendUserInfoTicket:(OAServiceTicket *)ticket didFailWithError:(NSError*)error;

- (void)shortenURL;
- (void)shortenURLFinished:(SHKRequest *)aRequest;
- (void)handleUnsuccessfulTicket:(NSData *)data;

@end

@implementation SHKDouban

- (id)init
{
	if (self = [super init])
	{	
		// OAUTH				
		self.consumerKey = SHKCONFIG(doubanConsumerKey);		
		self.secretKey = SHKCONFIG(doubanConsumerSecret);
 		self.authorizeCallbackURL = [NSURL URLWithString:SHKCONFIG(doubanCallbackUrl)];

        // -- //
        
		// You do not need to edit these, they are the same for everyone
	    self.authorizeURL = [NSURL URLWithString:@"http://www.douban.com/service/auth/authorize"];
	    self.requestURL = [NSURL URLWithString:@"http://www.douban.com/service/auth/request_token"];
	    self.accessURL = [NSURL URLWithString:@"http://www.douban.com/service/auth/access_token"]; 
	}	
	return self;
}


#pragma mark -
#pragma mark Configuration : Service Defination

+ (NSString *)sharerTitle
{
	return @"豆瓣";
}

+ (BOOL)canShareURL
{
	return YES;
}

+ (BOOL)canShareText
{
	return YES;
}

+ (BOOL)canGetUserInfo
{
	return YES;
}

#pragma mark -
#pragma mark Configuration : Dynamic Enable

- (BOOL)shouldAutoShare
{
	return NO;
}

#pragma mark -
#pragma mark Authorization

+ (void)logout 
{
	[[NSUserDefaults standardUserDefaults] removeObjectForKey:kSHKDoubanUserInfo];
	[super logout];    
}

#pragma mark -
#pragma mark UI Implementation

- (void)show
{
	if (item.shareType == SHKShareTypeURL)
	{
		[self shortenURL];
	}
	
	else if (item.shareType == SHKShareTypeImage)
	{
		[item setCustomValue:item.title forKey:@"status"];
		[self showDoubanForm];
	}
	
	else if (item.shareType == SHKShareTypeText)
	{
		[item setCustomValue:item.text forKey:@"status"];
		[self showDoubanForm];
	}
    
    else if (item.shareType == SHKShareTypeUserInfo)
	{
		[self setQuiet:YES];
		[self tryToSend];
	}
}

- (void)showDoubanForm
{
	SHKFormControllerLargeTextField *rootView = [[SHKFormControllerLargeTextField alloc] initWithNibName:nil bundle:nil delegate:self];	
    
    rootView.text = [item customValueForKey:@"status"];
	rootView.maxTextLength = 140;
	rootView.image = item.image;
	rootView.imageTextLength = 25;
	
	self.navigationBar.tintColor = SHKCONFIG_WITH_ARGUMENT(barTintForView:,self);
	
	[self pushViewController:rootView animated:NO];
	[rootView release];
	
	[[SHK currentHelper] showViewController:self];
}

- (void)sendForm:(SHKFormControllerLargeTextField *)form
{	
	[item setCustomValue:form.textView.text forKey:@"status"];
	[self tryToSend];
}

#pragma mark -

- (void)shortenURL
{
	if (![SHK connected]||[SHKCONFIG(sinaWeiboConsumerKey) isEqualToString:@""] || SHKCONFIG(sinaWeiboConsumerKey) == nil)
	{
		[item setCustomValue:[NSString stringWithFormat:@"%@ %@", item.title, [item.URL.absoluteString stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding]] forKey:@"status"];
		[self showDoubanForm];		
		return;
	}
    
	if (!quiet)
		[[SHKActivityIndicator currentIndicator] displayActivity:SHKLocalizedString(@"Shortening URL...")];
	
	self.request = [[[SHKRequest alloc] initWithURL:[NSURL URLWithString:[NSMutableString stringWithFormat:@"http://api.t.sina.com.cn/short_url/shorten.json?source=%@&url_long=%@",
																		  SHKCONFIG(sinaWeiboConsumerKey),						  
																		  SHKEncodeURL(item.URL)
																		  ]]
											 params:nil
										   delegate:self
								 isFinishedSelector:@selector(shortenURLFinished:)
											 method:@"GET"
										  autostart:YES] autorelease];
    
}

- (void)shortenURLFinished:(SHKRequest *)aRequest
{
	[[SHKActivityIndicator currentIndicator] hide];

    NSArray *result = [[aRequest getResult] objectFromJSONString];
    if ([result isKindOfClass:[NSArray class]] && result.count>0) {
        item.URL = [NSURL URLWithString:[[result objectAtIndex:0] objectForKey:@"url_short"]];
    }else {
        // TODO - better error message
        [[[[UIAlertView alloc] initWithTitle:SHKLocalizedString(@"Shorten URL Error")
                                     message:SHKLocalizedString(@"We could not shorten the URL.")
                                    delegate:nil
                           cancelButtonTitle:SHKLocalizedString(@"Continue")
                           otherButtonTitles:nil] autorelease] show];
    }
    
    [item setCustomValue:[NSString stringWithFormat:@"%@ %@", item.title, item.URL.absoluteString] 
                  forKey:@"status"];
    
	[self showDoubanForm];
}


#pragma mark -
#pragma mark Share API Methods

- (BOOL)validateItem
{
	if (self.item.shareType == SHKShareTypeUserInfo) {
		return YES;
	}
	
	NSString *status = [item customValueForKey:@"status"];
	return status != nil && status.length <= 140;
}


- (BOOL)send
{	
	if ( ! [self validateItem])
		return NO;
	
    switch (item.shareType) 
    {
		case SHKShareTypeUserInfo:            
			[self sendUserInfo];
			break;
			
		default:
			[self sendStatus];
			break;
	}
	
	// Notify delegate
	[self sendDidStart];	
	
	return YES;
}

- (void)sendStatus
{
	OAMutableURLRequest *oRequest = [[OAMutableURLRequest alloc] initWithURL:[NSURL URLWithString:@"http://api.douban.com/miniblog/saying"]
																	consumer:consumer
																	   token:accessToken
																	   realm:nil
														   signatureProvider:nil];
	
	[oRequest setHTTPMethod:@"POST"];
	[oRequest addValue:@"application/atom+xml" forHTTPHeaderField:@"Content-Type"];
    
	NSMutableString *body = [NSMutableString stringWithFormat:@"<?xml version='1.0' encoding='UTF-8'?>"];
    [body appendFormat:@"<entry xmlns:ns0=\"http://www.w3.org/2005/Atom\" xmlns:db=\"http://www.douban.com/xmlns/\">"];
    [body appendFormat:@"<content><![CDATA[%@]]></content>", [item customValueForKey:@"status"]];
    [body appendFormat:@"</entry>"];
    
    [oRequest setHTTPBody:[body dataUsingEncoding:NSUnicodeStringEncoding allowLossyConversion:YES]];
	
	OAAsynchronousDataFetcher *fetcher = [OAAsynchronousDataFetcher asynchronousFetcherWithRequest:oRequest
																						  delegate:self
																				 didFinishSelector:@selector(sendStatusTicket:didFinishWithData:)
																				   didFailSelector:@selector(sendStatusTicket:didFailWithError:)];	
	
	[fetcher start];
	[oRequest release];
}

- (void)sendStatusTicket:(OAServiceTicket *)ticket didFinishWithData:(NSData *)data 
{	
    if (ticket.didSucceed) 
		[self sendDidFinish];
	
	else
	{		
		[self handleUnsuccessfulTicket:data];
	}
}

- (void)sendStatusTicket:(OAServiceTicket *)ticket didFailWithError:(NSError*)error
{
	[self sendDidFailWithError:error];
}

- (void)sendUserInfo{
    NSString* user_id = [[NSUserDefaults standardUserDefaults] objectForKey:kSHKDoubanUserInfo];
    
    OAMutableURLRequest *oRequest = [[OAMutableURLRequest alloc] initWithURL:[NSURL URLWithString:[NSString stringWithFormat:@"http://api.douban.com/people/%@",user_id]]
																	consumer:consumer
																	   token:accessToken
																	   realm:nil
														   signatureProvider:nil];
	
	[oRequest setHTTPMethod:@"GET"];
	
	OAAsynchronousDataFetcher *fetcher = [OAAsynchronousDataFetcher asynchronousFetcherWithRequest:oRequest
																						  delegate:self
																				 didFinishSelector:@selector(sendUserInfoTicket:didFinishWithData:)
																				   didFailSelector:@selector(sendUserInfoTicket:didFailWithError:)];	
	
	[fetcher start];
	[oRequest release];
}

- (void)sendUserInfoTicket:(OAServiceTicket *)ticket didFinishWithData:(NSData *)data{
    if (ticket.didSucceed) {
        NSDictionary* account = [SHKXMLResponseParser objectFromXMLResponse:data];
        NSMutableDictionary * dict = [NSMutableDictionary dictionaryWithCapacity:4];
        [dict setValue:[account valueForKey:@"db:uid"] forKey:@"uid"];
        [dict setValue:[account valueForKey:@"title"] forKey:@"name"];
        //[dict setValue:[account valueForKey:@"uri"] forKey:@"email"];
        [dict setValue:[self sharerId] forKey:@"shareid"];
        [[NSNotificationCenter defaultCenter] postNotificationName:SHKGetUserInfoNotification object:self userInfo:dict];
		[self sendDidFinish];
	}
	else
	{		
		[self handleUnsuccessfulTicket:data];
	}
}

- (void)sendUserInfoTicket:(OAServiceTicket *)ticket didFailWithError:(NSError*)error{
    [self sendDidFailWithError:error];
}


#pragma mark - Overrewrite parent method
- (void)tokenAuthorize
{	
    NSString *urlString = [NSString stringWithFormat:@"%@?oauth_token=%@&p=1", authorizeURL.absoluteString, requestToken.key];
    
    if ( ! [[authorizeCallbackURL absoluteString] isEqualToString:@""]) {
        urlString = [NSString stringWithFormat:@"%@&oauth_callback=%@", 
                     urlString, 
                     [authorizeCallbackURL absoluteString]];
    }

	SHKOAuthView *auth = [[SHKOAuthView alloc] initWithURL:[NSURL URLWithString:urlString] delegate:self];
	[[SHK currentHelper] showViewController:auth];	
	[auth release];
}

- (void)tokenAccessTicket:(OAServiceTicket *)ticket didFinishWithData:(NSData *)data {
    NSString *responseBody = [[NSString alloc] initWithData:data
                                                   encoding:NSUTF8StringEncoding];
    NSArray* array = [responseBody componentsSeparatedByString:@"&"];
    for (NSString* str in array) {
        NSRange range = [str rangeOfString:@"douban_user_id="];
        if (range.location != NSNotFound) {
            [[NSUserDefaults standardUserDefaults] setObject:[str substringFromIndex:(range.location+range.length)] forKey:kSHKDoubanUserInfo];
            break;
        }
    }
    SHKLog(@"douban_user_id:%@",[[NSUserDefaults standardUserDefaults] objectForKey:kSHKDoubanUserInfo]);

    [super tokenAccessTicket:ticket didFinishWithData:data];
}

- (void)authDidFinish:(BOOL)success{
    [super authDidFinish:success];
    if (success) {
        SHKItem* myitem = [SHKItem text:@""];
        myitem.shareType = SHKShareTypeUserInfo;
        [[self class] shareItem:myitem];
    }
}

#pragma mark -

- (void)handleUnsuccessfulTicket:(NSData *)data
{
	if (SHKDebugShowLogs)
		SHKLog(@"Douban Send Status Error: %@", [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease]);
	
	// CREDIT: Oliver Drobnik
	
	NSString *string = [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease];		
	
	// in case our makeshift parsing does not yield an error message
	NSString *errorMessage = @"Unknown Error";		
	
	NSScanner *scanner = [NSScanner scannerWithString:string];
	
	// skip until error message
	[scanner scanUpToString:@"\"error\":\"" intoString:nil];
	
	
	if ([scanner scanString:@"\"error\":\"" intoString:nil])
	{
		// get the message until the closing double quotes
		[scanner scanUpToCharactersFromSet:[NSCharacterSet characterSetWithCharactersInString:@"\""] intoString:&errorMessage];
	}
	
	
	// this is the error message for revoked access ...?... || removed app from Twitter
    // TODO:Is it same with Douban?
	if ([errorMessage isEqualToString:@"Invalid / used nonce"] || [errorMessage isEqualToString:@"Could not authenticate with OAuth."]) {
		[[self class] logout];
		[self shouldReloginWithPendingAction:SHKPendingSend];
        return;
		
	} else {
		
		//when sharing image, and the user removed app permissions there is no JSON response expected above, but XML, which we need to parse. 401 is obsolete credentials -> need to relogin
		if ([string rangeOfString:@"Signature does not match"].location != NSNotFound) {
			[[self class] logout];
			[self shouldReloginWithPendingAction:SHKPendingSend];
			return;
		}
	}
	
	[self sendDidFailWithError:[SHK error:errorMessage,nil]];
}

@end
