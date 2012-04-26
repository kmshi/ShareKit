//
//  SHKGooglePlus.m
//  ShareKit
//
//  --Currently google only make readonly api public, send status/image/url functions are still not available
//
//  Created by kshi on 12-4-24.
//  Copyright (c) 2012年 __MyCompanyName__. All rights reserved.
//

#import "SHKGooglePlus.h"
#import "SHKConfiguration.h"

@implementation SHKGooglePlus

- (id)init
{
	if (self = [super init])
	{	
		// OAUTH		
		self.clientID = SHKCONFIG(googleplusConsumerKey);		
		self.clientSecret = SHKCONFIG(googleplusConsumerSecret);
 		self.redirectURI = SHKCONFIG(googleplusCallbackUrl);		
		
		// -- //
		
		
		// You do not need to edit these, they are the same for everyone
		self.authorizationURL = [NSURL URLWithString:@"https://accounts.google.com/o/oauth2/auth"];
		self.tokenURL = [NSURL URLWithString:@"https://accounts.google.com/o/oauth2/token"];
        self.scope = [[self class] scopeWithStrings:@"https://www.googleapis.com/auth/urlshortener",@"https://www.googleapis.com/auth/plus.me", nil];
        
        [self.parameters setValue:@"offline" forKey:@"access_type"];
        
        //[self.additionalTokenRequestParameters setValue:@"https://oauth.live.com/desktop" forKey:kOAuth2RedirectURIKey];
	}	
	return self;
}


#pragma mark -
#pragma mark Configuration : Service Defination

+ (NSString *)sharerTitle
{
	return @"Google+";
}

+ (BOOL)canShareURL
{
	return YES;
}

+ (BOOL)canShareText
{
	return YES;
}

// TODO use img.ly to support this
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

- (void)show{
    SHKLog(@"show should be override");
    if (item.shareType == SHKShareTypeURL)
	{
		[item setCustomValue:item.URL.absoluteString forKey:@"status"];
	}
	
	else if (item.shareType == SHKShareTypeImage)
	{
		[item setCustomValue:item.title forKey:@"status"];
	}
	
	else if (item.shareType == SHKShareTypeText)
	{
		[item setCustomValue:item.text forKey:@"status"];
	}
	else if (item.shareType == SHKShareTypeUserInfo)
	{
		[self setQuiet:YES];
		[self tryToSend];
        return;
	}

    SHKCustomFormControllerLargeTextField *rootView = [[SHKCustomFormControllerLargeTextField alloc] initWithNibName:nil bundle:nil delegate:self];	
	
	rootView.text = [item customValueForKey:@"status"];
	rootView.maxTextLength = 140;
	rootView.image = item.image;
	rootView.imageTextLength = 25;
	
	self.navigationBar.tintColor = SHKCONFIG_WITH_ARGUMENT(barTintForView:,self);
	
	[self pushViewController:rootView animated:NO];
	[rootView release];
	
	[[SHK currentHelper] showViewController:self];	

}

- (void)sendForm:(SHKCustomFormControllerLargeTextField *)form
{	
	[item setCustomValue:form.textView.text forKey:@"status"];
	[self tryToSend];
}

- (void)sendDidCancel{
    SHKLog(@"sendDidCancel");
}

- (BOOL)send{
    SHKLog(@"send should be override");
    if ([item customValueForKey:@"status"]==nil) {
        return NO;
    }
    if ([self shouldRefreshAccessToken]) {
        [self refreshAccessToken];
        return YES;
    }
    
    //Google currently only expose readonly apis, staytuned...
    
    SHKLog(@"to send status:%@",[item customValueForKey:@"status"]);
    
    return YES;
}
@end
