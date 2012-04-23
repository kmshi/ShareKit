//
//  SHKOAuth2Sharer.m
//  ShareKit
//
//  Created by kshi on 12-4-23.
//  Copyright (c) 2012年 __MyCompanyName__. All rights reserved.
//

#import "SHKOAuth2Sharer.h"
#import "NSHTTPCookieStorage+DeleteForURL.h"

// standard OAuth keys
static NSString *const kOAuth2AccessTokenKey       = @"access_token";
static NSString *const kOAuth2RefreshTokenKey      = @"refresh_token";
static NSString *const kOAuth2ClientIDKey          = @"client_id";
static NSString *const kOAuth2ClientSecretKey      = @"client_secret";
static NSString *const kOAuth2RedirectURIKey       = @"redirect_uri";
static NSString *const kOAuth2ResponseTypeKey      = @"response_type";
static NSString *const kOAuth2ScopeKey             = @"scope";
static NSString *const kOAuth2ErrorKey             = @"error";
static NSString *const kOAuth2TokenTypeKey         = @"token_type";
static NSString *const kOAuth2ExpiresInKey         = @"expires_in";
static NSString *const kOAuth2CodeKey              = @"code";

@implementation SHKOAuth2Sharer
@synthesize clientID = clientID_,
clientSecret = clientSecret_,
redirectURI = redirectURI_,
parameters = parameters_,
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
    // Make a string like "cat=fluffy@dog=spot"
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

- (id)init {
    self = [super init];
    if (self) {
        parameters_ = [[NSMutableDictionary alloc] init];
    }
    return self;
}

- (void)dealloc {
    [clientID_ release];
    [clientSecret_ release];
    [redirectURI_ release];
    [parameters_ release];
    [tokenURL_ release];
    [expirationDate_ release];
    [additionalTokenRequestParameters_ release];
    
    [super dealloc];
}

- (void)setKeysForResponseDictionary:(NSDictionary *)dict {
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
    NSDictionary *dict = [self dictionaryWithJSONData:data];
    [self setKeysForResponseDictionary:dict];
}

- (NSDictionary *)dictionaryWithJSONData:(NSData *)data {
    NSMutableDictionary *obj = nil;
    NSError *error = nil;
    
    Class serializer = NSClassFromString(@"NSJSONSerialization");
    if (serializer) {
        const NSUInteger kOpts = (1UL << 0); // NSJSONReadingMutableContainers
        obj = [serializer JSONObjectWithData:data
                                     options:kOpts
                                       error:&error];
#if DEBUG
        if (error) {
            NSString *str = [[[NSString alloc] initWithData:data
                                                   encoding:NSUTF8StringEncoding] autorelease];
            NSLog(@"NSJSONSerialization error %@ parsing %@",
                  error, str);
        }
#endif
        return obj;
    } 
//    else {
//        // try SBJsonParser or SBJSON
//        Class jsonParseClass = NSClassFromString(@"SBJsonParser");
//        if (!jsonParseClass) {
//            jsonParseClass = NSClassFromString(@"SBJSON");
//        }
//        if (jsonParseClass) {
//            GTMOAuth2ParserClass *parser = [[[jsonParseClass alloc] init] autorelease];
//            NSString *jsonStr = [[[NSString alloc] initWithData:data
//                                                       encoding:NSUTF8StringEncoding] autorelease];
//            if (jsonStr) {
//                obj = [parser objectWithString:jsonStr error:&error];
//#if DEBUG
//                if (error) {
//                    NSLog(@"%@ error %@ parsing %@", NSStringFromClass(jsonParseClass),
//                          error, jsonStr);
//                }
//#endif
//                return obj;
//            }
//        } else {
//#if DEBUG
//            NSAssert(0, @"GTMOAuth2Authentication: No parser available");
//#endif
//        }
//    }
    return nil;
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
    NSData *paramData = [paramStr dataUsingEncoding:NSUTF8StringEncoding];
    
    NSURL *tokenURL = self.tokenURL;
    
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
    [self setKeysForResponseJSONData:data];
#if DEBUG
    // Watch for token exchanges that return a non-bearer or unlabeled token
    NSString *tokenType = [self tokenType];
    if (tokenType == nil
        || [tokenType caseInsensitiveCompare:@"bearer"] != NSOrderedSame) {
        NSLog(@"GTMOAuth2: Unexpected token type: %@", tokenType);
    }
#endif    
}


- (void)requestTicket:(OAServiceTicket *)ticket didFailWithError:(NSError*)error{
    
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

@end
