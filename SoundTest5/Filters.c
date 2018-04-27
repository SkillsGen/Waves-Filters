//
//  Filters.c
//  SoundTest5
//
//  Created by Sebastian Reinolds on 20/04/2018.
//  Copyright © 2018 Sebastian Reinolds. All rights reserved.
//


int16 ExponentialLowPassFilter(int UnfilteredValue, osx_sound_output *SoundOutput, filter_params *FilterParams);
int16 ExponentialHighPassFilter(int UnfilteredValue, osx_sound_output *SoundOutput, filter_params *FilterParams);
int16 BiQuadLowPassFilter(int unfilteredValue, osx_sound_output *SoundOutput, filter_params *FilterParams);
int16 BiQuadHighPassFilter(int unfilteredValue, osx_sound_output *SoundOutput, filter_params *FilterParams);
int16 ConstSkirtBandPassFilter(int unfilteredValue, osx_sound_output *SoundOutput, filter_params *FilterParams);
int16 ZeroPeakGainBandPassFilter(int unfilteredValue, osx_sound_output *SoundOutput, filter_params *FilterParams);
int16 NotchFilter(int unfilteredValue, osx_sound_output *SoundOutput, filter_params *FilterParams);

int16 Filter(int UnfilteredValue, osx_sound_output *SoundOutput)
{
    static filter_params FilterParams = {};
    int16 FilteredValue;
    switch(SoundOutput->SoundBuffer.FilterType)
    {
        case NoFilter:
            FilteredValue = UnfilteredValue;
            break;
        case ExponentialLowPass:
            FilteredValue = ExponentialLowPassFilter(UnfilteredValue, SoundOutput, &FilterParams);
            break;
        case ExponentialHighPass:
            FilteredValue = ExponentialHighPassFilter(UnfilteredValue, SoundOutput, &FilterParams);
            break;
        case BiQuadLowPass:
            FilteredValue = BiQuadLowPassFilter(UnfilteredValue, SoundOutput, &FilterParams);
            break;
        case BiQuadHighPass:
            FilteredValue = BiQuadHighPassFilter(UnfilteredValue, SoundOutput, &FilterParams);
            break;
        case ConstSkirtBandPass:
            FilteredValue = ConstSkirtBandPassFilter(UnfilteredValue, SoundOutput, &FilterParams);
            break;
        case ZeroPeakGainBandPass:
            FilteredValue = ZeroPeakGainBandPassFilter(UnfilteredValue, SoundOutput, &FilterParams);
        case Notch:
            FilteredValue = NotchFilter(UnfilteredValue, SoundOutput, &FilterParams);
            break;
        default:
            FilteredValue = ExponentialLowPassFilter(UnfilteredValue, SoundOutput, &FilterParams);
    }
    
    return FilteredValue;
}


int16 ExponentialLowPassFilter(int UnfilteredValue, osx_sound_output *SoundOutput, filter_params *FilterParams)
{    
    filter_type FilterType = ExponentialLowPass;
    if(FilterParams->FilterType != FilterType)
    {
	*FilterParams = ZeroedFilterParams;
	FilterParams->FilterType = FilterType;
    }

    float TimeConstant = (1 / (2 * M_PI * SoundOutput->SoundBuffer.FilterFrequency));
    float alpha = (SoundOutput->SoundBuffer.TimeInterval /
                   (SoundOutput->SoundBuffer.TimeInterval + TimeConstant));
    
    int16 FilteredValue = FilterParams->FilterednMinus1 + alpha * (UnfilteredValue - FilterParams->FilterednMinus1);

    FilterParams->FilterednMinus2 = FilterParams->FilterednMinus1;
    FilterParams->FilterednMinus1 = FilteredValue;

    return FilteredValue;
}

