//
//  SHKNetEaseWeibo.m
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

#import "SHKNetEaseWeibo.h"
#import "JSONKit.h"
#import "SHKConfiguration.h"
#import "NSMutableDictionary+NSNullsToEmptyStrings.h"


#define API_DOMAIN  @"http://api.t.163.com"

//static NSString *const kSHKNetEaseWeiboUserInfo = @"kSHKNetEaseWeiboUserInfo";


@interface SHKNetEaseWeibo ()

#pragma mark -
#pragma mark UI Implementation

- (void)showNetEaseWeiboForm;

#pragma mark -
#pragma mark Share API Methods

- (void)sendStatus;
- (void)sendStatusTicket:(OAServiceTicket *)ticket didFinishWithData:(NSData *)data;
- (void)sendStatusTicket:(OAServiceTicket *)ticket didFailWithError:(NSError*)error;

- (void)sendImage;
- (void)sendImageTicket:(OAServiceTicket *)ticket didFinishWithData:(NSData *)data;
- (void)sendImageTicket:(OAServiceTicket *)ticket didFailWithError:(NSError*)error;

- (void)sendUserInfo;
- (void)sendUserInfoTicket:(OAServiceTicket *)ticket didFinishWithData:(NSData *)data;
- (void)sendUserInfoTicket:(OAServiceTicket *)ticket didFailWithError:(NSError*)error;

- (void)shortenURL;
- (void)shortenURLFinished:(SHKRequest *)aRequest;

- (void)handleUnsuccessfulTicket:(NSData *)data;
- (void)followMe;

@end

@implementation SHKNetEaseWeibo

- (id)init
{
	if ((self = [super init]))
	{		
		// OAuth
		self.consumerKey = SHKCONFIG(netEaseWeiboConsumerKey);		
		self.secretKey = SHKCONFIG(netEaseWeiboConsumerSecret);
 		self.authorizeCallbackURL = [NSURL URLWithString:SHKCONFIG(netEaseWeiboCallbackUrl)];
				
		// You do not need to edit these, they are the same for everyone
		self.authorizeURL = [NSURL URLWithString:[NSString stringWithFormat:@"%@/oauth/authenticate", API_DOMAIN]];
		self.requestURL = [NSURL URLWithString:[NSString stringWithFormat:@"%@/oauth/request_token", API_DOMAIN]];
		self.accessURL = [NSURL URLWithString:[NSString stringWithFormat:@"%@/oauth/access_token", API_DOMAIN]];
	}	
	return self;
}

#pragma mark -
#pragma mark Configuration : Service Defination

+ (NSString *)sharerTitle
{
	return @"网易微博";
}

+ (BOOL)canShareURL
{
	return YES;
}

+ (BOOL)canShareText
{
	return YES;
}

+ (BOOL)canShareImage
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

//+ (void)logout {
//	
//	[[NSUserDefaults standardUserDefaults] removeObjectForKey:kSHKNetEaseWeiboUserInfo];
//	[super logout];    
//}


- (void)tokenAccessModifyRequest:(OAMutableURLRequest *)oRequest
{
    if (pendingAction == SHKPendingRefreshToken)
    {
        if (accessToken.sessionHandle != nil)
            [oRequest setOAuthParameterName:@"oauth_session_handle" withValue:accessToken.sessionHandle];	
    }
    
    else if ([authorizeResponseQueryVars objectForKey:@"oauth_verifier"])
        [oRequest setOAuthParameterName:@"oauth_verifier" withValue:[authorizeResponseQueryVars objectForKey:@"oauth_verifier"]];

}


#pragma mark -
#pragma mark UI Implementation

- (void)show
{
    if (item.shareType == SHKShareTypeURL || item.URL.absoluteString.length>25)
	{
		[self shortenURL];
	}
	
    else if (item.shareType == SHKShareTypeImage || item.image != nil)
	{
        [item setCustomValue:item.title?item.title:item.text forKey:@"status"];
		[self showNetEaseWeiboForm];
	}
	
    else if (item.shareType == SHKShareTypeUserInfo)
	{
		[self setQuiet:YES];
		[self tryToSend];
	}
    
    else
	{
        [item setCustomValue:item.text forKey:@"status"];
		[self showNetEaseWeiboForm];
	}
    
}

