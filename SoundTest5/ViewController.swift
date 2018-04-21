//
//  ViewController.swift
//  SoundTest5
//
//  Created by Sebastian Reinolds on 19/03/2018.
//  Copyright © 2018 Sebastian Reinolds. All rights reserved.
//

import UIKit
import Foundation

class ViewController: UIViewController {
    let waveformLayer = CAShapeLayer()
    let FFTLayer = CAShapeLayer()
    var FFTMaxValue = 0
    
    var WaveformType: waveform_type = Sine;
    var FilterType: filter_type = NoFilter
    
    var SoundOutput: UnsafeMutablePointer<osx_sound_output>? = nil
    var waveform: [Int16] = Array(repeating: 0, count: 2048)
    var FFTArray: [Float] = Array(repeating: 0.0, count: 1024)
    
    @IBOutlet weak var ToneSlider: UISlider!
    @IBOutlet weak var FilterCutoffSlider: UISlider!
    @IBOutlet weak var QSlider: UISlider!
    
    @IBOutlet weak var WaveformButton: UIButton!
    @IBAction func WaveformButtonTapped(_ sender: UIButton) {
        switch WaveformType {
        case Sine:
            WaveformType = Square
            WaveformButton.setTitle("Square", for: .normal)
        case Square:
            WaveformType = Sawtooth
            WaveformButton.setTitle("SawTooth", for: .normal)
        case Sawtooth:
            WaveformType = Triangle
            WaveformButton.setTitle("Triangle", for: .normal)
        case Triangle:
            WaveformType = Noise
            WaveformButton.setTitle("Noise", for: .normal)
        case Noise:
            WaveformType = Sine
            WaveformButton.setTitle("Sine", for: .normal)
        default:
            WaveformType = Sine
            WaveformButton.setTitle("Sine", for: .normal)
        }
    }
    
    @IBOutlet weak var FilterButton: UIButton!
    @IBAction func FilterButtonTapped(_ sender: Any) {
        switch FilterType {
        case NoFilter:
            FilterType = ExponentialLowPass
            FilterButton.setTitle("Exponential LowPass", for: .normal)
        case ExponentialLowPass:
            FilterType = BiQuadLowPass
            FilterButton.setTitle("BiQuad LowPass", for: .normal)
            FilterCutoffSlider.value = 20000
        case BiQuadLowPass:
            FilterType = BiQuadHighPass
            FilterButton.setTitle("BiQuad HighPass", for: .normal)
            FilterCutoffSlider.value = 10
        case BiQuadHighPass:
            FilterType = ConstSkirtBandPass
            FilterButton.setTitle("ConstSkirt BandPass", for: .normal)
            FilterCutoffSlider.value = 5000
        case ConstSkirtBandPass:
            FilterType = ZeroPeakGainBandPass
            FilterButton.setTitle("ZeroPeakGain BandPass", for: .normal)
        case ZeroPeakGainBandPass:
            FilterType = NoFilter
            FilterButton.setTitle("No Filter", for: .normal)
        default:
            FilterType = NoFilter
            FilterButton.setTitle("Exponential LowPass", for: .normal)
        }
    }
    
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        SoundOutput = SetupAndRun()
        
        UpdateBuffer(SoundOutput)          // Why is this needed?
        
        Timer.scheduledTimer(withTimeInterval: 1/30, repeats: true) { (Timer) in
            self.SoundOutput?.pointee.SoundBuffer.WaveformType = self.WaveformType
            self.SoundOutput?.pointee.SoundBuffer.FilterType = self.FilterType
            self.SoundOutput?.pointee.SoundBuffer.ToneHz = Int32(self.ToneSlider.value)
            self.SoundOutput?.pointee.SoundBuffer.FilterFrequency = Int32(self.FilterCutoffSlider.value)
            self.SoundOutput?.pointee.SoundBuffer.Q = self.QSlider.value
            
            UpdateBuffer(self.SoundOutput)
            
            self.getWaveform()
            self.getFFTArray()
        }
    }

    func getWaveform() {
        let waveformPointer: UnsafeMutablePointer<s16> = (SoundOutput!.pointee.SoundBuffer.Waveform.WaveformArray)!
     
        for index in 0...(SoundOutput!.pointee.SoundBuffer.Waveform.WaveformArrayLength - 1) {
            waveform[Int(index)] = (waveformPointer + Int(index)).pointee
        }
        drawWaveForm()
    }
    
    func getFFTArray() {
        let FFTArrayPointer: UnsafeMutablePointer<Float> = (SoundOutput!.pointee.SoundBuffer.Waveform.FFTArray)!
        
        for index in 0...(SoundOutput!.pointee.SoundBuffer.Waveform.FFTSampleCount - 1) {
            FFTArray[Int(index)] = (FFTArrayPointer + Int(index)).pointee
        }
        drawFFT()
    }
    
    func drawWaveForm() {
        waveformLayer.path = nil
        waveformLayer.removeFromSuperlayer()
        
        let width = Int(self.view.frame.width) / 2
        let height = Int(300)
        let centerLineY = height/2 + 20
        let centerLineX = width / 2
        let waveformPath = UIBezierPath()
        
        waveformPath.move(to: CGPoint(x: 0, y: centerLineY))
        waveformPath.addLine(to: CGPoint(x: width, y: centerLineY))
        waveformPath.move(to: CGPoint(x: centerLineX, y: 0))
        waveformPath.addLine(to: CGPoint(x: centerLineX, y: height))
        
        let max = waveform.max()
        if Int(max!) == 0 {return}
        let scale: Float = Float(height / 2) / Float(max!)
        
        let xstart = centerLineX - Int(SoundOutput!.pointee.SoundBuffer.Waveform.WaveformArrayLength)
        for index in 0...(Int(SoundOutput!.pointee.SoundBuffer.Waveform.WaveformArrayLength - 1)) {
            let sample = Float(waveform[index]) * scale
            
            waveformPath.move(to: CGPoint(x: xstart + index * 2, y: centerLineY))
            waveformPath.addLine(to: CGPoint(x: xstart + index * 2, y: centerLineY - Int(sample)))
        }
        
        waveformLayer.strokeColor = UIColor(white: 0.2, alpha: 0.5).cgColor
        waveformLayer.lineWidth = 1
        
        waveformLayer.path = waveformPath.cgPath
        self.view.layer.addSublayer(waveformLayer)
    }
    
    func drawFFT()
    {
        FFTLayer.removeFromSuperlayer()
        
        let width = Int(self.view.frame.width) / 2
        let height = Int(300)
        let FFTPath = UIBezierPath()
        
        let max = FFTArray.max()
        if Int(max!) == 0 {return}
        if Int(max!) > FFTMaxValue && Int(max!) < 500000 {
            FFTMaxValue = Int(max!)
        } else if Int(max!) > 500000 {
            FFTMaxValue = 500000
        }
        
        //print(self.ToneSlider.value)
        //print(FFTArray.index(of: max!))
        
        let scale: Float = Float(height) / Float(FFTMaxValue)
        
        for i in 0...(FFTArray.count) {
            let sample = Float(FFTArray[i]) * scale
            
            FFTPath.move(to: CGPoint(x: width + i * 2, y: height))
            FFTPath.addLine(to: CGPoint(x: width + i * 2, y: height - Int(sample)))
            if i >= width / 2 {
                break
            }
        }
        
        FFTLayer.strokeColor = UIColor(white: 0.2, alpha: 0.5).cgColor
        FFTLayer.lineWidth = 1
        
        FFTLayer.path = FFTPath.cgPath
        self.view.layer.addSublayer(FFTLayer)
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
}
