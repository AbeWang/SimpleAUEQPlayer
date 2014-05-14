//
//  KKViewController.m
//  AUSimplePlayer
//
//  Created by Abe on 14/5/9.
//

#import "KKViewController.h"
#import "KKEQListViewController.h"
#import "AUSimplePlayer.h"

@implementation KKViewController

- (void)loadView
{
	[super loadView];

	songLengthLabel.text = @"";

	player = [[AUSimplePlayer alloc] init];
	player.delegate = self;
}

- (IBAction)playSong:(id)sender
{
	if (player.isPlaying) {
		return;
	}

//	[player playWithLocalFileURL:[NSURL fileURLWithPath:@"/Users/abe/Documents/test.mp3"]];
	[player playWithStreamingAudioURL:[NSURL URLWithString:@"http://abe.myftp.org/long_mix.mp3"]];
}

- (IBAction)showEQList:(id)sender
{
    if (player.isPlaying) {
        KKEQListViewController *EQListViewController = [[KKEQListViewController alloc] initWithStyle:UITableViewStylePlain];
		EQListViewController.playerController = self;
        UINavigationController *naviController = [[UINavigationController alloc] initWithRootViewController:EQListViewController];
        [self presentViewController:naviController animated:YES completion:nil];
    }
}

- (IBAction)resume:(id)sender
{
	[player resume];
}

- (IBAction)pause:(id)sender
{
	[player pause];
}

- (IBAction)stop:(id)sender
{
	[player stop];
}

@synthesize player;

#pragma mark AUSimplePlayer Delegates

- (void)simplePlayerDidStartPlaying:(AUSimplePlayer *)inPlayer
{
	NSLog(@"%s", __PRETTY_FUNCTION__);
}
- (void)simplePlayerDidPausePlaying:(AUSimplePlayer *)inPlayer
{
	NSLog(@"%s", __PRETTY_FUNCTION__);
}
- (void)simplePlayerDidResumePlaying:(AUSimplePlayer *)inPlayer
{
	NSLog(@"%s", __PRETTY_FUNCTION__);
}
- (void)simplePlayerDidStopPlaying:(AUSimplePlayer *)inPlayer
{
	NSLog(@"%s", __PRETTY_FUNCTION__);
}
- (void)simplePlayer:(AUSimplePlayer *)inPlayer updateSongLength:(NSTimeInterval)inLength
{
	NSLog(@"%s", __PRETTY_FUNCTION__);
	songLengthLabel.text = [NSString stringWithFormat:@"%f", inLength];
}

@end
