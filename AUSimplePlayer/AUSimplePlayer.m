//
//  AUSimplePlayer.m
//  AUSimplePlayer
//
//  Created by Abe on 14/5/9.
//

#import "AUSimplePlayer.h"

#pragma mark - Callback Functions

void AudioFileStreamPropertyListenerCallback(void * inClientData, AudioFileStreamID inAudioFileStream, AudioFileStreamPropertyID inPropertyID, UInt32 * ioFlags);

void AudioFileStreamPacketsCallback(void *inClientData, UInt32 inNumberBytes, UInt32 inNumberPackets, const void * inInputData, AudioStreamPacketDescription *inPacketDescriptions);

OSStatus PlaybackCallback(void *userData, AudioUnitRenderActionFlags *ioActionFlags, const AudioTimeStamp *inTimeStamp, UInt32 inBusNumber, UInt32 inNumberFrames, AudioBufferList *ioData);

OSStatus AudioConverterFiller(AudioConverterRef inAudioConverter, UInt32* ioNumberDataPackets, AudioBufferList* ioData, AudioStreamPacketDescription** outDataPacketDescription, void* inUserData);

#pragma mark - LinearPCMStreamDescription

AudioStreamBasicDescription PCMStreamDescription()
{
	AudioStreamBasicDescription format = {0};
	format.mSampleRate = 44100.0;
	format.mFormatID = kAudioFormatLinearPCM;
	format.mFormatFlags = kLinearPCMFormatFlagIsSignedInteger;
	format.mBitsPerChannel = 16;
	format.mChannelsPerFrame = 2;
	format.mBytesPerFrame = 4;
	format.mFramesPerPacket = 1;
	format.mBytesPerPacket = format.mFramesPerPacket * format.mBytesPerFrame;
	return format;
}

#pragma mark - AUSimplePlayer (StreamingAudio)

@interface AUSimplePlayer (StreamingAudio)
- (void)createAUGraph;
- (double)framePerSecond;
- (OSStatus)_enqueueDataWithPacketsCount:(UInt32)inPacketCount ioData:(AudioBufferList *)ioData;
- (void)_storePacketsWithNumberOfBytes:(UInt32)inNumberBytes numberOfPackets:(UInt32)inNumberPackets inputData:(const void *)inInputData packetDescriptions:(AudioStreamPacketDescription *)inPacketDescriptions;
- (void)_createAudioConverterWithAudioStreamDescription:(AudioStreamBasicDescription *)audioStreamBasicDescription;
- (OSStatus)_fillConverterBufferWithBufferlist:(AudioBufferList *)ioData packetDescription:(AudioStreamPacketDescription** )outDataPacketDescription;
@end

#pragma mark - AUSimplePlayer (LocalAudio)

@interface AUSimplePlayer (LocalAudio)
- (void)createAUGraphForLocalAudio;
- (void)configureFilePlayerNode;
@end

#pragma mark - AUSimplePlayer

typedef struct {
	size_t length;
	void *data;
} AUPacketData;

@implementation AUSimplePlayer
{
    AudioStreamBasicDescription streamDescription;

	AudioFileID inputFile;
    AudioFileStreamID audioFileStreamID;
    
	AUGraph graph;

	AudioUnit inputAU;
	AudioUnit outputAU;
    AudioUnit converterAU;
    AudioUnit EQAU;
    
    CFArrayRef EQPresetsArray;
    AUPreset currentEQPreset;

	NSURLConnection *URLConnection;

	size_t packetCount;
	size_t maxPacketCount;
    size_t readHead;

	AUPacketData *packetData;

	AudioBufferList *list;
	size_t renderBufferSize;
    
    AudioConverterRef converter;
}

- (void)dealloc
{
    AudioFileClose(inputFile);
    AudioFileStreamClose(audioFileStreamID);
    
    AUGraphStop(graph);
	AUGraphUninitialize(graph);
	AUGraphClose(graph);
    
    CFRelease(EQPresetsArray);
    
    AudioConverterReset(converter);
}

