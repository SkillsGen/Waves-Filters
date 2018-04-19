//
//  main.cpp
//  SoundTest3
//
//  Created by Sebastian Reinolds on 09/03/2018.
//  Copyright © 2018 Sebastian Reinolds. All rights reserved.
//

#include "Main.h"

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

    for(int i = 1; i < ArrayLength; i += 2)
    {
	Assert(FFTArray[i] == 0);	
    }

    
    int j = 0;
    for(int i = 0; i < ComplexSampleCount; i +=2)
    {
        if(j > i)
        {
            Swap(&FFTArray[j], &FFTArray[i]);                         //Swap real part
            //Swap(&FFTArray[j + 1], &FFTArray[i + 1]);               // Don't need to swap complex part
            
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
        float theta = (2.0f * pi32 / (float)mmax);   // Make negative for reversefft
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
    s16 *ReadFrom = WaveformParams.StartOfWaveform;
    for(int i = 0; i < WaveformParams.wavePeriod; i++)
    {
	*(SoundOutput->SoundBuffer.Waveform.WaveformArray + i) = *ReadFrom;

	ReadFrom += 2;

	if(ReadFrom > SoundOutput->CoreAudioBuffer + SoundOutput->SoundBufferSize)
	{
	    ReadFrom -= SoundOutput->SoundBufferSize;
	}
    }
}


void writeFFTSamples(osx_sound_output *SoundOutput)
{
    SoundOutput->SoundBuffer.Waveform.FFTSampleCount = 512;
    s16 *ReadFrom = SoundOutput->ReadCursor - (SoundOutput->SoundBuffer.Waveform.FFTSampleCount * 2);
    float *FFTArray = SoundOutput->SoundBuffer.Waveform.FFTArray;
    
    if(ReadFrom < SoundOutput->CoreAudioBuffer)
    {
        ReadFrom += SoundOutput->SoundBufferSize;
    }
    
    for(int i = 0; i < SoundOutput->SoundBuffer.Waveform.FFTSampleCount; i++)
    {
	*FFTArray++ = *ReadFrom;
	*FFTArray++ = 0.0f;

	ReadFrom += 2;

	if(ReadFrom >= SoundOutput->CoreAudioBuffer + SoundOutput->SoundBufferSize)
	{
	    ReadFrom -= SoundOutput->SoundBufferSize;
	}
    }
}

//     Basic Filter Outline
//     y[n] = (b0/a0)*x[n] + (b1/a0)*x[n-1] + (b2/a0)*x[n-2] - (a1/a0)*y[n-1] - (a2/a0)*y[n-2]

int16 BiQuadLowPassFilter(int unfilteredValue, osx_sound_output *SoundOutput, filter_params *FilterParams)
{
    if(!FilterParams->isInitaliased ||
       FilterParams->FilterFrequency != SoundOutput->SoundBuffer.FilterFrequency ||
       FilterParams->Q != SoundOutput->SoundBuffer.Q)
    {
	FilterParams->FilterFrequency = SoundOutput->SoundBuffer.FilterFrequency;
        FilterParams->Q = SoundOutput->SoundBuffer.Q;
            
	FilterParams->w0 = 2.0f * pi32 * ((float)FilterParams->FilterFrequency /
					  SoundOutput->SoundBuffer.SamplesPerSecond);
	FilterParams->cosw0 = cos(FilterParams->w0);
	FilterParams->sinw0 = sin(FilterParams->w0);

	FilterParams->alpha = FilterParams->sinw0 / (2 * FilterParams->Q);
        FilterParams->a0 = 1 + FilterParams->alpha;
        FilterParams->a1 = -2 * FilterParams->cosw0;
        FilterParams->a2 = 1 - FilterParams->alpha;
	
	//b values only change if filter freq changes
	FilterParams->b0 = (1 - FilterParams->cosw0) / 2;
	FilterParams->b1 = 1 - FilterParams->cosw0;
	FilterParams->b2 = FilterParams->b0;
          
	FilterParams->isInitaliased = true;
    }
    
    int16 FilteredValue = ((FilterParams->b0 / FilterParams->a0) * unfilteredValue) +
                          ((FilterParams->b1 / FilterParams->a0) * FilterParams->unFilterednMinus1) +
                          ((FilterParams->b2 / FilterParams->a0) * FilterParams->unFilterednMinus2) -
                          ((FilterParams->a1 / FilterParams->a0) * FilterParams->FilterednMinus1) -
                          ((FilterParams->a2 / FilterParams->a0) * FilterParams->FilterednMinus2);
    
    FilterParams->unFilterednMinus2 = FilterParams->unFilterednMinus1;
    FilterParams->unFilterednMinus1 = unfilteredValue;
    
    FilterParams->FilterednMinus2 = FilterParams->FilterednMinus1;
    FilterParams->FilterednMinus1 = FilteredValue;
    
    return FilteredValue;
}

int16 BiQuadHighPassFilter(int unfilteredValue, osx_sound_output *SoundOutput, filter_params *FilterParams)
{
    filter_type FilterType = BiQuadHighPass;
    if(!FilterParams->isInitaliased ||
       FilterParams->FilterFrequency != SoundOutput->SoundBuffer.FilterFrequency ||
       FilterParams->Q != SoundOutput->SoundBuffer.Q ||
       FilterParams->FilterType != FilterType)
    {
	FilterParams->FilterType = FilterType;
	FilterParams->FilterFrequency = SoundOutput->SoundBuffer.FilterFrequency;
	FilterParams->Q = SoundOutput->SoundBuffer.Q;

	FilterParams->w0 = 2.0f * pi32 * ((float)FilterParams->FilterFrequency /
					  SoundOutput->SoundBuffer.SamplesPerSecond);
	FilterParams->cosw0 = cos(FilterParams->w0);
	FilterParams->sinw0 = sin(FilterParams->w0);

	FilterParams->alpha = FilterParams->sinw0 / (2 * FilterParams->Q);
	FilterParams->a0 = 1 + FilterParams->alpha;
	FilterParams->a1 = -2 * FilterParams->cosw0;
	FilterParams->a2 = 1 - FilterParams->alpha;
      
	//b values only change if filter freq changes
	FilterParams->b0 = (1 + FilterParams->cosw0) / 2;
	FilterParams->b1 = -(1 + FilterParams->cosw0);
	FilterParams->b2 = FilterParams->b0;

	FilterParams->isInitaliased = true;
    }

    int16 FilteredValue = ((FilterParams->b0 / FilterParams->a0) * unfilteredValue) +
                          ((FilterParams->b1 / FilterParams->a0) * FilterParams->unFilterednMinus1) +
                          ((FilterParams->b2 / FilterParams->a0) * FilterParams->unFilterednMinus2) -
                          ((FilterParams->a1 / FilterParams->a0) * FilterParams->FilterednMinus1) -
                          ((FilterParams->a2 / FilterParams->a0) * FilterParams->FilterednMinus2);
    
    FilterParams->unFilterednMinus2 = FilterParams->unFilterednMinus1;
    FilterParams->unFilterednMinus1 = unfilteredValue;
    
    FilterParams->FilterednMinus2 = FilterParams->FilterednMinus1;
    FilterParams->FilterednMinus1 = FilteredValue;
    
    return FilteredValue;
}


int16 ExponentialFilter(int UnfilteredValue, osx_sound_output *SoundOutput)
{
    static int16 CurrentValue = 0;
    
    float TimeConstant = (1 / (2 * pi32 * SoundOutput->SoundBuffer.FilterFrequency));
    float alpha = (SoundOutput->SoundBuffer.TimeInterval /
                   (SoundOutput->SoundBuffer.TimeInterval + TimeConstant));
    
    int16 Result = CurrentValue + alpha * (UnfilteredValue - CurrentValue);
    CurrentValue = Result;
    
    return Result;
}


void writeNoise(osx_sound_output *SoundOutput, waveform_params *WaveformParams)
{
    bool FirstTime = true;
    
    for(int i = 0; i < SoundOutput->SoundBuffer.SamplesToWrite; i++)
    {
	if(FirstTime)
	{
	    WaveformParams->StartOfWaveform = SoundOutput->WriteCursor;
	    FirstTime = false;
	}
	
        float RandomValue = (rand() / (float)RAND_MAX - 0.5f) * 1000;

        static filter_params FilterParams = {};
        int16 FilteredValue = BiQuadLowPassFilter(RandomValue, SoundOutput, &FilterParams);
        
        *SoundOutput->WriteCursor++ = (int16)FilteredValue;
        *SoundOutput->WriteCursor++ = (int16)FilteredValue;
        
        if((char *)SoundOutput->WriteCursor >= ((char *)SoundOutput->CoreAudioBuffer + SoundOutput->SoundBufferSize))
        {
            SoundOutput->WriteCursor = SoundOutput->CoreAudioBuffer;
        }
    }
}


void writeSquareWave(osx_sound_output *SoundOutput, waveform_params *WaveformParams)
{
    int sign = 1;
    bool FirstTime = true;
    for(int i = 0; i < SoundOutput->SoundBuffer.SamplesToWrite; i++)
    {
        if(WaveformParams->wavePeriodIndex == 0 && FirstTime)
	{
	    WaveformParams->StartOfWaveform = SoundOutput->WriteCursor;
	    FirstTime = false;
	}
        if(WaveformParams->wavePeriodIndex < WaveformParams->wavePeriod / 2)
        {
            sign = 1;
        }
        else {
            sign = -1;
        }
        WaveformParams->wavePeriodIndex ++;
        if(WaveformParams->wavePeriodIndex >= WaveformParams->wavePeriod)
        {
            WaveformParams->wavePeriodIndex = 0;
        }
        
        int16 UnfilteredValue = (1 * sign * 1000);
        
        //Simple exponential filter
//        int16 FilteredValue = ExponentialFilter(UnfilteredValue, SoundOutput);
        
        //BiQuadLowPass
	static filter_params FilterParams = {};
        int16 FilteredValue = BiQuadHighPassFilter(UnfilteredValue, SoundOutput, &FilterParams);
        
        *SoundOutput->WriteCursor++ = FilteredValue;
        *SoundOutput->WriteCursor++ = FilteredValue;
        
        if((char *)SoundOutput->WriteCursor >= ((char *)SoundOutput->CoreAudioBuffer + SoundOutput->SoundBufferSize))
        {
            SoundOutput->WriteCursor = SoundOutput->CoreAudioBuffer;
        }
    }
}


void writeSineWave(osx_sound_output *SoundOutput, waveform_params *WaveformParams)
{
    bool FirstTime = true;
    for(int i = 0; i < SoundOutput->SoundBuffer.SamplesToWrite; i++)
    {
        double tSine = 2.0f * M_PI * ((double)WaveformParams->wavePeriodIndex / (double)WaveformParams->wavePeriod);
        if(WaveformParams->wavePeriodIndex == 0 && FirstTime)
	{
	    WaveformParams->StartOfWaveform = SoundOutput->WriteCursor;
	    FirstTime = false;
	}
        if(WaveformParams->wavePeriodIndex > WaveformParams->wavePeriod)
        {
            WaveformParams->wavePeriodIndex = 0;
        }
        else
        {
            WaveformParams->wavePeriodIndex++;
        }
        
        double sineStep = sin(tSine);
        
        //Simple exponential filter


        int16 UnfilteredValue = (1 * sineStep * 1000);
        int16 FilteredValue = ExponentialFilter(UnfilteredValue, SoundOutput);
        
        *SoundOutput->WriteCursor++ = FilteredValue;
        *SoundOutput->WriteCursor++ = FilteredValue;
        
        if((char *)SoundOutput->WriteCursor >= ((char *)SoundOutput->CoreAudioBuffer + SoundOutput->SoundBufferSize))
        {
            SoundOutput->WriteCursor = SoundOutput->CoreAudioBuffer;
        }
    }
}

void writeSawtoothWave(osx_sound_output *SoundOutput, waveform_params *WaveformParams)
{
    bool FirstTime = true;
    float SawStepAmount = 2.0f / (float)WaveformParams->wavePeriod;
    for(int i = 0; i < SoundOutput->SoundBuffer.SamplesToWrite; i++)
    {
	if(WaveformParams->wavePeriodIndex == 0 && FirstTime)
	{
	    WaveformParams->StartOfWaveform = SoundOutput->WriteCursor;
	    FirstTime = false;
	}
        if(WaveformParams->wavePeriodIndex > WaveformParams->wavePeriod)
        {
            WaveformParams->wavePeriodIndex = 0;
        }
        else
        {
            WaveformParams->wavePeriodIndex++;
        }
	int16 UnfilteredValue = (1.0f - (SawStepAmount * WaveformParams->wavePeriodIndex)) * 1000;

	static filter_params FilterParams = {};

	int16 FilteredValue = BiQuadLowPassFilter(UnfilteredValue, SoundOutput, &FilterParams);
	*SoundOutput->WriteCursor++ = FilteredValue;
        *SoundOutput->WriteCursor++ = FilteredValue;
        
        if((char *)SoundOutput->WriteCursor >= ((char *)SoundOutput->CoreAudioBuffer + SoundOutput->SoundBufferSize))
        {
            SoundOutput->WriteCursor = SoundOutput->CoreAudioBuffer;
        }
    }
}

void writeTriangleWave(osx_sound_output *SoundOutput, waveform_params *WaveformParams)
{
    bool FirstTime = true;
    int16 HalfPeriod = WaveformParams->wavePeriod / 2;
    for(int i = 0; i < SoundOutput->SoundBuffer.SamplesToWrite; i++)
    {
	if(WaveformParams->wavePeriodIndex == (WaveformParams->wavePeriod/4) && FirstTime)
	{
	    WaveformParams->StartOfWaveform = SoundOutput->WriteCursor;
	    FirstTime = false;
	}
        if(WaveformParams->wavePeriodIndex > WaveformParams->wavePeriod)
        {
            WaveformParams->wavePeriodIndex = 0;
        }
        else
        {
            WaveformParams->wavePeriodIndex++;
        }

	float temp = abs(WaveformParams->wavePeriodIndex - HalfPeriod);
	
	int16 UnfilteredValue = ((2000/HalfPeriod) * (HalfPeriod - temp)) - 1000;

	static filter_params FilterParams = {};

	int16 FilteredValue = BiQuadLowPassFilter(UnfilteredValue, SoundOutput, &FilterParams);
	*SoundOutput->WriteCursor++ = FilteredValue;
        *SoundOutput->WriteCursor++ = FilteredValue;
        
        if((char *)SoundOutput->WriteCursor >= ((char *)SoundOutput->CoreAudioBuffer + SoundOutput->SoundBufferSize))
        {
            SoundOutput->WriteCursor = SoundOutput->CoreAudioBuffer;
        }
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


float UpdateBuffer(osx_sound_output *SoundOutput)
{
    uint64_t StartTime = mach_absolute_time();
    static uint64_t LastStartTime = 0;
    
    float ForecastSecondsElapsed = 0;
    if(LastStartTime == 0)
    {
        SoundOutput->SoundBuffer.SamplesToWrite = (SoundOutput->SoundBuffer.SamplesPerSecond / 30 + 200);
    }
    else
    {
	ForecastSecondsElapsed = OSXGetSecondsElapsed(LastStartTime, StartTime);
	Assert(ForecastSecondsElapsed < 1);
        SoundOutput->SoundBuffer.SamplesToWrite = (SoundOutput->SoundBuffer.SamplesPerSecond * ForecastSecondsElapsed);
    }
    
    static waveform_params WaveformParams = {};
    WaveformParams.wavePeriod = SoundOutput->SoundBuffer.SamplesPerSecond / SoundOutput->SoundBuffer.ToneHz;
    s16 Latency = 1600;
    
    if(WaveformParams.LastWriteCursor == 0)
    {
        SoundOutput->WriteCursor = SoundOutput->ReadCursor + Latency;
    }
    else
    {
        SoundOutput->WriteCursor = WaveformParams.LastWriteCursor;
    }

    // TODO: grab few samples before and after the waveform to show how the filter changes the phase


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

    writeWaveForm(SoundOutput, WaveformParams);
    writeFFTSamples(SoundOutput);
    fastFourierTransform(SoundOutput);
    
    WaveformParams.LastWriteCursor = SoundOutput->WriteCursor;
    //writeWaveform(SoundOutput);
    
    LastStartTime = StartTime;
    
    return ForecastSecondsElapsed;
}


osx_sound_output * SetupAndRun(void)
{
    static game_sound_output_buffer SoundBuffer = {};
    static osx_sound_output SoundOutput = {};
    SoundOutput.SoundBuffer = SoundBuffer;
    SoundOutput.SoundBuffer.SamplesPerSecond = 48000;
    SoundOutput.SoundBuffer.SampleCount = 48000;
    SoundOutput.SoundBuffer.ToneHz = 440;
    SoundOutput.SoundBuffer.FilterFrequency = 1000;
    SoundOutput.SoundBuffer.Q = 1;
    SoundOutput.SoundBuffer.TimeInterval = 1.0f / 48000.0f;
    SoundOutput.SoundBufferSize = 48000 * sizeof(int16_t) * 2;
    
    uint32_t MaxOverrun = 8 * 2 * sizeof(int16_t);
    
    SoundOutput.SoundBuffer.Samples = (int16_t *)mmap(0, SoundOutput.SoundBufferSize + MaxOverrun, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANON, -1, 0);
    if(SoundOutput.SoundBuffer.Samples == MAP_FAILED)
    {

    }
    memset(SoundOutput.SoundBuffer.Samples, 0,  SoundOutput.SoundBufferSize);
    
    SoundOutput.CoreAudioBuffer = (int16_t *)mmap(0, SoundOutput.SoundBufferSize + MaxOverrun, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANON, -1, 0);
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