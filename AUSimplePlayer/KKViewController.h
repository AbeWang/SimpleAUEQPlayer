//
//  KKViewController.h
//  AUSimplePlayer
//
//  Created by Abe on 14/5/9.
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
