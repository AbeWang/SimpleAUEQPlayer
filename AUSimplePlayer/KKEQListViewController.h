//
//  KKEQListViewController.h
//  AUSimplePlayer
//
//  Created by Abe on 2014/5/12.
//

#import "KKViewController.h"

@interface KKEQListViewController : UITableViewController
{
	__weak KKViewController *playerController;
}

@property (weak, nonatomic) KKViewController *playerController;
@end
