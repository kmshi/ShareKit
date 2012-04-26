//
//  SHKOAuth2Sharer.m
//  ShareKit
//
//  Created by kshi on 12-4-23.
//  Copyright (c) 2012年 __MyCompanyName__. All rights reserved.
//

#import "SHKOAuth2Sharer.h"
#import "NSHTTPCookieStorage+DeleteForURL.h"
#import "JSONKit.h"


@implementation SHKOAuth2Sharer
@synthesize clientID = clientID_,
clientSecret = clientSecret_,
redirectURI = redirectURI_,
parameters = parameters_,
authorizationURL = authorizationURL_,
tokenURL = tokenURL_,
expirationDate = expirationDate_,
additionalTokenRequestParameters = additionalTokenRequestParameters_;

// Response parameters
@dynamic accessToken,
refreshToken,
code,
errorString,
tokenType,
scope,
expiresIn;

#pragma mark Utility Routines

+ (NSString *)encodedOAuthValueForString:(NSString *)str {
    CFStringRef originalString = (CFStringRef) str;
    CFStringRef leaveUnescaped = NULL;
    CFStringRef forceEscaped =  CFSTR("!*'();:@&=+$,/?%#[]");
    
    CFStringRef escapedStr = NULL;
    if (str) {
        escapedStr = CFURLCreateStringByAddingPercentEscapes(kCFAllocatorDefault,
                                                             originalString,
                                                             leaveUnescaped,
                                                             forceEscaped,
                                                             kCFStringEncodingUTF8);
        [(id)CFMakeCollectable(escapedStr) autorelease];
    }
    
    return (NSString *)escapedStr;
}

+ (NSString *)encodedQueryParametersForDictionary:(NSDictionary *)dict {
    // Make a string like "cat=fluffy&dog=spot"
    NSMutableString *result = [NSMutableString string];
    NSArray *sortedKeys = [[dict allKeys] sortedArrayUsingSelector:@selector(caseInsensitiveCompare:)];
    NSString *joiner = @"";
    for (NSString *key in sortedKeys) {
        NSString *value = [dict objectForKey:key];
        NSString *encodedValue = [self encodedOAuthValueForString:value];
        NSString *encodedKey = [self encodedOAuthValueForString:key];
        [result appendFormat:@"%@%@=%@", joiner, encodedKey, encodedValue];
        joiner = @"&";
    }
    return result;
}

+ (NSString *)scopeWithStrings:(NSString *)str, ... {
    // concatenate the strings, joined by a single space
    NSString *result = @"";
    NSString *joiner = @"";
    if (str) {
        va_list argList;
        va_start(argList, str);
        while (str) {
            result = [result stringByAppendingFormat:@"%@%@", joiner, str];
            joiner = @" ";
            str = va_arg(argList, id);
        }
        va_end(argList);
    }
    return result;
}

- (id)init {
    self = [super init];
    if (self) {
        parameters_ = [[NSMutableDictionary alloc] init];
        additionalTokenRequestParameters_ = [[NSMutableDictionary alloc] init];
    }
    return self;
}

- (void)dealloc {
    [clientID_ release];
    [clientSecret_ release];
    [redirectURI_ release];
    [parameters_ release];
    [authorizationURL_ release];
    [tokenURL_ release];
    [expirationDate_ release];
    [additionalTokenRequestParameters_ release];
    
    [super dealloc];
}

#pragma mark -
#pragma mark Authorization

- (BOOL)isAuthorized
{		
	return [self restoreRefreshToken];
}

- (void)promptAuthorization
{		
	[self tokenAuthorize];
}

- (void)storeRefreshToken{
    [SHK setAuthValue:self.refreshToken forKey:kOAuth2RefreshTokenKey forSharer:[self sharerId]];
    [SHK setAuthValue:self.accessToken forKey:kOAuth2AccessTokenKey forSharer:[self sharerId]];
    [SHK setAuthValue:[self.expiresIn stringValue] forKey:kOAuth2ExpiresInKey forSharer:[self sharerId]];
}

