//
//  main.c
//  SoundTest3
//
//  Created by Sebastian Reinolds on 09/03/2018.
//  Copyright © 2018 Sebastian Reinolds. All rights reserved.
//

#include "Main.h"
#include "Filters.c"
#include "Waveforms.c"

OSStatus OSXAudioUnitCallback(void *inRefCon,
                              AudioUnitRenderActionFlags *ioActionFlags,
                              const AudioTimeStamp *inTimeStamp,
                              u32 inBusNumber,
                              u32 inNumberFrames,
                              AudioBufferList *ioData)
{
    osx_sound_output *SoundOutput = ((osx_sound_output *)inRefCon);
    
    if(SoundOutput->ReadCursor == SoundOutput->WriteCursor)
    {
        SoundOutput->SoundBuffer.SampleCount = 0;
    }
    
    int SampleCount = inNumberFrames;
    if(SoundOutput->SoundBuffer.SampleCount < inNumberFrames)
    {
        SampleCount = SoundOutput->SoundBuffer.SampleCount;
    }
    
    int16 *outputBufferL = (int16 *)ioData->mBuffers[0].mData;
    int16 *outputBufferR = (int16 *)ioData->mBuffers[1].mData;
    
    for (u32 i = 0; i < SampleCount; i++)
    {
        outputBufferL[i] = *SoundOutput->ReadCursor++;
        outputBufferR[i] = *SoundOutput->ReadCursor++;
        
        if((char *)SoundOutput->ReadCursor >= (char *)((char *)SoundOutput->CoreAudioBuffer + SoundOutput->SoundBufferSize))
        {
            SoundOutput->ReadCursor = SoundOutput->CoreAudioBuffer;
        }
    }
    
    for(u32 i = SampleCount; i < inNumberFrames; i++)
    {
        outputBufferL[i] = 0.0;
        outputBufferR[i] = 0.0;
    }
    
    return noErr;
}


void OSXInitCoreAudio(osx_sound_output* SoundOutput)
{
    AudioComponentDescription acd;
    acd.componentType         = kAudioUnitType_Output;
    acd.componentSubType      = kAudioUnitSubType_RemoteIO;
    acd.componentManufacturer = kAudioUnitManufacturer_Apple;
    
    AudioComponent outputComponent = AudioComponentFindNext(NULL, &acd);
    
    AudioComponentInstanceNew(outputComponent, &SoundOutput->AudioUnit);
    AudioUnitInitialize(SoundOutput->AudioUnit);
    
    SoundOutput->AudioDescriptor.mSampleRate       = SoundOutput->SoundBuffer.SamplesPerSecond;
    SoundOutput->AudioDescriptor.mFormatID         = kAudioFormatLinearPCM;
    SoundOutput->AudioDescriptor.mFormatFlags      = kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsNonInterleaved | kAudioFormatFlagIsPacked;
    SoundOutput->AudioDescriptor.mFramesPerPacket  = 1;
    SoundOutput->AudioDescriptor.mChannelsPerFrame = 2;
    SoundOutput->AudioDescriptor.mBitsPerChannel   = sizeof(int16) * 8;
    SoundOutput->AudioDescriptor.mBytesPerFrame    = sizeof(int16); // don't multiply by channel count with non-interleaved!
    SoundOutput->AudioDescriptor.mBytesPerPacket   = SoundOutput->AudioDescriptor.mFramesPerPacket * SoundOutput->AudioDescriptor.mBytesPerFrame;
    
    AudioUnitSetProperty(SoundOutput->AudioUnit,
                         kAudioUnitProperty_StreamFormat,
                         kAudioUnitScope_Input,
                         0,
                         &SoundOutput->AudioDescriptor,
                         sizeof(SoundOutput->AudioDescriptor));
    
    AURenderCallbackStruct cb;
    cb.inputProc = OSXAudioUnitCallback;
    cb.inputProcRefCon = SoundOutput;
    
    AudioUnitSetProperty(SoundOutput->AudioUnit,
                         kAudioUnitProperty_SetRenderCallback,
                         kAudioUnitScope_Global,
                         0,
                         &cb,
                         sizeof(cb));
    
    AudioOutputUnitStart(SoundOutput->AudioUnit);
}


