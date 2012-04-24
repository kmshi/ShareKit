//
//  SHKOAuth2Sharer.h
//  ShareKit
//
//  Created by kshi on 12-4-23.
//  Copyright (c) 2012年 __MyCompanyName__. All rights reserved.
//  The source was copied from GoogleOAuth2, please ref:
//  https://github.com/papaver/GoogleOAuth2ObjectiveC/blob/master/Source/GTMOAuth2Authentication.m
//

#import "SHKSharer.h"
#import "SHKOAuthView.h"
#import "OAuthConsumer.h"

@interface SHKOAuth2Sharer : SHKSharer{
@private
    NSString *clientID_;
    NSString *clientSecret_;
    NSString *redirectURI_;
    NSMutableDictionary *parameters_;
    
    // authorization parameters
    NSURL *authorizationURL_;
    NSURL *tokenURL_;
    NSDate *expirationDate_;
    
    NSDictionary *additionalTokenRequestParameters_;
}

// OAuth2 standard protocol parameters
//
// These should be the plain strings; any needed escaping will be provided by
// the library.

// Request properties
@property (copy) NSString *clientID;
@property (copy) NSString *clientSecret;
@property (copy) NSString *redirectURI;
@property (copy) NSString *scope;
@property (copy) NSString *tokenType;

// Apps may optionally add parameters here to be provided to the token
// endpoint on token requests and refreshes, like live.com use https://oauth.live.com/desktop 
// as redirect_uri for mobile token refresh
@property (retain) NSDictionary *additionalTokenRequestParameters;

// Response properties
@property (retain) NSMutableDictionary *parameters;

@property (retain) NSString *accessToken;
@property (retain) NSString *refreshToken;
@property (retain) NSNumber *expiresIn;
@property (retain) NSString *code;
@property (retain) NSString *errorString;

// URL for obtaining access tokens
@property (copy) NSURL *authorizationURL;
@property (copy) NSURL *tokenURL;

// Calculated expiration date (expiresIn seconds added to the
// time the access token was received.)
@property (copy) NSDate *expirationDate;

#pragma mark Utility Routines
+ (NSString *)encodedOAuthValueForString:(NSString *)str;
+ (NSString *)encodedQueryParametersForDictionary:(NSDictionary *)dict;

+ (void)deleteStoredRefreshToken;
+ (void)logout;

- (void)setKeysForResponseDictionary:(NSDictionary *)dict;
- (void)setKeysForResponseJSONData:(NSData *)data;

- (void)tokenAuthorize;
- (void)tokenAccess;
- (void)requestTicket:(OAServiceTicket *)ticket didFinishWithData:(NSData *)data;
- (void)requestTicket:(OAServiceTicket *)ticket didFailWithError:(NSError*)error;

- (void)storeRefreshToken;
- (BOOL)restoreRefreshToken;
- (BOOL)shouldRefreshAccessToken;
- (void)refreshAccessToken;

@end
