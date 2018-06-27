//
//  ViewController.swift
//  SoundTest5
//
//  Created by Sebastian Reinolds on 19/03/2018.
//  Copyright © 2018 Sebastian Reinolds. All rights reserved.
//

import UIKit
import Foundation
import MetalKit
import MetalPerformanceShaders
import simd

class ViewController: UIViewController {
    //let waveformLayer = CAShapeLayer()
    //let FFTLayer = CAShapeLayer()
    var FFTMaxValue = 0
    
    var WaveformType: waveform_type = Sine;
    var FilterType: filter_type = NoFilter
    
    var SoundOutput: UnsafeMutablePointer<osx_sound_output>? = nil
    var FPS: Double = 60
    var waveform: [Int16] = Array(repeating: 0, count: 1024)
    var FFTArray: [Float] = Array(repeating: 0.0, count: 1024)
    
    
    //metal
    var timer: CADisplayLink!
    var device: MTLDevice!
    var metalLayer: CAMetalLayer!
    var computePipeline: MTLComputePipelineState!
    var pipelineState: MTLRenderPipelineState!
    var vertexBuffer: MTLBuffer!
    var uniformBuffer: MTLBuffer!
    var commandQueue: MTLCommandQueue!
    
    let gridVertices = 440
    let waveformTraceVertices = 1024
    var totalVertices: Int!
    let floatsPerVertex = 8
    
