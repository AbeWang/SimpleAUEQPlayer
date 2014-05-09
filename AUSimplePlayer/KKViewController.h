//
//  KKViewController.h
//  AUSimplePlayer
//
//  Created by Abe on 14/5/9.
//  Copyright (c) 2014年 KKBOX. All rights reserved.
//

#import "AUSimplePlayer.h"

@interface KKViewController : UIViewController
<AUSimplePlayerDelegate>
{
	IBOutlet UIButton *playButton;
	IBOutlet UILabel *songLengthLabel;
}

- (IBAction)playSong:(id)sender;

@end