void OSXStopCoreAudio(osx_sound_output* SoundOutput)
{
    AudioOutputUnitStop(SoundOutput->AudioUnit);
    AudioUnitUninitialize(SoundOutput->AudioUnit);
    AudioComponentInstanceDispose(SoundOutput->AudioUnit);
}


void Swap(float *a, float *b)
{
    float Temp = *a;
    *a = *b;
    *b = Temp;
}


void fastFourierTransform(osx_sound_output *SoundOutput)
{
    int ComplexSampleCount = SoundOutput->SoundBuffer.Waveform.FFTSampleCount;
    int ArrayLength = ComplexSampleCount * 2;
    
    float *FFTArray = SoundOutput->SoundBuffer.Waveform.FFTArray;
    
    int j = 0;
    for(int i = 0; i < ComplexSampleCount; i +=2)
    {
        if(j > i)
        {
            Swap(&FFTArray[j], &FFTArray[i]);                         //Swap real part
            //Swap(&FFTArray[j + 1], &FFTArray[i + 1]);               // All zeros
            
            if((j/2) < (ComplexSampleCount / 2))                      // if first half mirror for second half
            {
                Swap(&FFTArray[ArrayLength - (i+2)], &FFTArray[ArrayLength - (j+2)]);
                //Swap(&FFTArray[ArrayLength - (i+2) + 1], &FFTArray[ArrayLength - (j+2) + 1]);     //All zeros
            }
        }
        
        int m = ComplexSampleCount;
        while((m >= 2) && (j >= m))
        {
            j -= m;
            m = m / 2;
        }
        j += m;
    }
    
    int mmax = 2;
    
    while(ArrayLength > mmax)
    {
        int iStep = mmax << 1;
        float theta = (2.0f * M_PI / (float)mmax);   // Make negative for reversefft
        float wtemp = sin(0.5f * theta);
        float wpr = -2.0f * wtemp * wtemp;
        float wpi = sin(theta);
        float wr = 1.0f;
        float wi = 0.0f;
        
        for(int m = 1; m < mmax; m += 2)
        {
            for(int i = m; i < ArrayLength; i += iStep)
            {
                j = i + mmax;
                float tempr = wr * FFTArray[j-1] - wi * FFTArray[j];
                float tempi = wr * FFTArray[j] + wi * FFTArray[j-1];
                FFTArray[j-1] = FFTArray[i-1] - tempr;
                FFTArray[j] = FFTArray[i] - tempi;
                FFTArray[i-1] += tempr;
                FFTArray[i] += tempi;
            }
            wr = (wtemp = wr) * wpr - wi * wpi + wr;
            wi = wi * wpr + wtemp * wpi + wi;
        }
        mmax = iStep;
    }
    
    for(int i = 0; i < ComplexSampleCount; i += 2)
    {
        FFTArray[i/2] = sqrt(FFTArray[i]*FFTArray[i] + FFTArray[i+1]*FFTArray[i+1]);
    }
}


void writeWaveForm(osx_sound_output *SoundOutput, waveform_params WaveformParams)
{
    SoundOutput->SoundBuffer.Waveform.WaveformArrayLength = WaveformParams.wavePeriod;
    s16 *ReadFrom = SoundOutput->SoundBuffer.Samples + WaveformParams.wavePeriod * 2;
    for(int i = 0; i < WaveformParams.wavePeriod; i++)
    {
        *(SoundOutput->SoundBuffer.Waveform.WaveformArray + i) = *ReadFrom;
        
        ReadFrom += 2;
    }
}


