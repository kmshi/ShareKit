//
//  SHKTencentWeibo.m
//  ShareKit
//
//  As Tencent OAuth is sluggish, you have to pass API_DOMAIN as realm to the OAMutalRequest
//  --It does not use OAuth header but url query, and nonce has 30 length limit.
//  Created by kshi on 12-5-1.
//  Copyright (c) 2012年 __MyCompanyName__. All rights reserved.
//
#include <ifaddrs.h>
#include <arpa/inet.h>

#import "SHKTencentWeibo.h"
#import "JSONKit.h"
#import "SHKConfiguration.h"
#import "NSMutableDictionary+NSNullsToEmptyStrings.h"

#define API_DOMAIN  @"https://open.t.qq.com"
//static NSString *const kSHKTencentWeiboUserInfo = @"kSHKTencentWeiboUserInfo";

@interface SHKTencentWeibo ()
#pragma mark -
#pragma mark UI Implementation

- (void)showTencentWeiboForm;

#pragma mark -
#pragma mark Share API Methods

- (void)sendStatus;
- (void)sendStatusTicket:(OAServiceTicket *)ticket didFinishWithData:(NSData *)data;
- (void)sendStatusTicket:(OAServiceTicket *)ticket didFailWithError:(NSError*)error;

- (void)sendImage;
- (void)sendImageTicket:(OAServiceTicket *)ticket didFinishWithData:(NSData *)data;
- (void)sendImageTicket:(OAServiceTicket *)ticket didFailWithError:(NSError*)error;

// TODO: Finish it below
//- (void)sendUserInfo;
//- (void)sendUserInfo:(OAServiceTicket *)ticket didFinishWithData:(NSData *)data;
//- (void)sendUserInfo:(OAServiceTicket *)ticket didFailWithError:(NSError*)error;

- (BOOL)shortenURL;
- (void)shortenURLFinished:(SHKRequest *)aRequest;

- (void)handleUnsuccessfulTicket:(NSData *)data;
- (NSString *)getIPAddress;
@end

@implementation SHKTencentWeibo

- (id)init
{
	if ((self = [super init]))
	{		
		// OAuth
		self.consumerKey = SHKCONFIG(tencentWeiboConsumerKey);		
		self.secretKey = SHKCONFIG(tencentWeiboConsumerSecret);
 		self.authorizeCallbackURL = [NSURL URLWithString:SHKCONFIG(tencentWeiboCallbackUrl)];
		
		// -- //
		
		// You do not need to edit these, they are the same for everyone
		self.authorizeURL = [NSURL URLWithString:[NSString stringWithFormat:@"%@/cgi-bin/authorize", API_DOMAIN]];
		self.requestURL = [NSURL URLWithString:[NSString stringWithFormat:@"%@/cgi-bin/request_token", API_DOMAIN]];
		self.accessURL = [NSURL URLWithString:[NSString stringWithFormat:@"%@/cgi-bin/access_token", API_DOMAIN]];
	}	
	return self;
}


#pragma mark -
#pragma mark Configuration : Service Defination