- (BOOL)restoreRefreshToken{
    NSString* refreshToken = [SHK getAuthValueForKey:kOAuth2RefreshTokenKey forSharer:[self sharerId]];
    if (refreshToken) self.refreshToken = refreshToken;
    NSString* accessToken = [SHK getAuthValueForKey:kOAuth2AccessTokenKey forSharer:[self sharerId]];
    if (accessToken)  self.accessToken = accessToken;
    NSString* expiresIn = [SHK getAuthValueForKey:kOAuth2ExpiresInKey forSharer:[self sharerId]];
    if (expiresIn) self.expiresIn = [NSNumber numberWithInt:[expiresIn intValue]];
    if (self.refreshToken) {
        return YES;
    }
    
    return NO;
}

+ (void)deleteStoredRefreshToken
{
	NSString *sharerId = [self sharerId];
	
	[SHK removeAuthValueForKey:kOAuth2RefreshTokenKey forSharer:sharerId];
    [SHK removeAuthValueForKey:kOAuth2AccessTokenKey forSharer:sharerId];
    [SHK removeAuthValueForKey:kOAuth2ExpiresInKey forSharer:sharerId];
}

+ (void)logout
{
	[self deleteStoredRefreshToken];
	
	// Clear cookies (for OAuth, doesn't affect XAuth)
	// TODO - move the authorizeURL out of the init call (into a define) so we don't have to create an object just to get it
	SHKOAuth2Sharer *sharer = [[self alloc] init];
	if (sharer.authorizationURL)
	{
		[NSHTTPCookieStorage deleteCookiesForURL:sharer.authorizationURL];
    }
	[sharer release];
}


- (void)refreshAccessToken{
    self.pendingAction = SHKPendingRefreshToken;
    [self tokenAccess];
}

#pragma mark Authorize 

- (void)tokenAuthorize
{	
    NSMutableDictionary *paramsDict = [NSMutableDictionary dictionary];
    
    [paramsDict setObject:self.clientID forKey:@"client_id"];
    [paramsDict setObject:self.scope forKey:@"scope"];
    [paramsDict setObject:@"code" forKey:@"response_type"];
    [paramsDict setObject:self.redirectURI forKey:@"redirect_uri"];
    
    if (self.parameters) {
        [paramsDict addEntriesFromDictionary:self.parameters];
    }
    
    NSString *paramStr = [[self class] encodedQueryParametersForDictionary:paramsDict];

	NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"%@?%@", authorizationURL_.absoluteString, paramStr]];
    
    SHKLog(@"Authorize url:%@",url.absoluteString);
	SHKOAuthView *auth = [[SHKOAuthView alloc] initWithURL:url delegate:self];
	[[SHK currentHelper] showViewController:auth];	
	[auth release];
}

- (void)tokenAuthorizeView:(SHKOAuthView *)authView didFinishWithSuccess:(BOOL)success queryParams:(NSMutableDictionary *)queryParams error:(NSError *)error;
{
	[[SHK currentHelper] hideCurrentViewControllerAnimated:YES];
	
	if (!success)
	{
		[[[[UIAlertView alloc] initWithTitle:SHKLocalizedString(@"Authorize Error")
									 message:error!=nil?[error localizedDescription]:SHKLocalizedString(@"There was an error while authorizing")
									delegate:nil
						   cancelButtonTitle:SHKLocalizedString(@"Close")
						   otherButtonTitles:nil] autorelease] show];
		[self authDidFinish:success];
	}	
	
	else if ([queryParams objectForKey:kOAuth2ErrorKey])
	{
		SHKLog(@"oauth_problem reported: %@", [queryParams objectForKey:kOAuth2ErrorKey]);
        
		[[[[UIAlertView alloc] initWithTitle:SHKLocalizedString(@"Authorize Error")
									 message:error!=nil?[error localizedDescription]:SHKLocalizedString(@"There was an error while authorizing")
									delegate:nil
						   cancelButtonTitle:SHKLocalizedString(@"Close")
						   otherButtonTitles:nil] autorelease] show];
		success = NO;
		[self authDidFinish:success];
	}
    
	else 
	{
		[self setKeysForResponseDictionary:queryParams];
		
		[self tokenAccess];
	}
}

- (void)tokenAuthorizeCancelledView:(SHKOAuthView *)authView
{
	[[SHK currentHelper] hideCurrentViewControllerAnimated:YES];
	[self authDidFinish:NO];
}