void writeFFTSamples(osx_sound_output *SoundOutput)
{
    if(SoundOutput->SoundBuffer.SamplesToWrite > 1024)
    {	
	SoundOutput->SoundBuffer.Waveform.FFTSampleCount = 1024;
    }
    else
    {
	SoundOutput->SoundBuffer.Waveform.FFTSampleCount = 512;
    }
    
    s16 *ReadFrom = SoundOutput->SoundBuffer.Samples;
    float *FFTArray = SoundOutput->SoundBuffer.Waveform.FFTArray;
    
    for(int i = 0; i < SoundOutput->SoundBuffer.Waveform.FFTSampleCount; i++)
    {
        *FFTArray++ = *ReadFrom;
        *FFTArray++ = 0.0f;
        
        ReadFrom += 2;
    }
}


float OSXGetSecondsElapsed(uint64_t Then, uint64_t Now)
{
    static mach_timebase_info_data_t tb;
    
    uint64_t Elapsed = Now - Then;
    
    if (tb.denom == 0)
    {
        // First time we need to get the timebase
        mach_timebase_info(&tb);
    }
    
    uint64_t Nanos = Elapsed * tb.numer / tb.denom;
    float Result = (float)Nanos * 1.0E-9;
    
    return Result;
}

void UpdateBuffer(osx_sound_output *SoundOutput, waveform_params WaveformParams, float ForecastSecondsElapsed)
{
    int Latency;
    if(ForecastSecondsElapsed == 0)
    {
	Latency = (1 / SoundOutput->SoundBuffer.FPS) * SoundOutput->SoundBuffer.SamplesPerSecond;
    }
    else
    {
	Latency = ForecastSecondsElapsed * SoundOutput->SoundBuffer.SamplesPerSecond;
    }

    int PhaseDifference = 0;   
    if(SoundOutput->SoundBuffer.LastWriteCursor != 0)
    {
	SoundOutput->WriteCursor = (SoundOutput->SoundBuffer.LastWriteCursor + (Latency * 2));
    
	if(SoundOutput->WriteCursor > ((char *)SoundOutput->CoreAudioBuffer + SoundOutput->SoundBufferSize))
	{
	    SoundOutput->WriteCursor = (char *)SoundOutput->WriteCursor - SoundOutput->SoundBufferSize;
	}
    
	s16* NewWriteCursor = SoundOutput->WriteCursor;
	if(NewWriteCursor < SoundOutput->SoundBuffer.LastWriteCursor)
	{
	    NewWriteCursor = (char *)NewWriteCursor + SoundOutput->SoundBufferSize;
	}
	int SamplesSinceLastWrite = (NewWriteCursor - SoundOutput->SoundBuffer.LastWriteCursor) / 2;
	PhaseDifference = SamplesSinceLastWrite % WaveformParams.lastWavePeriod;
    }

    s16* SamplesRead = SoundOutput->SoundBuffer.Samples + WaveformParams.wavePeriod;
    SoundOutput->WriteCursor += (WaveformParams.lastWavePeriod - PhaseDifference) * 2;
    SoundOutput->SoundBuffer.LastWriteCursor = SoundOutput->WriteCursor;

    for(int i = 0; i < SoundOutput->SoundBuffer.SamplesToWrite - 4000; i++)
    {	
	if((char *)SoundOutput->WriteCursor >= (char *)SoundOutput->CoreAudioBuffer + SoundOutput->SoundBufferSize)
        {
            SoundOutput->WriteCursor = (char *)SoundOutput->WriteCursor - SoundOutput->SoundBufferSize;
        }

        *SoundOutput->WriteCursor++ = *SamplesRead++;
        *SoundOutput->WriteCursor++ = *SamplesRead++;
    }
}

