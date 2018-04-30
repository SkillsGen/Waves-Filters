//
//  Main.h
//  SoundTest5
//
//  Created by Sebastian Reinolds on 20/03/2018.
//  Copyright © 2018 Sebastian Reinolds. All rights reserved.
//

#ifndef Main_h
#define Main_h


#include <AudioUnit/AudioUnit.h>
#include <stdint.h>
#include <stdlib.h>
#include <math.h>
#include <time.h>
#include <sys/types.h>
#include <sys/mman.h>
#include <mach/mach.h>
#include <mach/mach_time.h>


#define Assert(Expression) if(!(Expression)) {abort();}


typedef uint32_t u32;
typedef int16_t s16;
typedef int16_t int16;

typedef enum waveform_type
{
    Sine,
    Square,
    Sawtooth,
    Triangle,
    Noise
} waveform_type;

typedef enum filter_type
{
    NoFilter,
    ExponentialLowPass,
    ExponentialHighPass,
    BiQuadLowPass,
    BiQuadHighPass,
    ConstSkirtBandPass,
    ZeroPeakGainBandPass,
    Notch
} filter_type;

typedef struct waveform_params
{
    int wavePeriod;
    int wavePeriodIndex;
    s16 *StartOfWaveform;
} waveform_params;

typedef struct filter_params
{
    bool isInitialised;
    filter_type FilterType;
    
    int FilterFrequency;
    float Q;
    float w0;
    float sinw0;
    float cosw0;
    float alpha;
    float b0;
    float b1;
    float b2;
    float a0;
    float a1;
    float a2;
    
    int16 FilterednMinus1;
    int16 FilterednMinus2;
    int16 UnfilterednMinus1;
    int16 UnfilterednMinus2;
} filter_params;

static filter_params ZeroedFilterParams = {};

typedef struct waveform_array
{
    int WaveformArrayLength;
    s16* WaveformArray;
    int FFTSampleCount;
    float* FFTArray;
} waveform_array;

typedef struct sound_output_buffer
{
    int SamplesPerSecond;
    int SampleCount;
    int SamplesToWrite;

    int LastPhaseDifference;
    s16 *LastWriteCursor;
    float TimeInterval;
    double FPS;
    
    waveform_type WaveformType;
    int Gain;
    int ToneHz;
    waveform_array Waveform;
    
    filter_type FilterType;
    int FilterFrequency;
    float Q;
    
    s16* Samples;
} sound_output_buffer;

typedef struct osx_sound_output
{
    sound_output_buffer SoundBuffer;
    u32 SoundBufferSize;
    s16* CoreAudioBuffer;
    s16* ReadCursor;
    s16* WriteCursor;
    
    AudioStreamBasicDescription AudioDescriptor;
    AudioUnit AudioUnit;
} osx_sound_output;


osx_sound_output * SetupAndRun(void);
float WriteSamples(osx_sound_output *SoundOutput);

#endif /* Main_h */
