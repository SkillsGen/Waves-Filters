//
//  Waveforms.c
//  SoundTest5
//
//  Created by Sebastian Reinolds on 21/04/2018.
//  Copyright © 2018 Sebastian Reinolds. All rights reserved.
//


void writeSineWave(osx_sound_output *SoundOutput, waveform_params *WaveformParams)
{
    s16* SamplesWriteCursor = SoundOutput->SoundBuffer.Samples;
    WaveformParams->wavePeriodIndex = 0;
    
    for(int i = 0; i < SoundOutput->SoundBuffer.SamplesToWrite + 4000; i++)
    {
	if(WaveformParams->wavePeriodIndex >= WaveformParams->wavePeriod)
        {
            WaveformParams->wavePeriodIndex = 0;
        }
        
	float tSine = 2.0f * M_PI * ((float)WaveformParams->wavePeriodIndex / (float)WaveformParams->wavePeriod);
        double sineStep = sin(tSine);
	
        int16 UnfilteredValue = (sineStep * SoundOutput->SoundBuffer.Gain);        
        int16 FilteredValue = Filter(UnfilteredValue, SoundOutput);        

	*SamplesWriteCursor++ = FilteredValue;
        *SamplesWriteCursor++ = FilteredValue;
        
        WaveformParams->wavePeriodIndex++;
    }
}


void writeSquareWave(osx_sound_output *SoundOutput, waveform_params *WaveformParams)
{
    s16* SamplesWriteCursor = SoundOutput->SoundBuffer.Samples;
    int sign = 1;
    WaveformParams->wavePeriodIndex = 0;
    
    for(int i = 0; i < SoundOutput->SoundBuffer.SamplesToWrite + 4000; i++)
    {
        if(WaveformParams->wavePeriodIndex >= WaveformParams->wavePeriod)
        {
            WaveformParams->wavePeriodIndex = 0;
        }
        if(WaveformParams->wavePeriodIndex < WaveformParams->wavePeriod / 2)
        {
            sign = 1;
        }
        else
	{
            sign = -1;
        }
        
        int16 UnfilteredValue = (sign * SoundOutput->SoundBuffer.Gain);        
        int16 FilteredValue = Filter(UnfilteredValue, SoundOutput);
        
        *SamplesWriteCursor++ = FilteredValue;
        *SamplesWriteCursor++ = FilteredValue;

	WaveformParams->wavePeriodIndex++;
    }
}


void writeSawtoothWave(osx_sound_output *SoundOutput, waveform_params *WaveformParams)
{
    s16* SamplesWriteCursor = SoundOutput->SoundBuffer.Samples;
    float SawStepAmount = 2.0f / (float)WaveformParams->wavePeriod;
    WaveformParams->wavePeriodIndex = 0;
	    
    for(int i = 0; i < SoundOutput->SoundBuffer.SamplesToWrite + 4000; i++)
    {
        if(WaveformParams->wavePeriodIndex >= WaveformParams->wavePeriod)
        {
            WaveformParams->wavePeriodIndex = 0;
        }

        int16 UnfilteredValue = ((1.0f - (SawStepAmount * (float)WaveformParams->wavePeriodIndex)) *
				 SoundOutput->SoundBuffer.Gain);       
        int16 FilteredValue = Filter(UnfilteredValue, SoundOutput);
	
        *SamplesWriteCursor++ = FilteredValue;
        *SamplesWriteCursor++ = FilteredValue;

	WaveformParams->wavePeriodIndex++;
    }
}


void writeTriangleWave(osx_sound_output *SoundOutput, waveform_params *WaveformParams)
{
    s16* SamplesWriteCursor = SoundOutput->SoundBuffer.Samples;
    int16 HalfPeriod = WaveformParams->wavePeriod / 2;
    WaveformParams->wavePeriodIndex = WaveformParams->wavePeriod / 4;
    
    for(int i = 0; i < SoundOutput->SoundBuffer.SamplesToWrite + 4000; i++)
    {
        if(WaveformParams->wavePeriodIndex >= WaveformParams->wavePeriod)
        {
            WaveformParams->wavePeriodIndex = 0;
        }
        
        float temp = abs(WaveformParams->wavePeriodIndex - HalfPeriod);        
        int16 UnfilteredValue = ((((SoundOutput->SoundBuffer.Gain * 2)/HalfPeriod) * (HalfPeriod - temp)) -
				 SoundOutput->SoundBuffer.Gain);
        int16 FilteredValue = Filter(UnfilteredValue, SoundOutput);
	
        *SamplesWriteCursor++ = FilteredValue;
        *SamplesWriteCursor++ = FilteredValue;

	WaveformParams->wavePeriodIndex++;
    }
}


void writeNoise(osx_sound_output *SoundOutput, waveform_params *WaveformParams)
{
    bool FirstTime = true;
    s16* SamplesWriteCursor = SoundOutput->SoundBuffer.Samples;
    
    for(int i = 0; i < SoundOutput->SoundBuffer.SamplesToWrite + 4000; i++)
    {
        if(FirstTime)
        {
            WaveformParams->StartOfWaveform = SamplesWriteCursor;
            FirstTime = false;
        }
        
        float UnfilteredValue = (rand() / (float)RAND_MAX - 0.5f) * SoundOutput->SoundBuffer.Gain;
        
        int16 FilteredValue = Filter(UnfilteredValue, SoundOutput);
        
        *SamplesWriteCursor++ = (int16)FilteredValue;
        *SamplesWriteCursor++ = (int16)FilteredValue;        
    }
}