float WriteSamples(osx_sound_output *SoundOutput)  // Add a write check!!
{
    uint64_t StartTime = mach_absolute_time();
    static uint64_t LastStartTime = 0;
    
    float ForecastSecondsElapsed = 0;
    if(LastStartTime != 0)
    {
        ForecastSecondsElapsed = OSXGetSecondsElapsed(LastStartTime, StartTime);
    }

    SoundOutput->SoundBuffer.SamplesToWrite = 48000;

    static waveform_params WaveformParams = {};
    WaveformParams.lastWavePeriod = WaveformParams.wavePeriod;
    WaveformParams.wavePeriod = SoundOutput->SoundBuffer.SamplesPerSecond / SoundOutput->SoundBuffer.ToneHz;
    
    switch(SoundOutput->SoundBuffer.WaveformType)
    {
        case Sine:
            writeSineWave(SoundOutput, &WaveformParams);
            break;
        case Square:
            writeSquareWave(SoundOutput, &WaveformParams);
            break;
        case Sawtooth:
            writeSawtoothWave(SoundOutput, &WaveformParams);
            break;
        case Triangle:
            writeTriangleWave(SoundOutput, &WaveformParams);
            break;
        case Noise:
            writeNoise(SoundOutput, &WaveformParams);
            break;
        default:
            writeSineWave(SoundOutput, &WaveformParams);
    }
    
    UpdateBuffer(SoundOutput, WaveformParams, ForecastSecondsElapsed);
    
    writeWaveForm(SoundOutput, WaveformParams);
    writeFFTSamples(SoundOutput);
    fastFourierTransform(SoundOutput);

    uint64_t EndTime = mach_absolute_time();

    float WriteSamplesTime = OSXGetSecondsElapsed(StartTime, EndTime);
    
    LastStartTime = StartTime;

    return WriteSamplesTime;
}


osx_sound_output * SetupAndRun(void)
{
    static sound_output_buffer SoundBuffer = {};
    static osx_sound_output SoundOutput = {};
    SoundOutput.SoundBuffer = SoundBuffer;
    SoundOutput.SoundBuffer.SamplesPerSecond = 48000;
    SoundOutput.SoundBuffer.SampleCount = 48000 * 2;
    SoundOutput.SoundBuffer.ToneHz = 440;
    SoundOutput.SoundBuffer.Gain = 1000;
    SoundOutput.SoundBuffer.FilterFrequency = 1000;
    SoundOutput.SoundBuffer.Q = 1;
    SoundOutput.SoundBuffer.TimeInterval = 1.0f / 48000.0f;
    SoundOutput.SoundBufferSize = 48000 * 2 * sizeof(int16_t) * 2;
    
    SoundOutput.SoundBuffer.Samples = (int16_t *)mmap(0, SoundOutput.SoundBufferSize, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANON, -1, 0);
    if(SoundOutput.SoundBuffer.Samples == MAP_FAILED)
    {
        
    }
    memset(SoundOutput.SoundBuffer.Samples, 0,  SoundOutput.SoundBufferSize);
    
    SoundOutput.CoreAudioBuffer = (int16_t *)mmap(0, SoundOutput.SoundBufferSize, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANON, -1, 0);
    if(SoundOutput.CoreAudioBuffer == MAP_FAILED)
    {
        
    }
    memset(SoundOutput.CoreAudioBuffer, 0,  SoundOutput.SoundBufferSize);
    
    int WaveformArrayMaxSize = 1024;
    SoundOutput.SoundBuffer.Waveform.WaveformArray = (int16_t *)mmap(0, WaveformArrayMaxSize, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANON, -1, 0);
    if(SoundOutput.SoundBuffer.Waveform.WaveformArray == MAP_FAILED)
    {
        
    }
    memset(SoundOutput.SoundBuffer.Waveform.WaveformArray, 0,  WaveformArrayMaxSize);
    
    SoundOutput.SoundBuffer.Waveform.FFTArray = (float *)mmap(0, WaveformArrayMaxSize * 2 * sizeof(float), PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANON, -1, 0);
    if(SoundOutput.SoundBuffer.Waveform.FFTArray == MAP_FAILED)
    {
        
    }
    memset(SoundOutput.SoundBuffer.Waveform.FFTArray, 0,  WaveformArrayMaxSize);
    
    SoundOutput.ReadCursor = SoundOutput.CoreAudioBuffer;
    SoundOutput.WriteCursor = SoundOutput.CoreAudioBuffer;
    
    OSXInitCoreAudio(&SoundOutput);
        
    return &SoundOutput;
}
