//
//  AUSimplePlayer.m
//  AUSimplePlayer
//
//  Created by Abe on 14/5/9.
//

#import "AUSimplePlayer.h"

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
    AudioUnit EQAU;
    AudioUnit converterAU;
    
    CFArrayRef EQPresetsArray;
    AUPreset currentEQPreset;
}

- (void)dealloc
{
    AUGraphStop(graph);
    AUGraphUninitialize(graph);
    AUGraphClose(graph);
    AudioFileClose(inputFile);
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

    OSStatus status;
    
	// Open the input local audio file
	status = AudioFileOpenURL((__bridge CFURLRef)fileURL, kAudioFileReadPermission, 0, &inputFile);
    NSAssert(status == noErr, @"Audio file open error. status:%d", (int)status);

	// Get the audio data format from the file
	UInt32 propSize = sizeof(inputFormat);
	status = AudioFileGetProperty(inputFile, kAudioFilePropertyDataFormat, &propSize, &inputFormat);
    NSAssert(status == noErr, @"Get audio file data format error. status:%d", (int)status);

	// Build a basic file player->speaker graph
	[self createAUGraphForLocalAudio];

	// Configure the file player
	[self configureFilePlayerNode];
    
    // Get EQ Presets Array
    UInt32 size = sizeof(EQPresetsArray);
    status = AudioUnitGetProperty(EQAU, kAudioUnitProperty_FactoryPresets, kAudioUnitScope_Global, 0, &EQPresetsArray, &size);
    NSAssert(status == noErr, @"Get EQ Presets Array error. status:%d", (int)status);
    
    // Reset EQ
    [self setEQPreset:0];

	// Starting playing
	status = AUGraphStart(graph);
    NSAssert(status == noErr, @"AUGraph start error. status:%d", (int)status);

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

- (void)setEQPreset:(NSInteger)inValue
{
    AUPreset *aPreset = (AUPreset *)CFArrayGetValueAtIndex(EQPresetsArray, inValue);
	OSStatus status = AudioUnitSetProperty(EQAU, kAudioUnitProperty_PresentPreset, kAudioUnitScope_Global, 0, aPreset, sizeof(AUPreset));
    NSAssert(status == noErr, @"selectEQPreset error. status:%d", (int)status);
    
    currentEQPreset = *aPreset;
}

@synthesize currentEQPreset;
@synthesize EQPresetsArray;
@end

@implementation AUSimplePlayer (LocalAudio)

- (void)createAUGraphForLocalAudio
{
    // AUGraph : Input node -> Converter node -> EQ node -> Output node
    
    OSStatus status;
    
	// Create the AUGraph
    status = NewAUGraph(&graph);
    NSAssert(status == noErr, @"New AUGraph error. status:%d", (int)status);

	// Create Nodes
    AUNode outputNode;
    AUNode inputNode;
    AUNode EQNode;
    AUNode converterNode;
    {
        // Create Output AUGraph Node
        AudioComponentDescription outputDescription = {0};
        outputDescription.componentType = kAudioUnitType_Output;
        // Note : On iOS, we need to use kAudioUnitSubType_RemoteIO. On Mac, we can use kAudioUnitSubType_DefaultOutput.
        outputDescription.componentSubType = kAudioUnitSubType_RemoteIO;
        outputDescription.componentManufacturer = kAudioUnitManufacturer_Apple;
        status = AUGraphAddNode(graph, &outputDescription, &outputNode);
        NSAssert(status == noErr, @"AUGraph add output node error. status:%d", (int)status);
        
        // Create Generator AUGraph Node
        AudioComponentDescription inputDescription = {0};
        inputDescription.componentType = kAudioUnitType_Generator;
        inputDescription.componentSubType = kAudioUnitSubType_AudioFilePlayer;
        inputDescription.componentManufacturer = kAudioUnitManufacturer_Apple;
        status = AUGraphAddNode(graph, &inputDescription, &inputNode);
        NSAssert(status == noErr, @"AUGraph add input node error. status:%d", (int)status);
        
        // Create EQ AUGraph Node
        AudioComponentDescription effectEQDescription = {0};
        effectEQDescription.componentType = kAudioUnitType_Effect;
        effectEQDescription.componentSubType = kAudioUnitSubType_AUiPodEQ;
        effectEQDescription.componentManufacturer = kAudioUnitManufacturer_Apple;
        status = AUGraphAddNode(graph, &effectEQDescription, &EQNode);
        NSAssert(status == noErr, @"AUGraph add EQ node error. status:%d", (int)status);
        
        // Create Converter AUGraph Node
        // Fix OSStatus error : -10868 (kAudioUnitErr_FormatNotSupported)
        // See stackoverflow : http://stackoverflow.com/questions/10478565/augraphinitialize-an-error-code-10868-when-adding-kaudiounitsubtype-reverb2-to
        AudioComponentDescription converterDescription = {0};
        converterDescription.componentType = kAudioUnitType_FormatConverter;
        converterDescription.componentSubType = kAudioUnitSubType_AUConverter;
        converterDescription.componentManufacturer = kAudioUnitManufacturer_Apple;
        status = AUGraphAddNode(graph, &converterDescription, &converterNode);
        NSAssert(status == noErr, @"AUGraph add converter node error. status:%d", (int)status);
    }

	// Open the graph
	status = AUGraphOpen(graph);
    NSAssert(status == noErr, @"AUGraph open error. status:%d", (int)status);

	// Get audio unit if we need
    {
        status = AUGraphNodeInfo(graph, inputNode, NULL, &inputAU);
        NSAssert(status == noErr, @"Get input AU error. status:%d", (int)status);
        status = AUGraphNodeInfo(graph, outputNode, NULL, &outputAU);
        NSAssert(status == noErr, @"Get output AU error. status:%d", (int)status);
        status = AUGraphNodeInfo(graph, EQNode, NULL, &EQAU);
        NSAssert(status == noErr, @"Get EQ AU error. status:%d", (int)status);
        status = AUGraphNodeInfo(graph, converterNode, NULL, &converterAU);
        NSAssert(status == noErr, @"Get converter AU error. status:%d", (int)status);
    }

	// Connect Nodes
    {
        status = AUGraphConnectNodeInput(graph, inputNode, 0, converterNode, 0);
        NSAssert(status == noErr, @"AUGraph connect node error. status:%d", (int)status);
        status = AUGraphConnectNodeInput(graph, converterNode, 0, EQNode, 0);
        NSAssert(status == noErr, @"AUGraph connect node error. status:%d", (int)status);
        status = AUGraphConnectNodeInput(graph, EQNode, 0, outputNode, 0);
        NSAssert(status == noErr, @"AUGraph connect node error. status:%d", (int)status);
    }

	// Initialize the AUGraph
	status = AUGraphInitialize(graph);
    NSAssert(status == noErr, @"AUGraph initialize error. status:%d", (int)status);
}

- (void)configureFilePlayerNode
{
    OSStatus status;
    
	// Scheduling an audio file (AudioFileID) with the AUFilePlayer (input node)
	// Tell the file player (input node) to load the audio file we want to play
	status = AudioUnitSetProperty(inputAU, kAudioUnitProperty_ScheduledFileIDs, kAudioUnitScope_Global, 0, &inputFile, sizeof(inputFile));
    NSAssert(status == noErr, @"AU set ScheduledFileIDs error. status:%d", (int)status);

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
	status = AudioUnitSetProperty(inputAU, kAudioUnitProperty_ScheduledFileRegion, kAudioUnitScope_Global, 0, &region, sizeof(region));
    NSAssert(status == noErr, @"AU set ScheduledFileRegion error. status:%d", (int)status);

	// Setting the scheduled start time for AUFilePlayer
	// Tell the file player when to start playing
	AudioTimeStamp startTime;
	memset(&startTime, 0, sizeof(startTime));
	startTime.mFlags = kAudioTimeStampSampleTimeValid;
	startTime.mSampleTime = 0;
	status = AudioUnitSetProperty(inputAU, kAudioUnitProperty_ScheduleStartTimeStamp, kAudioUnitScope_Global, 0, &startTime, sizeof(startTime));
    NSAssert(status == noErr, @"AU set ScheduleStartTimeStamp error. status:%d", (int)status);

	// Calculating file playback time in seconds
	// (total frames / sample frames per second) = total length
	if ([_delegate respondsToSelector:@selector(simplePlayer:updateSongLength:)]) {
		NSTimeInterval songLength = (nPackets * inputFormat.mFramesPerPacket) / inputFormat.mSampleRate;
		[_delegate simplePlayer:self updateSongLength:songLength];
	}
}

@end
