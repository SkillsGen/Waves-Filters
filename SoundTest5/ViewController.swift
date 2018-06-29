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
    var FFTMaxValue = 0
    
    var WaveformType: waveform_type = Sine;
    var FilterType: filter_type = NoFilter
    
    var SoundOutput: UnsafeMutablePointer<osx_sound_output>? = nil
    var FPS: Double = 120
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
    
    let gridVertices = 880
    let traceVertices = 1024
    var totalVertices: Int!
    let floatsPerVertex = 8
    
    var vertexData: [Float] = []
    
    
    override func viewDidLoad() {
        super.viewDidLoad()
        totalVertices = self.gridVertices + self.traceVertices * 2
        self.vertexData = Array(repeating: 0.0, count: ((totalVertices) * floatsPerVertex))
        
        genGrid(Width: 1, Height: 1, xOffset: -1.05, yOffset: -1/2, gridIndex: 0)
        genGrid(Width: 1, Height: 1, xOffset: 0.05, yOffset: -1/2, gridIndex: 1)
        
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
        
        let dataSize = vertexData.count * MemoryLayout.size(ofValue: vertexData[0])
        vertexBuffer = device.makeBuffer(bytes: vertexData, length: dataSize, options: [])
        
        var scaling = scalingMatrix(xScale: 1.0, yScale: 1.0, zScale: 1.0)
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
        

        self.GenTraceVertices(tracePointer: SoundOutput!.pointee.SoundBuffer.Waveform.WaveformArray, traceCount: Int(SoundOutput!.pointee.SoundBuffer.Waveform.WaveformArrayLength), traceIndex: 0,
                              Width: 1, Height: 1, xOffset: -1.05, yOffset: -0.5, yScale: 3276)
        self.GenTraceVertices(tracePointer: SoundOutput!.pointee.SoundBuffer.Waveform.FFTArray, traceCount: Int(SoundOutput!.pointee.SoundBuffer.Waveform.FFTSampleCount)/2, traceIndex: 1,
                              Width: 1, Height: 1, xOffset: 0.05, yOffset: -0.5, yScale: 100000)
        
        memcpy(vertexBuffer.contents(), vertexData, vertexData.count * MemoryLayout.size(ofValue: vertexData[0]))
        
        let scaling = scalingMatrix(xScale: 0.9, yScale: 1.4, zScale: 0.9)
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
    
    
    func GenTraceVertices(tracePointer: UnsafeMutablePointer<Float>, traceCount: Int, traceIndex: Int, Width: Float, Height: Float, xOffset: Float, yOffset: Float, yScale: Float) {
        let xStride = Width / Float(traceVertices)

        var traceCountCapped = traceCount
        if traceCount > traceVertices {
            traceCountCapped = traceVertices
        }
        
        let vertexStart = gridVertices + (traceIndex * traceVertices)
        let vertexEnd = vertexStart + traceVertices
        let start = vertexStart * 8
        let waveStart = start + (((traceVertices - traceCountCapped) / 2) * 8)
        let waveEnd = waveStart + (traceCountCapped * 8)
        
        var traceIndex = 0
        var gridIndex = 0
        for i in vertexStart..<(vertexEnd - 1) {
            var index = i * 8
            
            if index < waveStart  || index >= waveEnd {
                self.vertexData[index++] = xStride * Float(gridIndex) + xOffset
                self.vertexData[index++] = 0
                self.vertexData[index++] = 0
                self.vertexData[index++] = 1
                
                self.vertexData[index++] = 0.0
                self.vertexData[index++] = 1.0
                self.vertexData[index++] = 0.0
                self.vertexData[index++] = 1.0
                
                self.vertexData[index++] = xStride * Float(gridIndex+1) + xOffset
                self.vertexData[index++] = 0
                self.vertexData[index++] = 0
                self.vertexData[index++] = 1
                
                self.vertexData[index++] = 0.0
                self.vertexData[index++] = 1.0
                self.vertexData[index++] = 0.0
                self.vertexData[index++] = 1.0
            }
            else if index < waveEnd {
                self.vertexData[index++] = xStride * Float(gridIndex) + xOffset
                self.vertexData[index++] = Float((tracePointer + Int(traceIndex)).pointee) / yScale // int16 maxval. todo: scale
                self.vertexData[index++] = 0
                self.vertexData[index++] = 1
                
                self.vertexData[index++] = 0.0
                self.vertexData[index++] = 1.0
                self.vertexData[index++] = 0.0
                self.vertexData[index++] = 1.0
                
                self.vertexData[index++] = xStride * Float(gridIndex+1) + xOffset
                self.vertexData[index++] = Float((tracePointer + Int(traceIndex + 1)).pointee) / yScale
                self.vertexData[index++] = 0
                self.vertexData[index++] = 1
                
                self.vertexData[index++] = 0.0
                self.vertexData[index++] = 1.0
                self.vertexData[index++] = 0.0
                self.vertexData[index++] = 1.0
                
                traceIndex++
            }
            gridIndex++
        }
    }
    
    
    func genGrid(Width: Float, Height: Float, xOffset: Float, yOffset: Float, gridIndex: Int) {
        for i in 0...10 {
            for j in 0...9 {
                var index = (i * 10 * 32) + (j * 32) + (gridIndex * 440 * floatsPerVertex)
                
                self.vertexData[index++] = (Width/10 * Float(i) + xOffset)
                self.vertexData[index++] = (Height/10 * Float(j) + yOffset)
                self.vertexData[index++] = (0)
                self.vertexData[index++] = (1)
                
                self.vertexData[index++] = (0.3)
                self.vertexData[index++] = (0.3)
                self.vertexData[index++] = (0.3)
                self.vertexData[index++] = (1)
                
                self.vertexData[index++] = (Width/10 * Float(i) + xOffset)
                self.vertexData[index++] = (Height/10 * Float(j + 1) + yOffset)
                self.vertexData[index++] = (0)
                self.vertexData[index++] = (1)
                
                self.vertexData[index++] = (0.3)
                self.vertexData[index++] = (0.3)
                self.vertexData[index++] = (0.3)
                self.vertexData[index++] = (1)
                
                self.vertexData[index++] = (Width/10 * Float(j) + xOffset)
                self.vertexData[index++] = (Height/10 * Float(i) + yOffset)
                self.vertexData[index++] = (0)
                self.vertexData[index++] = (1)
                
                self.vertexData[index++] = (0.3)
                self.vertexData[index++] = (0.3)
                self.vertexData[index++] = (0.3)
                self.vertexData[index++] = (1)
                
                self.vertexData[index++] = (Width/10 * Float(j + 1) + xOffset)
                self.vertexData[index++] = (Height/10 * Float(i) + yOffset)
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