- (void)playWithLocalFileURL:(NSURL *)inFileURL
{
	if ([self isPlaying]) {
		return;
	}

	if (![[inFileURL path] length]) {
		return;
	}

    OSStatus status;

	// Open the input local audio file
	status = AudioFileOpenURL((__bridge CFURLRef)inFileURL, kAudioFileReadPermission, 0, &inputFile);
    NSAssert(status == noErr, @"Audio file open error. status:%d", (int)status);

	// Get the audio data format from the file
	UInt32 propSize = sizeof(streamDescription);
	status = AudioFileGetProperty(inputFile, kAudioFilePropertyDataFormat, &propSize, &streamDescription);
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

- (void)playWithStreamingAudioURL:(NSURL *)inAudioURL
{
	packetCount = 0;
	maxPacketCount = 20480;

	packetData = (AUPacketData *)calloc(maxPacketCount, sizeof(AUPacketData));

	UInt32 second = 5;
	UInt32 packetSize = 44100 * second * 8;
	renderBufferSize = packetSize;

	list = (AudioBufferList *)calloc(1, sizeof(AudioBuffer) + sizeof(UInt32));
	list->mNumberBuffers = 1;
	list->mBuffers[0].mNumberChannels = 2;
	list->mBuffers[0].mDataByteSize = packetSize;
	list->mBuffers[0].mData = calloc(1, packetSize);

	[self createAUGraph];
    
    OSStatus status;
    
    // Get EQ Presets Array
    UInt32 size = sizeof(EQPresetsArray);
    status = AudioUnitGetProperty(EQAU, kAudioUnitProperty_FactoryPresets, kAudioUnitScope_Global, 0, &EQPresetsArray, &size);
    NSAssert(status == noErr, @"Get EQ Presets Array error. status:%d", (int)status);
    
    // Reset EQ
    [self setEQPreset:0];

    status = AudioFileStreamOpen((__bridge void *)(self), AudioFileStreamPropertyListenerCallback, AudioFileStreamPacketsCallback, kAudioFileMP3Type, &audioFileStreamID);
    NSAssert(status == noErr, @"AudioFileStream open error. status:%d", (int)status);
    
    URLConnection = [[NSURLConnection alloc] initWithRequest:[NSURLRequest requestWithURL:inAudioURL] delegate:self];
}

- (void)resume
{
	if (!self.isPlaying) {
		AUGraphStart(graph);
        [_delegate simplePlayerDidResumePlaying:self];
	}
}

- (void)pause
{
	if (self.isPlaying) {
		AUGraphStop(graph);
        [_delegate simplePlayerDidPausePlaying:self];
	}
}

- (void)stop
{
	AUGraphStop(graph);
	AUGraphUninitialize(graph);
	AUGraphClose(graph);
	AudioFileClose(inputFile);
    AudioFileStreamClose(audioFileStreamID);
    AudioConverterReset(converter);
    
    [_delegate simplePlayerDidStopPlaying:self];
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
    NSAssert(status == noErr, @"setEQPreset error. status:%d", (int)status);
    
    currentEQPreset = *aPreset;
}

#pragma mark - NSURLConnection delegates

- (void)connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)response
{
	if ([response isKindOfClass:[NSHTTPURLResponse class]]) {
		if ([(NSHTTPURLResponse *)response statusCode] != 200) {
			[connection cancel];
		}
	}
}