- (void)showNetEaseWeiboForm
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
		[item setCustomValue:[NSString stringWithFormat:@"%@ %@ ", item.title?item.title:item.text, [item.URL.absoluteString stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding]] forKey:@"status"];
        [self showNetEaseWeiboForm];
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

    [item setCustomValue:[NSString stringWithFormat:@"%@ %@ ", item.title?item.title:item.text, [item.URL.absoluteString stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding]] 
                  forKey:@"status"];
		
	[self showNetEaseWeiboForm];
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
	if (![self validateItem])
		return NO;
	
	if (item.shareType == SHKShareTypeImage || item.image!=nil)            
        [self sendImage];
    
    else if (item.shareType == SHKShareTypeUserInfo)           
        [self sendUserInfo];
    
	else
        [self sendStatus];
		
	// Notify delegate
	[self sendDidStart];	
	
	return YES;
}
	
- (void)sendStatus
{
	OAMutableURLRequest *oRequest = [[OAMutableURLRequest alloc] initWithURL:[NSURL URLWithString:[NSString stringWithFormat:@"%@/statuses/update.json", API_DOMAIN]]
                                                                    consumer:consumer
                                                                       token:accessToken
                                                                       realm:nil
                                                           signatureProvider:nil];
	
	[oRequest setHTTPMethod:@"POST"];
	
	OARequestParameter *statusParam = [[OARequestParameter alloc] initWithName:@"status"
																		 value:[item customValueForKey:@"status"]];
	NSArray *params = [NSArray arrayWithObjects:statusParam, nil];
	[oRequest setParameters:params];
	[statusParam release];
	
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

- (void)sendImage {
	
	NSURL *serviceURL = [NSURL URLWithString:[NSString stringWithFormat:@"%@/statuses/upload.json", API_DOMAIN]];
	
	OAMutableURLRequest *oRequest = [[OAMutableURLRequest alloc] initWithURL:serviceURL
																	consumer:consumer
																	   token:accessToken
																	   realm:nil
														   signatureProvider:nil];
    [oRequest setHTTPMethod:@"POST"];
    
	CGFloat compression = 0.9f;
	NSData *imageData = UIImageJPEGRepresentation([item image], compression);
	
	// TODO
	// Note from Nate to creator of sendImage method - This seems like it could be a source of sluggishness.
	// For example, if the image is large (say 3000px x 3000px for example), it would be better to resize the image
	// to an appropriate size (max of img.ly) and then start trying to compress.
	
	while ([imageData length] > 700000 && compression > 0.1) {
		// NSLog(@"Image size too big, compression more: current data size: %d bytes",[imageData length]);
		compression -= 0.1;
		imageData = UIImageJPEGRepresentation([item image], compression);
		
	}
	
	NSString *boundary = @"0xKhTmLbOuNdArY";
	NSString *contentType = [NSString stringWithFormat:@"multipart/form-data; boundary=%@",boundary];
	[oRequest setValue:contentType forHTTPHeaderField:@"Content-Type"];
	
	NSMutableData *body = [NSMutableData data];
	NSString *dispKey = @"Content-Disposition: form-data; name=\"pic\"; filename=\"upload.jpg\"\r\n";
    
	[body appendData:[[NSString stringWithFormat:@"--%@\r\n",boundary] dataUsingEncoding:NSUTF8StringEncoding]];
	[body appendData:[dispKey dataUsingEncoding:NSUTF8StringEncoding]];
	[body appendData:[@"Content-Type: image/jpg\r\n\r\n" dataUsingEncoding:NSUTF8StringEncoding]];
	[body appendData:imageData];
	[body appendData:[@"\r\n" dataUsingEncoding:NSUTF8StringEncoding]];
	
//		[body appendData:[[NSString stringWithFormat:@"--%@\r\n",boundary] dataUsingEncoding:NSUTF8StringEncoding]];
//		[body appendData:[[NSString stringWithString:@"Content-Disposition: form-data; name=\"status\"\r\n\r\n"] dataUsingEncoding:NSUTF8StringEncoding]];
//		[body appendData:[[item customValueForKey:@"status"] dataUsingEncoding:NSUTF8StringEncoding]];
//		[body appendData:[@"\r\n" dataUsingEncoding:NSUTF8StringEncoding]];	
	
	[body appendData:[[NSString stringWithFormat:@"--%@--\r\n",boundary] dataUsingEncoding:NSUTF8StringEncoding]];
	
	// setting the body of the post to the reqeust
	[oRequest setHTTPBody:body];
        
	// Start the request
	OAAsynchronousDataFetcher *fetcher = [OAAsynchronousDataFetcher asynchronousFetcherWithRequest:oRequest
																						  delegate:self
																				 didFinishSelector:@selector(sendImageTicket:didFinishWithData:)
																				   didFailSelector:@selector(sendImageTicket:didFailWithError:)];	
	
	[fetcher start];
	
	
	[oRequest release];
}

- (void)sendImageTicket:(OAServiceTicket *)ticket didFinishWithData:(NSData *)data {

	if (ticket.didSucceed) {
		[self sendDidFinish];
        
        // Finished uploading Image, now need to posh the message and url in netease weibo
        NSDictionary *result = [data objectFromJSONData];
        [item setCustomValue:[NSString stringWithFormat:@"%@ %@",  [item customValueForKey:@"status"], [result objectForKey:@"upload_image_url"]]  
                      forKey:@"status"];
        
        [self sendStatus];
	} else {
		[self handleUnsuccessfulTicket:data];
	}
}

- (void)sendImageTicket:(OAServiceTicket *)ticket didFailWithError:(NSError*)error {
	[self sendDidFailWithError:error];
}

- (void)sendUserInfo{
    
    OAMutableURLRequest *oRequest = [[OAMutableURLRequest alloc] initWithURL:[NSURL URLWithString:[NSString stringWithFormat:@"%@/account/verify_credentials.json",API_DOMAIN]]
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
        NSString *dataString = [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease];
		NSDictionary* account = [dataString objectFromJSONString];
        
        //[[NSUserDefaults standardUserDefaults] setValue:account forKey:kSHKNetEaseWeiboUserInfo];
        
        SHKLog(@"account: %@",account);
        
        NSMutableDictionary * dict = [NSMutableDictionary dictionaryWithCapacity:6];
        [dict setValue:[account valueForKey:@"screen_name"] forKey:@"uid"];//id = "-6032672804846278856";
        [dict setValue:[account valueForKey:@"name"] forKey:@"name"];
        [dict setValue:[account valueForKey:@"email"] forKey:@"email"];
        [dict setValue:[account valueForKey:@"verified"] forKey:@"isvip"];
        [dict setValue:[self sharerId] forKey:@"shareid"];
        [dict setObject:@"userinfo" forKey:@"task"];
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

- (void)authDidFinish:(BOOL)success{
    [super authDidFinish:success];
    if (success) {
        SHKItem* myitem = [SHKItem text:@""];
        myitem.shareType = SHKShareTypeUserInfo;
        [[self class] shareItem:myitem];
    }
}


- (void)handleUnsuccessfulTicket:(NSData *)data
{
	if (SHKDebugShowLogs)
		SHKLog(@"NetEase Send Status Error: %@", [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease]);
	
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
    // TODO:Is it same with NetEase? {"request":"/statuses/update.json","error":"oauth_problem=token_invalid HTTP status=401","error_code":"401","message_code":"00401token_invalid"}
	if ([errorMessage isEqualToString:@"Invalid / used nonce"] || [errorMessage isEqualToString:@"Could not authenticate with OAuth."]|| [errorMessage isEqualToString:@"oauth_problem=token_invalid HTTP status=401"]) {
		[[self class] logout];
		[self shouldReloginWithPendingAction:SHKPendingSend];
        return;
		
	} else {
		
		//when sharing image, and the user removed app permissions there is no JSON response expected above, but XML, which we need to parse. 401 is obsolete credentials -> need to relogin
		if ([string rangeOfString:@"401"].location != NSNotFound) {
			[[self class] logout];
			[self shouldReloginWithPendingAction:SHKPendingSend];
			return;
		}
	}
	
	[self sendDidFailWithError:[SHK error:errorMessage,nil]];
}


- (void)followMe
{
	OAMutableURLRequest *oRequest = [[OAMutableURLRequest alloc] initWithURL:[NSURL URLWithString:[NSString stringWithFormat:@"%@/friendships/create.json", API_DOMAIN]]
																	consumer:consumer
																	   token:accessToken
																	   realm:nil
														   signatureProvider:nil];
	
	[oRequest setHTTPMethod:@"POST"];
    OARequestParameter *statusParam = [[OARequestParameter alloc] initWithName:@"user_id"
																		 value:SHKCONFIG(netEaseWeiboUserID)];
	NSArray *params = [NSArray arrayWithObjects:statusParam, nil];
	[oRequest setParameters:params];
	[statusParam release];
    
	OAAsynchronousDataFetcher *fetcher = [OAAsynchronousDataFetcher asynchronousFetcherWithRequest:oRequest
                                                                                          delegate:self // Currently not doing any error handling here.  If it fails, it's probably best not to bug the user to follow you again.
                                                                                 didFinishSelector:nil
                                                                                   didFailSelector:nil];	
	
	[fetcher start];
	[oRequest release];
}

@end
