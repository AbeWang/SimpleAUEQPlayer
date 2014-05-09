//
//  AUSimplePlayer.m
//  AUSimplePlayer
//
//  Created by Abe on 14/5/9.
//

#import "AUSimplePlayer.h"
#import <AudioToolbox/AudioToolbox.h>

@interface AUSimplePlayer (LocalAudio)
- (void)createAUGraphForLocalAudio;
- (void)configureFilePlayerNode;
@end

@implementation AUSimplePlayer
{
	AudioStreamBasicDescription inputFormat;
	AudioFileID inputFile;
	AUGraph graph;

	AudioUnit inputAU;
	AudioUnit outputAU;
}

+ (AUSimplePlayer *)sharedPlayer
{
	static AUSimplePlayer *simplePlayerInstance = nil;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		simplePlayerInstance = [[AUSimplePlayer alloc] init];
	});

	return simplePlayerInstance;
}

- (void)playLocalFile:(NSURL *)fileURL
{
	if (![[fileURL path] length]) {
		return;
	}

	// Open the input local audio file
	AudioFileOpenURL((__bridge CFURLRef)fileURL, kAudioFileReadPermission, 0, &inputFile);

	// Get the audio data format from the file
	UInt32 propSize = sizeof(inputFormat);
	AudioFileGetProperty(inputFile, kAudioFilePropertyDataFormat, &propSize, &inputFormat);

	// Build a basic file player->speaker graph
	[self createAUGraphForLocalAudio];

	// Configure the file player
	[self configureFilePlayerNode];

	// Starting playing
	AUGraphStart(graph);

	[_delegate simplePlayerDidStartPlaying:self];
}

- (void)play
{
}

- (void)pause
{
}

- (void)stop
{
	// Cleanup
//	AUGraphStop(graph);
//	AUGraphUninitialize(graph);
//	AUGraphClose(graph);
//	AudioFileClose(inputFile);
}

- (BOOL)isPlaying
{
	if (!graph) {
		return NO;
	}

	Boolean isPlaying = false;
	AUGraphIsRunning(graph, &isPlaying);
	return isPlaying;
}

@end

@implementation AUSimplePlayer (LocalAudio)

- (void)createAUGraphForLocalAudio
{
	// Create the AUGraph
	NewAUGraph(&graph);

	// Create Nodes
	// Create Output AUGraph Node
	AudioComponentDescription outputDescription = {0};
	outputDescription.componentType = kAudioUnitType_Output;
	// Note : On iOS, we need to use kAudioUnitSubType_RemoteIO. On Mac, we can use kAudioUnitSubType_DefaultOutput.
	outputDescription.componentSubType = kAudioUnitSubType_RemoteIO;
	outputDescription.componentManufacturer = kAudioUnitManufacturer_Apple;
	AUNode outputNode;
	AUGraphAddNode(graph, &outputDescription, &outputNode);

	// Create Generator AUGraph Node
	AudioComponentDescription inputDescription = {0};
	inputDescription.componentType = kAudioUnitType_Generator;
	inputDescription.componentSubType = kAudioUnitSubType_AudioFilePlayer;
	inputDescription.componentManufacturer = kAudioUnitManufacturer_Apple;
	AUNode inputNode;
	AUGraphAddNode(graph, &inputDescription, &inputNode);

	// Open the graph
	AUGraphOpen(graph);

	// Get audio unit if we need
	AUGraphNodeInfo(graph, inputNode, NULL, &inputAU);
	AUGraphNodeInfo(graph, outputNode, NULL, &outputAU);

	// Connect Nodes
	AUGraphConnectNodeInput(graph, inputNode, 0, outputNode, 0);

	// Initialize the AUGraph
	AUGraphInitialize(graph);
}

- (void)configureFilePlayerNode
{
	// Scheduling an audio file (AudioFileID) with the AUFilePlayer (input node)
	// Tell the file player (input node) to load the audio file we want to play
	AudioUnitSetProperty(inputAU, kAudioUnitProperty_ScheduledFileIDs, kAudioUnitScope_Global, 0, &inputFile, sizeof(inputFile));

	// Setting a ScheduledAudioFileRegion for the AUFilePlayer
	UInt64 nPackets;
	UInt32 propsize = sizeof(nPackets);
	AudioFileGetProperty(inputFile, kAudioFilePropertyAudioDataPacketCount, &propsize, &nPackets);
	// Tell the file player to play the entire file
	ScheduledAudioFileRegion region;
	region.mAudioFile = inputFile;
	region.mLoopCount = 1;
	region.mStartFrame = 0;
	region.mFramesToPlay = (UInt32)(nPackets * inputFormat.mFramesPerPacket);
	region.mCompletionProc = NULL;
	AudioUnitSetProperty(inputAU, kAudioUnitProperty_ScheduledFileRegion, kAudioUnitScope_Global, 0, &region, sizeof(region));

	// Setting the scheduled start time for AUFilePlayer
	// Tell the file player when to start playing
	AudioTimeStamp startTime;
	memset(&startTime, 0, sizeof(startTime));
	startTime.mFlags = kAudioTimeStampSampleTimeValid;
	startTime.mSampleTime = 0;
	AudioUnitSetProperty(inputAU, kAudioUnitProperty_ScheduleStartTimeStamp, kAudioUnitScope_Global, 0, &startTime, sizeof(startTime));

	// Calculating file playback time in seconds
	// (total frames / sample frames per second) = total length
	if ([_delegate respondsToSelector:@selector(simplePlayer:updateSongLength:)]) {
		NSTimeInterval songLength = (nPackets * inputFormat.mFramesPerPacket) / inputFormat.mSampleRate;
		[_delegate simplePlayer:self updateSongLength:songLength];
	}
}

@end