int16 ExponentialHighPassFilter(int UnfilteredValue, osx_sound_output *SoundOutput, filter_params *FilterParams)
{    
    filter_type FilterType = ExponentialHighPass;
    if(FilterParams->FilterType != FilterType)
    {
	*FilterParams = ZeroedFilterParams;
	FilterParams->FilterType = FilterType;
    }

    float TimeConstant = (1 / (2 * M_PI * SoundOutput->SoundBuffer.FilterFrequency));
    float alpha = (TimeConstant /
                   (SoundOutput->SoundBuffer.TimeInterval + TimeConstant));
    
    int16 FilteredValue = alpha * (FilterParams->FilterednMinus1 + UnfilteredValue - FilterParams->UnfilterednMinus1);

    FilterParams->FilterednMinus2 = FilterParams->FilterednMinus1;
    FilterParams->FilterednMinus1 = FilteredValue;
    FilterParams->UnfilterednMinus1 = UnfilteredValue;


    return FilteredValue;
}


//     Basic Filter Outline
//     y[n] = (b0/a0)*x[n] + (b1/a0)*x[n-1] + (b2/a0)*x[n-2] - (a1/a0)*y[n-1] - (a2/a0)*y[n-2]
int16 BiQuadLowPassFilter(int unfilteredValue, osx_sound_output *SoundOutput, filter_params *FilterParams)
{
    filter_type FilterType = BiQuadLowPass;
    
    if(!FilterParams->isInitialised ||
       FilterParams->FilterFrequency != SoundOutput->SoundBuffer.FilterFrequency ||
       FilterParams->Q != SoundOutput->SoundBuffer.Q ||
       FilterParams->FilterType != FilterType)
    {
	if(FilterParams->FilterType != FilterType)
	{
	    *FilterParams = ZeroedFilterParams;
	}
	
	FilterParams->FilterType = FilterType;
        FilterParams->FilterFrequency = SoundOutput->SoundBuffer.FilterFrequency;
        FilterParams->Q = SoundOutput->SoundBuffer.Q;
        
        FilterParams->w0 = 2.0f * M_PI * ((float)FilterParams->FilterFrequency /
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
        
        FilterParams->isInitialised = true;
    }
    
    int16 FilteredValue = ((FilterParams->b0 / FilterParams->a0) * unfilteredValue) +
	((FilterParams->b1 / FilterParams->a0) * FilterParams->UnfilterednMinus1) +
	((FilterParams->b2 / FilterParams->a0) * FilterParams->UnfilterednMinus2) -
	((FilterParams->a1 / FilterParams->a0) * FilterParams->FilterednMinus1) -
	((FilterParams->a2 / FilterParams->a0) * FilterParams->FilterednMinus2);
    
    FilterParams->UnfilterednMinus2 = FilterParams->UnfilterednMinus1;
    FilterParams->UnfilterednMinus1 = unfilteredValue;
    
    FilterParams->FilterednMinus2 = FilterParams->FilterednMinus1;
    FilterParams->FilterednMinus1 = FilteredValue;
    
    return FilteredValue;
}


int16 BiQuadHighPassFilter(int unfilteredValue, osx_sound_output *SoundOutput, filter_params *FilterParams)
{
    filter_type FilterType = BiQuadHighPass;
    if(!FilterParams->isInitialised ||
       FilterParams->FilterFrequency != SoundOutput->SoundBuffer.FilterFrequency ||
       FilterParams->Q != SoundOutput->SoundBuffer.Q ||
       FilterParams->FilterType != FilterType)
    {
	if(FilterParams->FilterType != FilterType)
	{
	    *FilterParams = ZeroedFilterParams;
	}

        FilterParams->FilterType = FilterType;
        FilterParams->FilterFrequency = SoundOutput->SoundBuffer.FilterFrequency;
        FilterParams->Q = SoundOutput->SoundBuffer.Q;
        
        FilterParams->w0 = 2.0f * M_PI * ((float)FilterParams->FilterFrequency /
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
        
        FilterParams->isInitialised = true;
    }
    
    int16 FilteredValue = ((FilterParams->b0 / FilterParams->a0) * unfilteredValue) +
	((FilterParams->b1 / FilterParams->a0) * FilterParams->UnfilterednMinus1) +
	((FilterParams->b2 / FilterParams->a0) * FilterParams->UnfilterednMinus2) -
	((FilterParams->a1 / FilterParams->a0) * FilterParams->FilterednMinus1) -
	((FilterParams->a2 / FilterParams->a0) * FilterParams->FilterednMinus2);
    
    FilterParams->UnfilterednMinus2 = FilterParams->UnfilterednMinus1;
    FilterParams->UnfilterednMinus1 = unfilteredValue;
    
    FilterParams->FilterednMinus2 = FilterParams->FilterednMinus1;
    FilterParams->FilterednMinus1 = FilteredValue;
    
    return FilteredValue;
}


int16 ConstSkirtBandPassFilter(int unfilteredValue, osx_sound_output *SoundOutput, filter_params *FilterParams)
{
    filter_type FilterType = ConstSkirtBandPass;
    
    if(!FilterParams->isInitialised ||
       FilterParams->FilterFrequency != SoundOutput->SoundBuffer.FilterFrequency ||
       FilterParams->Q != SoundOutput->SoundBuffer.Q ||
       FilterParams->FilterType != FilterType)
    {
	if(FilterParams->FilterType != FilterType)
	{
	    *FilterParams = ZeroedFilterParams;
	}

        FilterParams->FilterType = FilterType;
        FilterParams->FilterFrequency = SoundOutput->SoundBuffer.FilterFrequency;
        FilterParams->Q = SoundOutput->SoundBuffer.Q;
        
        FilterParams->w0 = 2.0f * M_PI * ((float)FilterParams->FilterFrequency /
                                          SoundOutput->SoundBuffer.SamplesPerSecond);
        FilterParams->cosw0 = cos(FilterParams->w0);
        FilterParams->sinw0 = sin(FilterParams->w0);
        
        
        FilterParams->alpha = FilterParams->sinw0 / (2 * FilterParams->Q);
        FilterParams->a0 = 1 + FilterParams->alpha;
        FilterParams->a1 = -2 * FilterParams->cosw0;
        FilterParams->a2 = 1 - FilterParams->alpha;
        
        FilterParams->b0 = FilterParams->sinw0 / 2;
        FilterParams->b1 = 0;
        FilterParams->b2 = -FilterParams->sinw0 / 2;
        
        FilterParams->isInitialised = true;
    }
    
    int16 FilteredValue = ((FilterParams->b0 / FilterParams->a0) * unfilteredValue) +
	((FilterParams->b1 / FilterParams->a0) * FilterParams->UnfilterednMinus1) +
	((FilterParams->b2 / FilterParams->a0) * FilterParams->UnfilterednMinus2) -
	((FilterParams->a1 / FilterParams->a0) * FilterParams->FilterednMinus1) -
	((FilterParams->a2 / FilterParams->a0) * FilterParams->FilterednMinus2);
    
    FilterParams->UnfilterednMinus2 = FilterParams->UnfilterednMinus1;
    FilterParams->UnfilterednMinus1 = unfilteredValue;
    
    FilterParams->FilterednMinus2 = FilterParams->FilterednMinus1;
    FilterParams->FilterednMinus1 = FilteredValue;
    
    return FilteredValue;
}


int16 ZeroPeakGainBandPassFilter(int unfilteredValue, osx_sound_output *SoundOutput, filter_params *FilterParams)
{
    filter_type FilterType = ZeroPeakGainBandPass;
    
    if(!FilterParams->isInitialised ||
       FilterParams->FilterFrequency != SoundOutput->SoundBuffer.FilterFrequency ||
       FilterParams->Q != SoundOutput->SoundBuffer.Q ||
       FilterParams->FilterType != FilterType)
    {
	if(FilterParams->FilterType != FilterType)
	{
	    *FilterParams = ZeroedFilterParams;
	}

        FilterParams->FilterType = FilterType;
        FilterParams->FilterFrequency = SoundOutput->SoundBuffer.FilterFrequency;
        FilterParams->Q = SoundOutput->SoundBuffer.Q;
        
        FilterParams->w0 = 2.0f * M_PI * ((float)FilterParams->FilterFrequency /
                                          SoundOutput->SoundBuffer.SamplesPerSecond);
        FilterParams->cosw0 = cos(FilterParams->w0);
        FilterParams->sinw0 = sin(FilterParams->w0);
        
        
        FilterParams->alpha = (FilterParams->sinw0 *
                               sinh((log(2)/2) * FilterParams->Q * (FilterParams->sinw0 / 2)));
        FilterParams->a0 = 1 + FilterParams->alpha;
        FilterParams->a1 = -2 * FilterParams->cosw0;
        FilterParams->a2 = 1 - FilterParams->alpha;
        
        FilterParams->b0 = FilterParams->alpha;
        FilterParams->b1 = 0;
        FilterParams->b2 = -FilterParams->alpha;
        
        FilterParams->isInitialised = true;
    }
    
    int16 FilteredValue = ((FilterParams->b0 / FilterParams->a0) * unfilteredValue) +
	((FilterParams->b1 / FilterParams->a0) * FilterParams->UnfilterednMinus1) +
	((FilterParams->b2 / FilterParams->a0) * FilterParams->UnfilterednMinus2) -
	((FilterParams->a1 / FilterParams->a0) * FilterParams->FilterednMinus1) -
	((FilterParams->a2 / FilterParams->a0) * FilterParams->FilterednMinus2);
    
    FilterParams->UnfilterednMinus2 = FilterParams->UnfilterednMinus1;
    FilterParams->UnfilterednMinus1 = unfilteredValue;
    
    FilterParams->FilterednMinus2 = FilterParams->FilterednMinus1;
    FilterParams->FilterednMinus1 = FilteredValue;
    
    return FilteredValue;
}

int16 NotchFilter(int unfilteredValue, osx_sound_output *SoundOutput, filter_params *FilterParams)
{
    filter_type FilterType = Notch;
    if(!FilterParams->isInitialised ||
       FilterParams->FilterFrequency != SoundOutput->SoundBuffer.FilterFrequency ||
       FilterParams->Q != SoundOutput->SoundBuffer.Q ||
       FilterParams->FilterType != FilterType)
    {
	if(FilterParams->FilterType != FilterType)
	{
	    *FilterParams = ZeroedFilterParams;
	}

	FilterParams->FilterType = FilterType;
        FilterParams->FilterFrequency = SoundOutput->SoundBuffer.FilterFrequency;
        FilterParams->Q = SoundOutput->SoundBuffer.Q;
        
        FilterParams->w0 = 2.0f * M_PI * ((float)FilterParams->FilterFrequency /
                                          SoundOutput->SoundBuffer.SamplesPerSecond);
        FilterParams->cosw0 = cos(FilterParams->w0);
        FilterParams->sinw0 = sin(FilterParams->w0);

	FilterParams->alpha = (FilterParams->sinw0 *
                               sinh((log(2)/2) * FilterParams->Q * (FilterParams->sinw0 / 2)));
        FilterParams->a0 = 1 + FilterParams->alpha;
        FilterParams->a1 = -2 * FilterParams->cosw0;
        FilterParams->a2 = 1 - FilterParams->alpha;

	FilterParams->b0 = 1;
        FilterParams->b1 = -2 * FilterParams->cosw0;
        FilterParams->b2 = 1;
    }
    
    int16 FilteredValue = ((FilterParams->b0 / FilterParams->a0) * unfilteredValue) +
	((FilterParams->b1 / FilterParams->a0) * FilterParams->UnfilterednMinus1) +
	((FilterParams->b2 / FilterParams->a0) * FilterParams->UnfilterednMinus2) -
	((FilterParams->a1 / FilterParams->a0) * FilterParams->FilterednMinus1) -
	((FilterParams->a2 / FilterParams->a0) * FilterParams->FilterednMinus2);

    FilterParams->UnfilterednMinus2 = FilterParams->UnfilterednMinus1;
    FilterParams->UnfilterednMinus1 = unfilteredValue;
    
    FilterParams->FilterednMinus2 = FilterParams->FilterednMinus1;
    FilterParams->FilterednMinus1 = FilteredValue;
    
    return FilteredValue;    
}