+ (NSString *)sharerTitle
{
	return @"腾讯微博";
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

//+ (BOOL)canGetUserInfo
//{
//	return YES;
//}

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
//	[[NSUserDefaults standardUserDefaults] removeObjectForKey:kSHKTencentWeiboUserInfo];
//	[super logout];    
//}

- (void)tokenRequest
{
	[[SHKActivityIndicator currentIndicator] displayActivity:SHKLocalizedString(@"Connecting...")];
	
    OAMutableURLRequest *oRequest = [[OAMutableURLRequest alloc] initWithURL:requestURL
                                                                    consumer:consumer
                                                                       token:nil   // we don't have a Token yet
                                                                       realm:API_DOMAIN   // our service provider doesn't specify a realm
														   signatureProvider:signatureProvider];
    
	
	//[oRequest setOAuthParameterName:@"format" withValue:@"json"];
    [oRequest setOAuthParameterName:@"oauth_callback" withValue:[self.authorizeCallbackURL absoluteString]];
    [oRequest setHTTPMethod:@"GET"];
	
	[self tokenRequestModifyRequest:oRequest];
	
    OAAsynchronousDataFetcher *fetcher = [OAAsynchronousDataFetcher asynchronousFetcherWithRequest:oRequest
                                                                                          delegate:self
                                                                                 didFinishSelector:@selector(tokenRequestTicket:didFinishWithData:)
                                                                                   didFailSelector:@selector(tokenRequestTicket:didFailWithError:)];
	[fetcher start];	
	[oRequest release];
}

- (void)tokenAccess:(BOOL)refresh
{
	if (!refresh)
		[[SHKActivityIndicator currentIndicator] displayActivity:SHKLocalizedString(@"Authenticating...")];
	
    OAMutableURLRequest *oRequest = [[OAMutableURLRequest alloc] initWithURL:accessURL
                                                                    consumer:consumer
																	   token:(refresh ? accessToken : requestToken)
                                                                       realm:API_DOMAIN   // our service provider doesn't specify a realm
                                                           signatureProvider:signatureProvider]; // use the default method, HMAC-SHA1
	
    [oRequest setHTTPMethod:@"GET"];
	
	[self tokenAccessModifyRequest:oRequest];
	
    OAAsynchronousDataFetcher *fetcher = [OAAsynchronousDataFetcher asynchronousFetcherWithRequest:oRequest
                                                                                          delegate:self
                                                                                 didFinishSelector:@selector(tokenAccessTicket:didFinishWithData:)
                                                                                   didFailSelector:@selector(tokenAccessTicket:didFailWithError:)];
	[fetcher start];
	[oRequest release];
}


- (void)tokenAccessModifyRequest:(OAMutableURLRequest *)oRequest
{	
    if (pendingAction == SHKPendingRefreshToken)
    {
        if (accessToken.sessionHandle != nil)
            [oRequest setOAuthParameterName:@"oauth_session_handle" withValue:accessToken.sessionHandle];
    }
    else
        [oRequest setOAuthParameterName:@"oauth_verifier" withValue:[authorizeResponseQueryVars objectForKey:@"oauth_verifier"]];
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
		[self showTencentWeiboForm];
	}
	
	else if (item.shareType == SHKShareTypeText)
	{
        [item setCustomValue:item.text forKey:@"status"];
		[self showTencentWeiboForm];
	}
    
    else if (item.shareType == SHKShareTypeUserInfo)
	{
		[self setQuiet:YES];
		[self tryToSend];
	}
}

- (void)showTencentWeiboForm
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

