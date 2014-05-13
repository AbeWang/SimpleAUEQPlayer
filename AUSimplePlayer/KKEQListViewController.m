//
//  KKEQListViewController.m
//  AUSimplePlayer
//
//  Created by Abe on 2014/5/12.
//

#import "KKEQListViewController.h"
#import "AUSimplePlayer.h"

@implementation KKEQListViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.title = @"EQ List";
    
    UIBarButtonItem *closeItem = [[UIBarButtonItem alloc] initWithTitle:@"Close" style:UIBarButtonItemStyleDone target:self action:@selector(close:)];
    self.navigationItem.leftBarButtonItem = closeItem;
}

- (IBAction)close:(id)sender
{
    [self dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return [(NSArray *)[[playerController player] EQPresetsArray] count];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    static NSString *CellIdentifier = @"CellIdentifier";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:CellIdentifier];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:CellIdentifier];
    }
    
    AUPreset *aPreset = (AUPreset *)CFArrayGetValueAtIndex([[playerController player] EQPresetsArray], indexPath.row);
    cell.textLabel.text = (__bridge NSString *)aPreset->presetName;
    NSString *currentEQPreset = (__bridge NSString *)[[playerController player] currentEQPreset].presetName;
    cell.accessoryType = ([cell.textLabel.text isEqualToString:currentEQPreset]) ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [[playerController player] setEQPreset:indexPath.row];
    [self close:nil];
}

@synthesize playerController;
@end