- (void)setKeysForResponseDictionary:(NSDictionary *)dict {
    SHKLog(@"%@",dict);
    if (dict == nil) return;
    
    // If a new code or access token is being set, remove the old expiration
    NSString *newCode = [dict objectForKey:kOAuth2CodeKey];
    NSString *newAccessToken = [dict objectForKey:kOAuth2AccessTokenKey];
    if (newCode || newAccessToken) {
        self.expiresIn = nil;
    }
    
    BOOL didRefreshTokenChange = NO;
    NSString *refreshToken = [dict objectForKey:kOAuth2RefreshTokenKey];
    if (refreshToken) {
        NSString *priorRefreshToken = self.refreshToken;
        
        if (priorRefreshToken != refreshToken
            && (priorRefreshToken == nil
                || ![priorRefreshToken isEqual:refreshToken])) {
                didRefreshTokenChange = YES;
            }
    }
    
    [self.parameters addEntriesFromDictionary:dict];
    [self updateExpirationDate];
    
//    if (didRefreshTokenChange) {
//        NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
//        [nc postNotificationName:kGTMOAuth2RefreshTokenChanged
//                          object:self
//                        userInfo:nil];
//    }
    // NSLog(@"keys set ----------------------------\n%@", dict);
}


- (void)setKeysForResponseJSONData:(NSData *)data {
    NSDictionary *dict = [data objectFromJSONData];
    [self setKeysForResponseDictionary:dict];
}


- (BOOL)shouldRefreshAccessToken {
    // We should refresh the access token when it's missing or nearly expired
    // and we have a refresh token
    BOOL shouldRefresh = NO;
    NSString *accessToken = self.accessToken;
    NSString *refreshToken = self.refreshToken;
    
    BOOL hasRefreshToken = ([refreshToken length] > 0);
    BOOL hasAccessToken = ([accessToken length] > 0);
    
    // Determine if we need to refresh the access token
    if (hasRefreshToken) {
        if (!hasAccessToken) {
            shouldRefresh = YES;
        } else {
            // We'll consider the token expired if it expires 60 seconds from now
            // or earlier
            NSDate *expirationDate = self.expirationDate;
            NSTimeInterval timeToExpire = [expirationDate timeIntervalSinceNow];
            if (expirationDate == nil || timeToExpire < 60.0) {
                // access token has expired, or will in a few seconds
                shouldRefresh = YES;
            }
        }
    }
    return shouldRefresh;
}

- (void)tokenAccess {
    
    NSMutableDictionary *paramsDict = [NSMutableDictionary dictionary];
    NSString *refreshToken = self.refreshToken;
    NSString *code = self.code;
        
    if (refreshToken) {
        // We have a refresh token
        [paramsDict setObject:@"refresh_token" forKey:@"grant_type"];
        [paramsDict setObject:refreshToken forKey:@"refresh_token"];
        
    } else if (code) {
        // We have a code string
        [paramsDict setObject:@"authorization_code" forKey:@"grant_type"];
        [paramsDict setObject:code forKey:@"code"];
        
        NSString *redirectURI = self.redirectURI;
        if ([redirectURI length] > 0) {
            [paramsDict setObject:redirectURI forKey:@"redirect_uri"];
        }
        
        NSString *scope = self.scope;
        if ([scope length] > 0) {
            [paramsDict setObject:scope forKey:@"scope"];
        }
        
    } else {
#if DEBUG
        NSAssert(0, @"unexpected lack of code or refresh token for fetching");
#endif
        return;
    }
    
    NSString *clientID = self.clientID;
    if ([clientID length] > 0) {
        [paramsDict setObject:clientID forKey:@"client_id"];
    }
    
    NSString *clientSecret = self.clientSecret;
    if ([clientSecret length] > 0) {
        [paramsDict setObject:clientSecret forKey:@"client_secret"];
    }
    
    NSDictionary *additionalParams = self.additionalTokenRequestParameters;
    if (additionalParams) {
        [paramsDict addEntriesFromDictionary:additionalParams];
    }
    
    NSString *paramStr = [[self class] encodedQueryParametersForDictionary:paramsDict];
    SHKLog(@"tokenUrl:%@?%@",tokenURL_.absoluteString,paramStr);
    NSData *paramData = [paramStr dataUsingEncoding:NSUTF8StringEncoding];
    
    NSURL *tokenURL = self.tokenURL;
    
    [[SHKActivityIndicator currentIndicator] displayActivity:SHKLocalizedString(@"Authenticating...")];
    
    NSMutableURLRequest *oRequest = [NSMutableURLRequest requestWithURL:tokenURL];
    [oRequest setValue:@"application/x-www-form-urlencoded" forHTTPHeaderField:@"Content-Type"];
    
    [oRequest setHTTPMethod:@"POST"];
    oRequest.HTTPBody = paramData;
    
    OAAsynchronousDataFetcher *fetcher = [OAAsynchronousDataFetcher asynchronousFetcherWithRequest:oRequest
                                                                                          delegate:self
                                                                                 didFinishSelector:@selector(requestTicket:didFinishWithData:)
                                                                                   didFailSelector:@selector(requestTicket:didFailWithError:)];
	[fetcher start];
}