    var vertexData: [Float] = []
    
    
    override func viewDidLoad() {
        super.viewDidLoad()
        totalVertices = self.gridVertices + self.waveformTraceVertices
        self.vertexData = Array(repeating: 0.0, count: ((totalVertices) * floatsPerVertex))
        
        SetupMetal()
        SoundOutput = SetupAndRun()
        self.SoundOutput?.pointee.SoundBuffer.FPS = FPS
        
        WriteSamples(SoundOutput)          // Why is this needed?
        
        timer = CADisplayLink(target: self, selector: #selector(ViewController.soundLoopAndRender))
        timer.add(to: RunLoop.main, forMode: RunLoopMode.defaultRunLoopMode)
    }
    
    
    func SetupMetal()
    {
        device = MTLCreateSystemDefaultDevice()
        metalLayer = CAMetalLayer()
        metalLayer.device = device
        metalLayer.pixelFormat = .bgra8Unorm
        metalLayer.framebufferOnly = false
        metalLayer.frame = CGRect(x: 0, y: 0, width: view.layer.frame.width, height: view.layer.frame.height/2)
        view.layer.addSublayer(metalLayer)
        
        genGrid(Width: 2, Height: 2)
        
        let dataSize = vertexData.count * MemoryLayout.size(ofValue: vertexData[0])
        vertexBuffer = device.makeBuffer(bytes: vertexData, length: dataSize, options: [])
        
        var scaling = scalingMatrix(scale: 1.0)
        let matrixSize = MemoryLayout<Float>.size * 16
        var projMatrix = projectionMatrix(near: 0.1, far: 100, aspect: Float(self.view.bounds.size.width / self.view.bounds.size.height), fovy: 1.484)
        uniformBuffer = device.makeBuffer(length: matrixSize * 2, options: [])
        memcpy(uniformBuffer.contents(), &scaling, matrixSize)
        memcpy(uniformBuffer.contents() + matrixSize, &projMatrix, matrixSize)
        
        let defaultLibrary = device.makeDefaultLibrary()!
        let fragmentProgram = defaultLibrary.makeFunction(name: "basic_fragment")
        let vertexProgram = defaultLibrary.makeFunction(name: "basic_vertex")
        let computeProgram = defaultLibrary.makeFunction(name: "compute_shader")
        computePipeline = try! device.makeComputePipelineState(function: computeProgram!)
        
        let pipelineStateDescriptor = MTLRenderPipelineDescriptor()
        pipelineStateDescriptor.vertexFunction = vertexProgram
        pipelineStateDescriptor.fragmentFunction = fragmentProgram
        pipelineStateDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        pipelineStateDescriptor.colorAttachments[1].pixelFormat = .bgra8Unorm // Trace texture
        
        pipelineState = try! device.makeRenderPipelineState(descriptor: pipelineStateDescriptor)
        commandQueue = device.makeCommandQueue()
    }
    
    
    @objc func soundLoopAndRender() {
        self.SoundOutput?.pointee.SoundBuffer.WaveformType = self.WaveformType
        self.SoundOutput?.pointee.SoundBuffer.FilterType = self.FilterType
        self.SoundOutput?.pointee.SoundBuffer.ToneHz = Int32(self.ToneSlider.value)
        self.SoundOutput?.pointee.SoundBuffer.FilterFrequency = Int32(self.FilterCutoffSlider.value)
        self.SoundOutput?.pointee.SoundBuffer.Q = self.QSlider.value
        
        WriteSamples(self.SoundOutput)
        
        self.GenVertices()
        memcpy(vertexBuffer.contents(), vertexData, vertexData.count * MemoryLayout.size(ofValue: vertexData[0]))
        
        let scaling = scalingMatrix(scale: 0.9)
        let rotation = rotationMatrix(rotVector: float3(0.0, 0.0, 0.0)) * scaling
        var translation = translationMatrix(position: float3(0.0, 0.0, 0.0)) * rotation
        
        let transsize = MemoryLayout<Float>.size * 16
        memcpy(uniformBuffer.contents(), &translation, transsize)
        
        render()
    }
    
    
    func render() {
        let drawable = metalLayer!.nextDrawable()!
        
        let renderPassDescriptor = MTLRenderPassDescriptor()
        renderPassDescriptor.colorAttachments[0].texture = drawable.texture
        renderPassDescriptor.colorAttachments[0].loadAction = .clear
        renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 1.0)
        
        // Trace texture
        let traceDesc: MTLTextureDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: drawable.texture.pixelFormat,
                                                                                       width: drawable.texture.width,
                                                                                       height: drawable.texture.height, mipmapped: false)
        traceDesc.usage = [.shaderRead, .shaderWrite, .renderTarget]
        var traceTexture: MTLTexture = device.makeTexture(descriptor: traceDesc)!
        renderPassDescriptor.colorAttachments[1].texture = traceTexture
        renderPassDescriptor.colorAttachments[1].loadAction = .clear
        renderPassDescriptor.colorAttachments[1].clearColor = MTLClearColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 1.0)
        
        let commandBuffer = commandQueue.makeCommandBuffer()!
        let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor)!
        renderEncoder.setRenderPipelineState(pipelineState)
        renderEncoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        renderEncoder.setVertexBuffer(uniformBuffer, offset: 0, index: 1)
        let vertexCount = vertexData.count / 8
        renderEncoder.drawPrimitives(type: .line, vertexStart: 0, vertexCount: vertexCount, instanceCount: 1)
        renderEncoder.endEncoding()
        
        // Blur trace
        let gaussKernel = MPSImageGaussianBlur(device: device, sigma: 6.0)
        gaussKernel.encode(commandBuffer: commandBuffer, inPlaceTexture: &traceTexture, fallbackCopyAllocator: nil)
        
        // Add blurred texture back
        let compute = commandBuffer.makeComputeCommandEncoder()!
        compute.setComputePipelineState(computePipeline)
        compute.setTexture(drawable.texture, index: 0)
        compute.setTexture(traceTexture, index: 1)
        compute.setTexture(drawable.texture, index: 2)
        
        let groupSize = MTLSize(width: 64, height: 64, depth: 1)
        let groups = MTLSize(width: Int(view.bounds.size.width) / groupSize.width+1, height: Int(view.bounds.size.height) / groupSize.height+1, depth: 1)
        compute.dispatchThreadgroups(groupSize, threadsPerThreadgroup: groups)
        compute.endEncoding()
        
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
    
    
    func getWaveform() {
        let waveformPointer: UnsafeMutablePointer<s16> = (SoundOutput!.pointee.SoundBuffer.Waveform.WaveformArray)!
     
        for index in 0...(SoundOutput!.pointee.SoundBuffer.Waveform.WaveformArrayLength - 1) {
            waveform[Int(index)] = (waveformPointer + Int(index)).pointee
        }
    }
    
    func getFFTArray() {
        let FFTArrayPointer: UnsafeMutablePointer<Float> = (SoundOutput!.pointee.SoundBuffer.Waveform.FFTArray)!
        
        for index in 0...(SoundOutput!.pointee.SoundBuffer.Waveform.FFTSampleCount - 1) {
            FFTArray[Int(index)] = (FFTArrayPointer + Int(index)).pointee
        }
    }
    
    func GenVertices() {
        let Width: Float = 2
        let Height: Float = 2
        
        let waveformPointer: UnsafeMutablePointer<s16> = (SoundOutput!.pointee.SoundBuffer.Waveform.WaveformArray)!
        var waveformLength = Int(SoundOutput!.pointee.SoundBuffer.Waveform.WaveformArrayLength)
        let xStride = Width / Float(waveformTraceVertices)

        if waveformLength > waveformTraceVertices {
            waveformLength = waveformTraceVertices
        }
        
        
        let start = gridVertices * 8
        let waveStart = start + (((waveformTraceVertices - waveformLength) / 2) * 8)
        let waveEnd = waveStart + (waveformLength * 8)
        
        var waveIndex = 0
        var gridIndex = 0
        for i in gridVertices..<(totalVertices-1) {
            var index = i * 8
            
            if index < waveStart  || index >= waveEnd {
                self.vertexData[index++] = xStride * Float(gridIndex) - Width/2
                self.vertexData[index++] = 0
                self.vertexData[index++] = 0
                self.vertexData[index++] = 1
                
                self.vertexData[index++] = 0.0
                self.vertexData[index++] = 1.0
                self.vertexData[index++] = 0.0
                self.vertexData[index++] = 1.0
                
                self.vertexData[index++] = xStride * Float(gridIndex+1) - Width/2
                self.vertexData[index++] = 0
                self.vertexData[index++] = 0
                self.vertexData[index++] = 1
                
                self.vertexData[index++] = 0.0
                self.vertexData[index++] = 1.0
                self.vertexData[index++] = 0.0
                self.vertexData[index++] = 1.0
            }
            else if index < waveEnd {
                self.vertexData[index++] = xStride * Float(gridIndex) - Width/2
                self.vertexData[index++] = Float((waveformPointer + Int(waveIndex)).pointee) / 3276// int16 maxval. todo: scale
                self.vertexData[index++] = 0
                self.vertexData[index++] = 1
                
                self.vertexData[index++] = 0.0
                self.vertexData[index++] = 1.0
                self.vertexData[index++] = 0.0
                self.vertexData[index++] = 1.0
                
                self.vertexData[index++] = xStride * Float(gridIndex+1) - Width/2
                self.vertexData[index++] = Float((waveformPointer + Int(waveIndex + 1)).pointee) / 3276// int16 maxval. todo: scale
                self.vertexData[index++] = 0
                self.vertexData[index++] = 1
                
                self.vertexData[index++] = 0.0
                self.vertexData[index++] = 1.0
                self.vertexData[index++] = 0.0
                self.vertexData[index++] = 1.0
                
                waveIndex++
            }
            gridIndex++
        }
    }
    
    
    func genGrid(Width: Float, Height: Float) {
        for i in 0...10 {
            for j in 0...9 {
                var index = (i * 10 * 32) + (j * 32)
                
                self.vertexData[index++] = (Width/10 * Float(i) - Width/2)
                self.vertexData[index++] = (Height/10 * Float(j) - Height/2)
                self.vertexData[index++] = (0)
                self.vertexData[index++] = (1)
                
                self.vertexData[index++] = (0.3)
                self.vertexData[index++] = (0.3)
                self.vertexData[index++] = (0.3)
                self.vertexData[index++] = (1)
                
                self.vertexData[index++] = (Width/10 * Float(i) - Width/2)
                self.vertexData[index++] = (Height/10 * Float(j + 1) - Height/2)
                self.vertexData[index++] = (0)
                self.vertexData[index++] = (1)
                
                self.vertexData[index++] = (0.3)
                self.vertexData[index++] = (0.3)
                self.vertexData[index++] = (0.3)
                self.vertexData[index++] = (1)
                
                self.vertexData[index++] = (Width/10 * Float(j) - Width/2)
                self.vertexData[index++] = (Height/10 * Float(i) - Height/2)
                self.vertexData[index++] = (0)
                self.vertexData[index++] = (1)
                
                self.vertexData[index++] = (0.3)
                self.vertexData[index++] = (0.3)
                self.vertexData[index++] = (0.3)
                self.vertexData[index++] = (1)
                
                self.vertexData[index++] = (Width/10 * Float(j + 1) - Width/2)
                self.vertexData[index++] = (Height/10 * Float(i) - Height/2)
                self.vertexData[index++] = (0)
                self.vertexData[index++] = (1)
                
                self.vertexData[index++] = (0.3)
                self.vertexData[index++] = (0.3)
                self.vertexData[index++] = (0.3)
                self.vertexData[index++] = (1)
            }
        }
    }
    
    
    //interface
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
            FilterType = ExponentialHighPass
            FilterButton.setTitle("Exponential HighPass", for: .normal)
        case ExponentialHighPass:
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
            FilterType = Notch
            FilterButton.setTitle("Notch", for: .normal)
        case Notch:
            FilterType = NoFilter
            FilterButton.setTitle("No Filter", for: .normal)
        default:
            FilterType = NoFilter
            FilterButton.setTitle("Exponential LowPass", for: .normal)
        }
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
}