- (BOOL)shortenURL
{
    if (![SHK connected]||[SHKCONFIG(sinaWeiboConsumerKey) isEqualToString:@""] || SHKCONFIG(sinaWeiboConsumerKey) == nil)
	{
		[item setCustomValue:[NSString stringWithFormat:@"%@ %@", item.title, [item.URL.absoluteString stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding]] forKey:@"status"];
		return NO;
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
    
    return YES;
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
	
	[self showTencentWeiboForm];
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
	
	switch (item.shareType) {
			
		case SHKShareTypeImage:            
			[self sendImage];
			break;
			
            //		case SHKShareTypeUserInfo:            
            //			[self sendUserInfo];
            //			break;
			
		default:
			[self sendStatus];
			break;
	}
	
	// Notify delegate
	[self sendDidStart];	
	
	return YES;
}

//ref:https://github.com/taobao-idev/TBShareKit/blob/master/ShareKit/Sharers/Services/Tencent/SHKTencent.m
- (NSString *)getIPAddress 
{
    return @"8.8.8.8";//as the following code always return error in simulator
    
	NSString *address = @"error";
	struct ifaddrs *interfaces = NULL;
	struct ifaddrs *temp_addr = NULL;
	int success = 0;
    
	//retrieve the current interfaces - returns 0 on success
	success = getifaddrs(&interfaces);
	if (success == 0) {
		//Loop through linked list of interfaces
		temp_addr = interfaces;
		while (temp_addr != NULL) {
			if (temp_addr->ifa_addr->sa_family == AF_INET) {
				//Check if interface is en0 which is the wifi connection on the iPhone
				if ([[NSString stringWithUTF8String: temp_addr->ifa_name] isEqualToString:@"en0"]) {
					//Get NSString from C String
//					address =[NSString stringWithCString:inet_ntoa(((struct sockaddr_in *) temp_addr->ifa_addr)->sin_addr) encoding:NSUTF8StringEncoding];
//                    break;
                    address =[NSString stringWithUTF8String:inet_ntoa(((struct sockaddr_in *) temp_addr->ifa_addr)->sin_addr)];
				}
			}
			temp_addr = temp_addr->ifa_next;
		}
	}
	//Free memory
	freeifaddrs(interfaces);
	SHKLog(@"current address: %@", address);
	return address;
}

- (void)sendStatus
{
	OAMutableURLRequest *oRequest = [[OAMutableURLRequest alloc] initWithURL:[NSURL URLWithString:@"http://open.t.qq.com/api/t/add"]
                                                                    consumer:consumer
                                                                       token:accessToken
                                                                       realm:API_DOMAIN
                                                           signatureProvider:nil];
	
	[oRequest setHTTPMethod:@"POST"];
	
    OARequestParameter *formatParam =[[OARequestParameter alloc] initWithName:@"format" value:@"json"];
	OARequestParameter *contentParam =[[OARequestParameter alloc] initWithName:@"content" value:[item customValueForKey:@"status"]];
	OARequestParameter *ipParam =[[OARequestParameter alloc] initWithName:@"clientip" value:[self getIPAddress]];
    
	NSArray *params = [NSArray arrayWithObjects:formatParam,contentParam,ipParam, nil];
	[oRequest setParameters:params];
	[formatParam release];
    [contentParam release];
    [ipParam release];
	
	OAAsynchronousDataFetcher *fetcher = [OAAsynchronousDataFetcher asynchronousFetcherWithRequest:oRequest
                                                                                          delegate:self
                                                                                 didFinishSelector:@selector(sendStatusTicket:didFinishWithData:)
                                                                                   didFailSelector:@selector(sendStatusTicket:didFailWithError:)];	
    
	[fetcher start];
	[oRequest release];
}

- (void)sendStatusTicket:(OAServiceTicket *)ticket didFinishWithData:(NSData *)data 
{
	if (ticket.didSucceed) {
        NSString *dataString = [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease];
        NSDictionary* result = [dataString objectFromJSONString];
		
		if ([[result valueForKey:@"ret"] intValue]==0) {
            [self sendDidFinish];
        }else {
            [self handleUnsuccessfulTicket:data];
        }
	}
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
	
	NSURL *serviceURL = [NSURL URLWithString:@"http://open.t.qq.com/api/t/add_pic"];
	
	OAMutableURLRequest *oRequest = [[OAMutableURLRequest alloc] initWithURL:serviceURL
																	consumer:consumer
																	   token:accessToken
																	   realm:API_DOMAIN
														   signatureProvider:signatureProvider];
    [oRequest setHTTPMethod:@"POST"];
    
    OARequestParameter *formatParam =[[OARequestParameter alloc] initWithName:@"format" value:@"json"];
	OARequestParameter *contentParam =[[OARequestParameter alloc] initWithName:@"content" value:[item customValueForKey:@"status"]];
	OARequestParameter *ipParam =[[OARequestParameter alloc] initWithName:@"clientip" value:[self getIPAddress]];
    
	NSArray *params = [NSArray arrayWithObjects:formatParam,contentParam,ipParam,nil];
	[oRequest setParameters:params];
	[formatParam release];
    [contentParam release];
    [ipParam release];

    [oRequest prepare];
    
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
	
    [body appendData:[[NSString stringWithFormat:@"--%@\r\n",boundary] dataUsingEncoding:NSUTF8StringEncoding]];
    [body appendData:[[NSString stringWithString:@"Content-Disposition: form-data; name=\"content\"\r\n\r\n"] dataUsingEncoding:NSUTF8StringEncoding]];
    [body appendData:[[item customValueForKey:@"status"] dataUsingEncoding:NSUTF8StringEncoding]];
    [body appendData:[@"\r\n" dataUsingEncoding:NSUTF8StringEncoding]];	

    [body appendData:[[NSString stringWithFormat:@"--%@\r\n",boundary] dataUsingEncoding:NSUTF8StringEncoding]];
    [body appendData:[[NSString stringWithString:@"Content-Disposition: form-data; name=\"format\"\r\n\r\n"] dataUsingEncoding:NSUTF8StringEncoding]];
    [body appendData:[@"json" dataUsingEncoding:NSUTF8StringEncoding]];
    [body appendData:[@"\r\n" dataUsingEncoding:NSUTF8StringEncoding]];	

    [body appendData:[[NSString stringWithFormat:@"--%@\r\n",boundary] dataUsingEncoding:NSUTF8StringEncoding]];
    [body appendData:[[NSString stringWithString:@"Content-Disposition: form-data; name=\"clientip\"\r\n\r\n"] dataUsingEncoding:NSUTF8StringEncoding]];
    [body appendData:[[self getIPAddress] dataUsingEncoding:NSUTF8StringEncoding]];
    [body appendData:[@"\r\n" dataUsingEncoding:NSUTF8StringEncoding]];	

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
		
		// Finished uploading Image, now need to posh the message and url
		NSString *dataString = [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease];
		NSDictionary* result = [dataString objectFromJSONString];
		
		if ([[result valueForKey:@"ret"] intValue]==0) {
			SHKLog(@"imgurl: %@",[result valueForKey:@"imgurl"]);
            [self sendDidFinish];
		}else {
            [self handleUnsuccessfulTicket:data];
        }
 		
	} else {
		[self handleUnsuccessfulTicket:data];
	}
}

