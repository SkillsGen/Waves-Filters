//
//  Waveforms.c
//  SoundTest5
//
//  Created by Sebastian Reinolds on 21/04/2018.
//  Copyright © 2018 Sebastian Reinolds. All rights reserved.
//


void writeSineWave(osx_sound_output *SoundOutput, waveform_params *WaveformParams)
{
    bool FirstTime = true;
    s16* SamplesWriteCursor = SoundOutput->SoundBuffer.Samples;
    
    for(int i = 0; i < SoundOutput->SoundBuffer.SamplesToWrite; i++)
    {
        float tSine = 2.0f * M_PI * ((float)WaveformParams->wavePeriodIndex / (float)WaveformParams->wavePeriod);
        if(WaveformParams->wavePeriodIndex > WaveformParams->wavePeriod)
        {
            WaveformParams->wavePeriodIndex = 0;
            if(FirstTime)
            {
                WaveformParams->StartOfWaveform = SamplesWriteCursor;
                FirstTime = false;
            }
        }
        
        double sineStep = sin(tSine);
        
        int16 UnfilteredValue = (sineStep * 1000);
        
        int16 FilteredValue = Filter(UnfilteredValue, SoundOutput);
        
        *SamplesWriteCursor++ = FilteredValue;
        *SamplesWriteCursor++ = FilteredValue;
        
        WaveformParams->wavePeriodIndex++;
    }
}


void writeSquareWave(osx_sound_output *SoundOutput, waveform_params *WaveformParams)
{
    int sign = 1;
    bool FirstTime = true;
    s16* SamplesWriteCursor = SoundOutput->SoundBuffer.Samples;
    
    for(int i = 0; i < SoundOutput->SoundBuffer.SamplesToWrite; i++)
    {
        if(WaveformParams->wavePeriodIndex == 0 && FirstTime)
        {
            WaveformParams->StartOfWaveform = SamplesWriteCursor;
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
        
        int16 FilteredValue = Filter(UnfilteredValue, SoundOutput);
        
        *SamplesWriteCursor++ = FilteredValue;
        *SamplesWriteCursor++ = FilteredValue;
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
        
        int16 FilteredValue = Filter(UnfilteredValue, SoundOutput);
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
        
        int16 FilteredValue = Filter(UnfilteredValue, SoundOutput);
        *SoundOutput->WriteCursor++ = FilteredValue;
        *SoundOutput->WriteCursor++ = FilteredValue;
        
        if((char *)SoundOutput->WriteCursor >= ((char *)SoundOutput->CoreAudioBuffer + SoundOutput->SoundBufferSize))
        {
            SoundOutput->WriteCursor = SoundOutput->CoreAudioBuffer;
        }
    }
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
        
        float UnfilteredValue = (rand() / (float)RAND_MAX - 0.5f) * 1000;
        
        int16 FilteredValue = Filter(UnfilteredValue, SoundOutput);
        
        *SoundOutput->WriteCursor++ = (int16)FilteredValue;
        *SoundOutput->WriteCursor++ = (int16)FilteredValue;
        
        if((char *)SoundOutput->WriteCursor >= ((char *)SoundOutput->CoreAudioBuffer + SoundOutput->SoundBufferSize))
        {
            SoundOutput->WriteCursor = SoundOutput->CoreAudioBuffer;
        }
    }
}
