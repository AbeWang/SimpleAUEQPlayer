//
//  KKAppDelegate.m
//  AUSimplePlayer
//
//  Created by Abe on 14/5/9.
//

#import "KKAppDelegate.h"
#import <AVFoundation/AVFoundation.h>

@implementation KKAppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
	NSError *setCategoryErr = nil;
	NSError *activationErr = nil;
	[[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayback error:&setCategoryErr];
	[[AVAudioSession sharedInstance] setActive:YES error:&activationErr];
    
    return YES;
}

- (void)applicationWillResignActive:(UIApplication *)application
{
}

- (void)applicationDidEnterBackground:(UIApplication *)application
{
}

- (void)applicationWillEnterForeground:(UIApplication *)application
{
}

- (void)applicationDidBecomeActive:(UIApplication *)application
{
}

- (void)applicationWillTerminate:(UIApplication *)application
{
}

@end
