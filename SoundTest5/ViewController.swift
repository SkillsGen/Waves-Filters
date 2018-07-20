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
    var waveFormScalingX: Float = 1.0
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
    let traceVertices = 2048
    var totalVertices: Int!
    let floatsPerVertex = 8
    
    var vertexData: [Float] = []
    
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        setupUI()
        
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
        metalLayer.frame = CGRect(x: 0, y: 20, width: view.layer.frame.width, height: view.layer.frame.height/2)
        view.layer.addSublayer(metalLayer)
        
        let dataSize = vertexData.count * MemoryLayout.size(ofValue: vertexData[0])
        vertexBuffer = device.makeBuffer(bytes: vertexData, length: dataSize, options: [])
        
        var scaling = scalingMatrix(xScale: 1.0, yScale: 1.0, zScale: 1.0)
        let matrixSize = MemoryLayout<Float>.size * 16
        var waveStretch = scalingMatrix(xScale: self.waveFormScalingX, yScale: 1.0, zScale: 1.0)
        uniformBuffer = device.makeBuffer(length: matrixSize * 2, options: [])
        memcpy(uniformBuffer.contents(), &scaling, matrixSize)
        memcpy(uniformBuffer.contents() + matrixSize, &waveStretch, matrixSize)
        
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
        self.SoundOutput?.pointee.SoundBuffer.ToneHz = Int32(self.freqDialView.value)
        self.SoundOutput?.pointee.SoundBuffer.FilterFrequency = Int32(self.cutDialView.value)
        self.SoundOutput?.pointee.SoundBuffer.Q = self.qDialView.value
        
        WriteSamples(self.SoundOutput)
        
        self.GenTraceVertices(tracePointer: SoundOutput!.pointee.SoundBuffer.Waveform.WaveformArray, traceCount: Int(SoundOutput!.pointee.SoundBuffer.Waveform.WaveformArrayLength), traceIndex: 0,
                              Width: 1, Height: 1, xOffset: -1.05, yOffset: 0.0, yScale: 3276)
        self.GenTraceVertices(tracePointer: SoundOutput!.pointee.SoundBuffer.Waveform.FFTArray, traceCount: Int(SoundOutput!.pointee.SoundBuffer.Waveform.FFTSampleCount)/2, traceIndex: 1,
                              Width: 1, Height: 1, xOffset: 0.05, yOffset: -0.5, yScale: 1000000)
        
        memcpy(vertexBuffer.contents(), vertexData, vertexData.count * MemoryLayout.size(ofValue: vertexData[0]))
        
        let scaling = scalingMatrix(xScale: 0.9, yScale: 1.4, zScale: 0.9)
        let rotation = rotationMatrix(rotVector: float3(0.0, 0.0, 0.0)) * scaling
        var translation = translationMatrix(position: float3(0.0, 0.0, 0.0)) * rotation

        let matrixSize = MemoryLayout<Float>.size * 16
        memcpy(uniformBuffer.contents(), &translation, matrixSize)
        
        waveFormScalingX = waveFormScalingXSlider.value
        var waveStretch = scalingMatrix(xScale: waveFormScalingX, yScale: 1.0, zScale: 1.0)
        memcpy(uniformBuffer.contents() + matrixSize, &waveStretch, matrixSize)
        
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
        let xStride = Width / Float(traceVertices/2)

        var traceCountCapped = traceCount
        if traceCount > traceVertices/2 {
            traceCountCapped = traceVertices/2
        }
        
        let start = (gridVertices + (traceIndex * traceVertices)) * 8
        let end = start + traceVertices * 8
        let waveStart = start + (traceVertices - traceCountCapped*2) * 4
        let waveEnd = waveStart + (traceCountCapped * 8 * 2)

        var traceIndex = 0
        var gridIndex = 0
        
        var index = start
        while index < end {
            if index < waveStart  || index > waveEnd {
                self.vertexData[index++] = xStride * Float(gridIndex) + xOffset
                self.vertexData[index++] = yOffset
                self.vertexData[index++] = 0.1
                self.vertexData[index++] = 1
                
                self.vertexData[index++] = 0.0
                self.vertexData[index++] = 1.0
                self.vertexData[index++] = 0.0
                self.vertexData[index++] = 1.0
                
                self.vertexData[index++] = xStride * Float(gridIndex+1) + xOffset
                self.vertexData[index++] = yOffset
                self.vertexData[index++] = 0.1
                self.vertexData[index++] = 1
                
                self.vertexData[index++] = 0.0
                self.vertexData[index++] = 1.0
                self.vertexData[index++] = 0.0
                self.vertexData[index++] = 1.0
                
                if index >= waveStart && index < waveEnd {
                    self.vertexData[index++] = xStride * Float(gridIndex) + xOffset
                    self.vertexData[index++] = yOffset
                    self.vertexData[index++] = 0.1
                    self.vertexData[index++] = 1
                    
                    self.vertexData[index++] = 0.0
                    self.vertexData[index++] = 1.0
                    self.vertexData[index++] = 0.0
                    self.vertexData[index++] = 1.0
                    
                    self.vertexData[index++] = xStride * Float(gridIndex+1) + xOffset
                    self.vertexData[index++] = (tracePointer + Int(traceIndex)).pointee / yScale + yOffset
                    self.vertexData[index++] = 0.1
                    self.vertexData[index++] = 1
                    
                    self.vertexData[index++] = 0.0
                    self.vertexData[index++] = 1.0
                    self.vertexData[index++] = 0.0
                    self.vertexData[index++] = 1.0
                }
            }
            else {
                self.vertexData[index++] = xStride * Float(gridIndex) + xOffset
                self.vertexData[index++] = (tracePointer + Int(traceIndex)).pointee / yScale + yOffset
                self.vertexData[index++] = 0.1
                self.vertexData[index++] = 1
                
                self.vertexData[index++] = 0.0
                self.vertexData[index++] = 1.0
                self.vertexData[index++] = 0.0
                self.vertexData[index++] = 1.0
                
                self.vertexData[index++] = xStride * Float(gridIndex+1) + xOffset
                self.vertexData[index++] = (tracePointer + Int(traceIndex + 1)).pointee / yScale + yOffset
                self.vertexData[index++] = 0.1
                self.vertexData[index++] = 1
                
                self.vertexData[index++] = 0.0
                self.vertexData[index++] = 1.0
                self.vertexData[index++] = 0.0
                self.vertexData[index++] = 1.0
                traceIndex++
                
                if index >= waveEnd && index < end {
                    self.vertexData[index++] = xStride * Float(gridIndex) + xOffset
                    self.vertexData[index++] = (tracePointer + Int(traceIndex)).pointee / yScale + yOffset
                    self.vertexData[index++] = 0.1
                    self.vertexData[index++] = 1
                    
                    self.vertexData[index++] = 0.0
                    self.vertexData[index++] = 1.0
                    self.vertexData[index++] = 0.0
                    self.vertexData[index++] = 1.0
                    
                    self.vertexData[index++] = xStride * Float(gridIndex+1) + xOffset
                    self.vertexData[index++] = yOffset
                    self.vertexData[index++] = 0.1
                    self.vertexData[index++] = 1
                    
                    self.vertexData[index++] = 0.0
                    self.vertexData[index++] = 1.0
                    self.vertexData[index++] = 0.0
                    self.vertexData[index++] = 1.0
                }
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
    
    //
    //interface
    //
    @IBOutlet weak var waveFormScalingXSlider: UISlider!
    
    var waveButtonView: UIImageView!
    var filterButtonView: UIImageView!
    var BGBottomView: UIImageView!
    var freqDialView: UIDialImageView!
    var gainDialView: UIDialImageView!
    var cutDialView: UIDialImageView!
    var qDialView: UIDialImageView!
    
    func setupUI() {
        let xScale = self.view.frame.width / 2732
        let yScale = self.view.frame.height / 2048
        
        waveButtonView = UIImageView(frame: CGRect(x: 0, y: self.view.frame.height/2 + 20, width: self.view.frame.width/2, height: 580 * yScale))
        waveButtonView.contentMode = .scaleAspectFit
        waveButtonView.image = #imageLiteral(resourceName: "WB Sine 1366-580")
        self.view.addSubview(waveButtonView)
        
        let signButton = waveButton(waveform: Sine)
        signButton.frame = CGRect(x: 145 * xScale, y: self.view.frame.height - 762 * yScale, width: 144 * xScale, height: 130 * yScale)
        signButton.addTarget(self, action: #selector(waveButtonTapped), for: .touchUpInside)
        self.view.addSubview(signButton)
        
        let triangleButton = waveButton(waveform: Triangle)
        triangleButton.frame = CGRect(x: (145 + 136) * xScale, y: self.view.frame.height - 762 * yScale, width: 144 * xScale, height: 130 * yScale)
        triangleButton.addTarget(self, action: #selector(waveButtonTapped), for: .touchUpInside)
        self.view.addSubview(triangleButton)
        
        let noiseButton = waveButton(waveform: Noise)
        noiseButton.frame = CGRect(x: (145 + 136 + 132) * xScale, y: self.view.frame.height - 762 * yScale, width: 144 * xScale, height: 130 * yScale)
        noiseButton.addTarget(self, action: #selector(waveButtonTapped), for: .touchUpInside)
        self.view.addSubview(noiseButton)
        
        let squareButton = waveButton(waveform: Square)
        squareButton.frame = CGRect(x: 145 * xScale, y: self.view.frame.height - (762 - 130) * yScale, width: 144 * xScale, height: 130 * yScale)
        squareButton.addTarget(self, action: #selector(waveButtonTapped), for: .touchUpInside)
        self.view.addSubview(squareButton)
        
        let sawButton = waveButton(waveform: Sawtooth)
        sawButton.frame = CGRect(x: (145 + 136) * xScale, y: self.view.frame.height - (762 - 130) * yScale, width: 144 * xScale, height: 130 * yScale)
        sawButton.addTarget(self, action: #selector(waveButtonTapped), for: .touchUpInside)
        self.view.addSubview(sawButton)
        
        filterButtonView = UIImageView(frame: CGRect(x: self.view.frame.width/2, y: self.view.frame.height/2 + 20, width: self.view.frame.width/2, height: 580 * yScale))
        filterButtonView.contentMode = .scaleAspectFit
        filterButtonView.image = #imageLiteral(resourceName: "FilterButtons 1366-580")
        self.view.addSubview(filterButtonView)
        
        let lowButton = filterButton(filter: ExponentialLowPass)
        lowButton.frame = CGRect(x: 1510 * xScale, y: self.view.frame.height - 765 * yScale, width: 145 * xScale, height: 136 * yScale)
        lowButton.addTarget(self, action: #selector(filterButtonTapped), for: .touchUpInside)
        self.view.addSubview(lowButton)
        
        let BQLPButton = filterButton(filter: BiQuadLowPass)
        BQLPButton.frame = CGRect(x: (1510 + 145) * xScale, y: self.view.frame.height - 765 * yScale, width: 202 * xScale, height: 136 * yScale)
        BQLPButton.addTarget(self, action: #selector(filterButtonTapped), for: .touchUpInside)
        self.view.addSubview(BQLPButton)
        
        let ConstButton = filterButton(filter: ConstSkirtBandPass)
        ConstButton.frame = CGRect(x: (1510 + 145 + 202) * xScale, y: self.view.frame.height - 765 * yScale, width: 205 * xScale, height: 136 * yScale)
        ConstButton.addTarget(self, action: #selector(filterButtonTapped), for: .touchUpInside)
        self.view.addSubview(ConstButton)
        
        let NoButton = filterButton(filter: NoFilter)
        NoButton.frame = CGRect(x: (1510 + 145 + 202 + 205) * xScale, y: self.view.frame.height - 765 * yScale, width: 150 * xScale, height: 136 * yScale)
        NoButton.addTarget(self, action: #selector(filterButtonTapped), for: .touchUpInside)
        self.view.addSubview(NoButton)
        
        let highButton = filterButton(filter: ExponentialHighPass)
        highButton.frame = CGRect(x: 1510 * xScale, y: self.view.frame.height - (765 - 136) * yScale, width: 145 * xScale, height: 145 * yScale)
        highButton.addTarget(self, action: #selector(filterButtonTapped), for: .touchUpInside)
        self.view.addSubview(highButton)
        
        let BQHPButton = filterButton(filter: BiQuadHighPass)
        BQHPButton.frame = CGRect(x: (1510 + 145) * xScale, y: self.view.frame.height - (765 - 136) * yScale, width: 202 * xScale, height: 145 * yScale)
        BQHPButton.addTarget(self, action: #selector(filterButtonTapped), for: .touchUpInside)
        self.view.addSubview(BQHPButton)
        
        let zeroButton = filterButton(filter: ZeroPeakGainBandPass)
        zeroButton.frame = CGRect(x: (1510 + 145 + 202) * xScale, y: self.view.frame.height - (765 - 136) * yScale, width: 205 * xScale, height: 145 * yScale)
        zeroButton.addTarget(self, action: #selector(filterButtonTapped), for: .touchUpInside)
        self.view.addSubview(zeroButton)
        
        let notchButton = filterButton(filter: Notch)
        notchButton.frame = CGRect(x: (1510 + 145 + 202 + 205) * xScale, y: self.view.frame.height - (765 - 136) * yScale, width: 150 * xScale, height: 145 * yScale)
        notchButton.addTarget(self, action: #selector(filterButtonTapped), for: .touchUpInside)
        self.view.addSubview(notchButton)
        
        BGBottomView = UIImageView(frame: CGRect(x: 0, y: self.view.frame.height/2 + 20 + (580 * yScale), width: self.view.frame.width, height: 395 * yScale))
        BGBottomView.contentMode = .scaleAspectFill
        BGBottomView.image = #imageLiteral(resourceName: "BG Bottom - 2732-424")
        self.view.addSubview(BGBottomView)
        
        let freqDialFrame: CGRect = CGRect(x: 258 * xScale, y: (self.view.frame.height - ((150 + 148) * yScale)), width: 143 * xScale, height: 148 * yScale)
        freqDialView = UIDialImageView(frame: freqDialFrame, viewForGesture: self.view, angleMinOffset: -0.22, valMin: 40, valMax: 6000)
        freqDialView.image = #imageLiteral(resourceName: "FreqDial 258-165")
        self.view.addSubview(freqDialView)
        
        let gainDialFrame: CGRect = CGRect(x: 573 * xScale, y: (self.view.frame.height - ((150 + 148) * yScale)), width: 143 * xScale, height: 148 * yScale)
        gainDialView = UIDialImageView(frame: gainDialFrame, viewForGesture: self.view, angleMinOffset: -0.22, valMin: 40, valMax: 6000)
        gainDialView.image = #imageLiteral(resourceName: "GainDial 574-171")
        self.view.addSubview(gainDialView)
        
        let cutDialFrame: CGRect = CGRect(x: 1620 * xScale, y: (self.view.frame.height - ((150 + 148) * yScale)), width: 143 * xScale, height: 148 * yScale)
        cutDialView = UIDialImageView(frame: cutDialFrame, viewForGesture: self.view, angleMinOffset: -1.42, valMin: 10, valMax: 20000)
        cutDialView.image = #imageLiteral(resourceName: "CutDial 1619-169")
        self.view.addSubview(cutDialView)
        
        let qDialFrame: CGRect = CGRect(x: 1931 * xScale, y: (self.view.frame.height - ((150 + 158) * yScale)), width: 143 * xScale, height: 148 * yScale)
        qDialView = UIDialImageView(frame: qDialFrame, viewForGesture: self.view, angleMinOffset: -0.22, valMin: 0.01, valMax: 10)
        qDialView.image = #imageLiteral(resourceName: "QDial 1937-174")
        self.view.addSubview(qDialView)
    }
    
    @objc func waveButtonTapped(sender: waveButton) {
        self.WaveformType = sender.waveform
        
        switch sender.waveform {
        case Sine:
            waveButtonView.image = #imageLiteral(resourceName: "WB Sine 1366-580")
        case Triangle:
            waveButtonView.image = #imageLiteral(resourceName: "WB Triangle 1366-580")
        case Noise:
            waveButtonView.image = #imageLiteral(resourceName: "WB Noise 1366-580")
        case Square:
            waveButtonView.image = #imageLiteral(resourceName: "WB Square 1366-580")
        case Sawtooth:
            waveButtonView.image = #imageLiteral(resourceName: "WB Saw 1366-580")
        default:
            self.WaveformType = Sine
            waveButtonView.image = #imageLiteral(resourceName: "WB Sine 1366-580")
        }
    }
    
    @objc func filterButtonTapped(sender: filterButton) {
        self.FilterType = sender.filter
        
        switch sender.filter {
        case ExponentialLowPass:
            filterButtonView.image = #imageLiteral(resourceName: "FB Low 1366-580")
        case BiQuadLowPass:
            filterButtonView.image = #imageLiteral(resourceName: "FB BQLP 1366-580")
        case ConstSkirtBandPass:
            filterButtonView.image = #imageLiteral(resourceName: "FB Const 1366-580")
        case NoFilter:
            filterButtonView.image = #imageLiteral(resourceName: "FB No 1366-580")
        case ExponentialHighPass:
            filterButtonView.image = #imageLiteral(resourceName: "FB High 1366-580")
        case BiQuadHighPass:
            filterButtonView.image = #imageLiteral(resourceName: "FB BQHP 1366-580")
        case ZeroPeakGainBandPass:
            filterButtonView.image = #imageLiteral(resourceName: "FB 0 1366-580")
        case Notch:
            filterButtonView.image = #imageLiteral(resourceName: "FB Notch 1366-580")
        default:
            self.FilterType = NoFilter
            filterButtonView.image = #imageLiteral(resourceName: "FB No 1366-580")
        }
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
}