- (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data
{
    AudioFileStreamParseBytes(audioFileStreamID, (UInt32)[data length], [data bytes], 0);
}

- (void)connectionDidFinishLoading:(NSURLConnection *)connection
{
}

- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error
{
}

@synthesize currentEQPreset;
@synthesize EQPresetsArray;
@end

#pragma mark - AUSimplePlayer (StreamingAudio)

@implementation AUSimplePlayer (StreamingAudio)

- (void)createAUGraph
{
	OSStatus status;

	status = NewAUGraph(&graph);
	NSAssert(status == noErr, @"New AUGraph error. status:%d", (int)status);

	AUNode outputNode;
	AudioComponentDescription outputDescription = {0};
	outputDescription.componentType = kAudioUnitType_Output;
	outputDescription.componentSubType = kAudioUnitSubType_RemoteIO;
	outputDescription.componentManufacturer = kAudioUnitManufacturer_Apple;
	status = AUGraphAddNode(graph, &outputDescription, &outputNode);
	NSAssert(status == noErr, @"Add output node error. status:%d", (int)status);
    
    AUNode EQNode;
    AudioComponentDescription effectEQDescription = {0};
    effectEQDescription.componentType = kAudioUnitType_Effect;
    effectEQDescription.componentSubType = kAudioUnitSubType_AUiPodEQ;
    effectEQDescription.componentManufacturer = kAudioUnitManufacturer_Apple;
    status = AUGraphAddNode(graph, &effectEQDescription, &EQNode);
    NSAssert(status == noErr, @"AUGraph add EQ node error. status:%d", (int)status);
    
    AUNode converterNode;
    AudioComponentDescription converterDescription = {0};
    converterDescription.componentType = kAudioUnitType_FormatConverter;
    converterDescription.componentSubType = kAudioUnitSubType_AUConverter;
    converterDescription.componentManufacturer = kAudioUnitManufacturer_Apple;
    status = AUGraphAddNode(graph, &converterDescription, &converterNode);
    NSAssert(status == noErr, @"AUGraph add converter node error. status:%d", (int)status);

	status = AUGraphOpen(graph);
	NSAssert(status == noErr, @"AUGraph open error. status:%d", (int)status);
    
    status = AUGraphConnectNodeInput(graph, converterNode, 0, EQNode, 0);
    NSAssert(status == noErr, @"AUGraph connect node error. status:%d", (int)status);
    status = AUGraphConnectNodeInput(graph, EQNode, 0, outputNode, 0);
    NSAssert(status == noErr, @"AUGraph connect node error. status:%d", (int)status);

	status = AUGraphNodeInfo(graph, outputNode, &outputDescription, &outputAU);
	NSAssert(status == noErr, @"Get output node error. status:%d", (int)status);
    status = AUGraphNodeInfo(graph, EQNode, &effectEQDescription, &EQAU);
	NSAssert(status == noErr, @"Get output node error. status:%d", (int)status);
    status = AUGraphNodeInfo(graph, converterNode, &converterDescription, &converterAU);
	NSAssert(status == noErr, @"Get output node error. status:%d", (int)status);

	AudioStreamBasicDescription format = PCMStreamDescription();
	status = AudioUnitSetProperty(converterAU, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 0, &format, sizeof(format));
	NSAssert(status == noErr, @"Set stream format error. status:%d", (int)status);

	AURenderCallbackStruct inputCallbackStruct;
	inputCallbackStruct.inputProc = PlaybackCallback;
	inputCallbackStruct.inputProcRefCon = (__bridge void *)(self);
	status = AudioUnitSetProperty(converterAU, kAudioUnitProperty_SetRenderCallback, kAudioUnitScope_Input, 0, &inputCallbackStruct, sizeof(inputCallbackStruct));
	NSAssert(status == noErr, @"Set RenderCallback error. status:%d", (int)status);

	status = AUGraphInitialize(graph);
	NSAssert(status == noErr, @"AUGraph initialize error. status:%d", (int)status);
}

- (OSStatus)_enqueueDataWithPacketsCount:(UInt32)inPacketCount ioData:(AudioBufferList *)ioData
{
    OSStatus status = -1;
    
    @synchronized(self) {
        @autoreleasepool {
            UInt32 packetSize = inPacketCount;
            status = AudioConverterFillComplexBuffer(converter, AudioConverterFiller, (__bridge void *)(self), &packetSize, list, NULL);
            if (status != noErr || !packetSize) {
                AUGraphStop(graph);
                AudioConverterReset(self->converter);
                list->mNumberBuffers = 1;
                list->mBuffers[0].mNumberChannels = 2;
                list->mBuffers[0].mDataByteSize = (UInt32)renderBufferSize;
                bzero(list->mBuffers[0].mData, renderBufferSize);
            }
			else if (self.isPlaying) {
				ioData->mNumberBuffers = 1;
				ioData->mBuffers[0].mNumberChannels = 2;
				ioData->mBuffers[0].mData = self->list->mBuffers[0].mData;
				ioData->mBuffers[0].mDataByteSize = self->list->mBuffers[0].mDataByteSize;
				list->mBuffers[0].mDataByteSize = (UInt32)renderBufferSize;
				status = noErr;
			}
        }
    }
    
	return status;
}

- (void)_storePacketsWithNumberOfBytes:(UInt32)inNumberBytes numberOfPackets:(UInt32)inNumberPackets inputData:(const void *)inInputData packetDescriptions:(AudioStreamPacketDescription *)inPacketDescriptions
{
    for (int i = 0; i < inNumberPackets; ++i) {
        SInt64 packetStart = inPacketDescriptions[i].mStartOffset;
        UInt32 packetSize = inPacketDescriptions[i].mDataByteSize;
        packetData[packetCount].data = malloc(packetSize);
        packetData[packetCount].length = (size_t)packetSize;
        memcpy(packetData[packetCount].data, inInputData + packetStart, packetSize);
        packetCount++;
    }
    
    if (readHead == 0 && packetCount > (int)([self framePerSecond] * 12)) {
		if (!self.isPlaying) {
			AudioConverterReset(converter);
			OSStatus status = AUGraphStart(graph);
			NSAssert(status == noErr, @"AUGraph Start error. status:%d", (int)status);
            [_delegate simplePlayerDidStartPlaying:self];
		}
    }
}

- (void)_createAudioConverterWithAudioStreamDescription:(AudioStreamBasicDescription *)audioStreamBasicDescription
{
    memcpy(&streamDescription, audioStreamBasicDescription, sizeof(AudioStreamBasicDescription));
    
    AudioStreamBasicDescription format = PCMStreamDescription();
    AudioConverterNew(audioStreamBasicDescription, &format, &converter);
}

- (OSStatus)_fillConverterBufferWithBufferlist:(AudioBufferList *)ioData packetDescription:(AudioStreamPacketDescription** )outDataPacketDescription
{
	static AudioStreamPacketDescription aspdesc;

	ioData->mNumberBuffers = 1;
	void *data = packetData[readHead].data;
	UInt32 length = (UInt32)packetData[readHead].length;
	ioData->mBuffers[0].mData = data;
	ioData->mBuffers[0].mDataByteSize = length;

	readHead++;

	*outDataPacketDescription = &aspdesc;
	aspdesc.mDataByteSize = length;
	aspdesc.mStartOffset = 0;
	aspdesc.mVariableFramesInPacket = 1;
    
	return noErr;
}

- (double)framePerSecond
{
    if (streamDescription.mFramesPerPacket) {
        return streamDescription.mSampleRate / streamDescription.mFramesPerPacket;
    }
    return 44100.0 / 1152.0;
}

@end

#pragma mark - AUSimplePlayer (LocalAudio)

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
	region.mFramesToPlay = (UInt32)(nPackets * streamDescription.mFramesPerPacket);
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
    NSTimeInterval songLength = (nPackets * streamDescription.mFramesPerPacket) / streamDescription.mSampleRate;
    [_delegate simplePlayer:self updateSongLength:songLength];
}

