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
- (void)simplePlayerDidResumePlaying:(AUSimplePlayer *)inPlayer;
- (void)simplePlayerDidStopPlaying:(AUSimplePlayer *)inPlayer;
- (void)simplePlayer:(AUSimplePlayer *)inPlayer updateSongLength:(NSTimeInterval)inLength;
@end

@interface AUSimplePlayer : NSObject

- (void)playWithLocalFileURL:(NSURL *)inFileURL;
- (void)playWithStreamingAudioURL:(NSURL *)inAudioURL;

- (void)pause;
- (void)resume;
- (void)stop;

- (BOOL)isPlaying;
- (void)setEQPreset:(NSInteger)inValue;

@property (weak, nonatomic) id<AUSimplePlayerDelegate> delegate;
@property (readonly, nonatomic) CFArrayRef EQPresetsArray;
@property (readonly, nonatomic) AUPreset currentEQPreset;
@end