- (void)requestTicket:(OAServiceTicket *)ticket didFinishWithData:(NSData *)data{
    [[SHKActivityIndicator currentIndicator] hide];
    if (ticket.didSucceed){
        [self setKeysForResponseJSONData:data];
        [self storeRefreshToken];
        
        [self tryPendingAction];
#if DEBUG
    // Watch for token exchanges that return a non-bearer or unlabeled token
    NSString *tokenType = [self tokenType];
    if (tokenType == nil
        || [tokenType caseInsensitiveCompare:@"bearer"] != NSOrderedSame) {
        NSLog(@"Unexpected token type: %@", tokenType);
    }
#endif  
    }else{
		// TODO - better error handling here
		[self requestTicket:ticket didFailWithError:[SHK error:SHKLocalizedString(@"There was a problem requesting access from %@", [self sharerTitle])]];
    }
	[self authDidFinish:ticket.didSucceed];
}


- (void)requestTicket:(OAServiceTicket *)ticket didFailWithError:(NSError*)error{
    [[SHKActivityIndicator currentIndicator] hide];
    
    [[[[UIAlertView alloc] initWithTitle:SHKLocalizedString(@"Access Error")
								 message:error!=nil?[error localizedDescription]:SHKLocalizedString(@"There was an error while sharing")
								delegate:nil
					   cancelButtonTitle:SHKLocalizedString(@"Close")
					   otherButtonTitles:nil] autorelease] show];

}


#pragma mark Accessors for Response Parameters

- (NSString *)accessToken {
    return [self.parameters objectForKey:kOAuth2AccessTokenKey];
}

- (void)setAccessToken:(NSString *)str {
    [self.parameters setValue:str forKey:kOAuth2AccessTokenKey];
}

- (NSString *)refreshToken {
    return [self.parameters objectForKey:kOAuth2RefreshTokenKey];
}

- (void)setRefreshToken:(NSString *)str {
    [self.parameters setValue:str forKey:kOAuth2RefreshTokenKey];
}

- (NSString *)code {
    return [self.parameters objectForKey:kOAuth2CodeKey];
}

- (void)setCode:(NSString *)str {
    [self.parameters setValue:str forKey:kOAuth2CodeKey];
}

- (NSString *)errorString {
    return [self.parameters objectForKey:kOAuth2ErrorKey];
}

- (void)setErrorString:(NSString *)str {
    [self.parameters setValue:str forKey:kOAuth2ErrorKey];
}

- (NSString *)tokenType {
    return [self.parameters objectForKey:kOAuth2TokenTypeKey];
}

- (void)setTokenType:(NSString *)str {
    [self.parameters setValue:str forKey:kOAuth2TokenTypeKey];
}

- (NSString *)scope {
    return [self.parameters objectForKey:kOAuth2ScopeKey];
}

- (void)setScope:(NSString *)str {
    [self.parameters setValue:str forKey:kOAuth2ScopeKey];
}

- (NSNumber *)expiresIn {
    return [self.parameters objectForKey:kOAuth2ExpiresInKey];
}

- (void)setExpiresIn:(NSNumber *)num {
    [self.parameters setValue:num forKey:kOAuth2ExpiresInKey];
    [self updateExpirationDate];
}

- (void)updateExpirationDate {
    // Update our absolute expiration time to something close to when
    // the server expects the expiration
    NSDate *date = nil;
    NSNumber *expiresIn = self.expiresIn;
    if (expiresIn) {
        unsigned long deltaSeconds = [expiresIn unsignedLongValue];
        if (deltaSeconds > 0) {
            date = [NSDate dateWithTimeIntervalSinceNow:deltaSeconds];
        }
    }
    self.expirationDate = date;
}

- (NSURL *)authorizeCallbackURL{
    return [NSURL URLWithString:redirectURI_];
}
@end