@end

#pragma mark - Callback Functions

OSStatus PlaybackCallback(void *userData, AudioUnitRenderActionFlags *ioActionFlags, const AudioTimeStamp *inTimeStamp, UInt32 inBusNumber, UInt32 inNumberFrames, AudioBufferList *ioData)
{
    AUSimplePlayer *self = (__bridge AUSimplePlayer *)userData;
    return [self _enqueueDataWithPacketsCount:inNumberFrames ioData:ioData];
}

void AudioFileStreamPropertyListenerCallback(void * inClientData, AudioFileStreamID inAudioFileStream, AudioFileStreamPropertyID inPropertyID, UInt32 * ioFlags)
{
    AUSimplePlayer *self = (__bridge AUSimplePlayer *)inClientData;
    
    if (inPropertyID == kAudioFileStreamProperty_DataFormat) {
        OSStatus status = 0;
        AudioStreamBasicDescription audioStreamDescription;
        UInt32 dataSize	= 0;
        Boolean writable = false;
		status = AudioFileStreamGetPropertyInfo(inAudioFileStream, kAudioFileStreamProperty_DataFormat, &dataSize, &writable);
        status = AudioFileStreamGetProperty(inAudioFileStream, kAudioFileStreamProperty_DataFormat, &dataSize, &audioStreamDescription);
        [self _createAudioConverterWithAudioStreamDescription:&audioStreamDescription];
    }
}

void AudioFileStreamPacketsCallback(void * inClientData, UInt32 inNumberBytes, UInt32 inNumberPackets, const void * inInputData, AudioStreamPacketDescription *inPacketDescriptions)
{
    AUSimplePlayer *self = (__bridge AUSimplePlayer *)inClientData;
    [self _storePacketsWithNumberOfBytes:inNumberBytes numberOfPackets:inNumberPackets inputData:inInputData packetDescriptions:inPacketDescriptions];
}

OSStatus AudioConverterFiller(AudioConverterRef inAudioConverter, UInt32* ioNumberDataPackets, AudioBufferList* ioData, AudioStreamPacketDescription** outDataPacketDescription, void* inUserData)
{
    AUSimplePlayer *self = (__bridge AUSimplePlayer *)inUserData;
	*ioNumberDataPackets = 1;
	[self _fillConverterBufferWithBufferlist:ioData packetDescription:outDataPacketDescription];
	return noErr;
}