- (void)sendImageTicket:(OAServiceTicket *)ticket didFailWithError:(NSError*)error {
	[self sendDidFailWithError:error];
}

- (void)handleUnsuccessfulTicket:(NSData *)data
{
	if (SHKDebugShowLogs)
		SHKLog(@"Tencent Send Status Error: %@", [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease]);
	
    //{"data":null,"errcode":-3180,"msg":"check sign error","ret":3}
    //    ret=0
    //    成功返回
    //    ret=1
    //    参数错误
    //    ret=2
    //    频率受限
    //    ret=3
    //    鉴权失败
    //    ret=4
    //    服务器内部错误
    NSString *errorMessage = @"Unknown Error";
    @try {
        NSString *dataString = [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease];
        NSDictionary* result = [dataString objectFromJSONString];
        if ([[result valueForKey:@"ret"] intValue]==3) {
			[self shouldReloginWithPendingAction:SHKPendingSend];
            return;
		}else {
            errorMessage = [result valueForKey:@"msg"];
        }
    }
    @catch (NSException *exception) {
        errorMessage = [exception description];
    }
        
	[self sendDidFailWithError:[SHK error:errorMessage,nil]];
}

- (void)followMe
{    
	OAMutableURLRequest *oRequest = [[OAMutableURLRequest alloc] initWithURL:[NSURL URLWithString:@"http://open.t.qq.com/api/friends/add"]
																	consumer:consumer
																	   token:accessToken
																	   realm:API_DOMAIN
														   signatureProvider:nil];
	
	[oRequest setHTTPMethod:@"POST"];
    
    OARequestParameter *formatParam =[[OARequestParameter alloc] initWithName:@"format" value:@"json"];
	OARequestParameter *nameParam =[[OARequestParameter alloc] initWithName:@"name" value:SHKCONFIG(tencentWeiboUserID)];
    
	NSArray *params = [NSArray arrayWithObjects:formatParam,nameParam, nil];
	[oRequest setParameters:params];
	[formatParam release];
    [nameParam release];
    
	OAAsynchronousDataFetcher *fetcher = [OAAsynchronousDataFetcher asynchronousFetcherWithRequest:oRequest
                                                                                          delegate:nil // Currently not doing any error handling here.  If it fails, it's probably best not to bug the user to follow you again.
                                                                                 didFinishSelector:nil
                                                                                   didFailSelector:nil];	
	
	[fetcher start];
	[oRequest release];
}


@end
