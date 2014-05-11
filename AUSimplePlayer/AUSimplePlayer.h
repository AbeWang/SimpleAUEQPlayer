//
//  AUSimplePlayer.h
//  AUSimplePlayer
//
//  Created by Abe on 14/5/9.
//

#import <AudioToolbox/AudioToolbox.h>

@class AUSimplePlayer;

@protocol AUSimplePlayerDelegate <NSObject>
- (void)simplePlayerDidStartPlaying:(AUSimplePlayer *)inPlayer;
- (void)simplePlayerDidPausePlaying:(AUSimplePlayer *)inPlayer;
- (void)simplePlayerDidStopPlaying:(AUSimplePlayer *)inPlayer;
- (void)simplePlayer:(AUSimplePlayer *)inPlayer updateSongLength:(NSTimeInterval)inLength;
@end

@interface AUSimplePlayer : NSObject

+ (AUSimplePlayer *)sharedPlayer;

- (void)playLocalFile:(NSURL *)fileURL;

- (void)play;
- (void)pause;
- (void)stop;

- (BOOL)isPlaying;
- (void)setEQPreset:(NSInteger)inValue;

@property (weak, nonatomic) id<AUSimplePlayerDelegate> delegate;
@property (readonly, nonatomic) CFArrayRef EQPresetsArray;
@property (readonly, nonatomic) AUPreset currentEQPreset;
@end