//    func drawWaveForm() {
//        waveformLayer.path = nil
//        waveformLayer.removeFromSuperlayer()
//
//        let width = Int(self.view.frame.width) / 2
//        let height = Int(300)
//        let centerLineY = height/2 + 20
//        let centerLineX = width / 2
//        let waveformPath = UIBezierPath()
//
//        waveformPath.move(to: CGPoint(x: 0, y: centerLineY))
//        waveformPath.addLine(to: CGPoint(x: width, y: centerLineY))
//        waveformPath.move(to: CGPoint(x: centerLineX, y: 0))
//        waveformPath.addLine(to: CGPoint(x: centerLineX, y: height))
//
//        let max = waveform.max()
//        if Int(max!) == 0 {return}
//        let scale: Float = Float(height / 2) / Float(max!)
//
//        let xstart = centerLineX - Int(SoundOutput!.pointee.SoundBuffer.Waveform.WaveformArrayLength)
//        for index in 0...(Int(SoundOutput!.pointee.SoundBuffer.Waveform.WaveformArrayLength - 1)) {
//            let sample = Float(waveform[index]) * scale
//
//            waveformPath.move(to: CGPoint(x: xstart + index * 2, y: centerLineY))
//            waveformPath.addLine(to: CGPoint(x: xstart + index * 2, y: centerLineY - Int(sample)))
//        }
//
//        waveformLayer.strokeColor = UIColor(white: 0.2, alpha: 0.5).cgColor
//        waveformLayer.lineWidth = 1
//
//        waveformLayer.path = waveformPath.cgPath
//        self.view.layer.addSublayer(waveformLayer)
//    }
//
//    func drawFFT()
//    {
//        FFTLayer.removeFromSuperlayer()
//
//        let width = Int(self.view.frame.width) / 2
//        let height = Int(300)
//        let FFTPath = UIBezierPath()
//
//        let max = FFTArray.max()
//        if Int(max!) == 0 {return}
//        if Int(max!) > FFTMaxValue && Int(max!) < 500000 {
//            FFTMaxValue = Int(max!)
//        } else if Int(max!) > 500000 {
//            FFTMaxValue = 500000
//        }
//
//        //print(self.ToneSlider.value)
//        //print(FFTArray.index(of: max!))
//
//        let scale: Float = Float(height) / Float(FFTMaxValue)
//
//        for i in 0...(FFTArray.count) {
//            let sample = Float(FFTArray[i]) * scale
//
//            FFTPath.move(to: CGPoint(x: width + i * 2, y: height))
//            FFTPath.addLine(to: CGPoint(x: width + i * 2, y: height - Int(sample)))
//            if i >= width / 2 {
//                break
//            }
//        }
//
//        FFTLayer.strokeColor = UIColor(white: 0.2, alpha: 0.5).cgColor
//        FFTLayer.lineWidth = 1
//
//        FFTLayer.path = FFTPath.cgPath
//        self.view.layer.addSublayer(FFTLayer)
//    }
//}
