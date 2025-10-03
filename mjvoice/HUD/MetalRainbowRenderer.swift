import Foundation
import MetalKit
import simd

final class MetalRainbowRenderer: NSObject {
    struct Uniforms {
        var resolution: SIMD2<Float>
        var time: Float
        var intensity: Float
        var rippleProgress: Float
        var rippleStrength: Float
        var rippleWidth: Float
        var rippleSoftness: Float
    }

    enum RendererError: Error {
        case deviceUnavailable
        case libraryUnavailable
    }

    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let pipelineState: MTLRenderPipelineState

    private var startTime: CFTimeInterval = CACurrentMediaTime()
    private var rippleStartTime: CFTimeInterval?

    private(set) var drawableSize: CGSize = .zero

    var audioLevel: Float = 0
    var rippleDuration: CFTimeInterval = 1.0
    var rippleStrength: Float = 0.22
    var rippleWidth: Float = 0.18

    init(mtkView: MTKView) throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw RendererError.deviceUnavailable
        }
        self.device = device

        guard let commandQueue = device.makeCommandQueue() else {
            throw RendererError.deviceUnavailable
        }
        self.commandQueue = commandQueue

        let library: MTLLibrary
        if let bundleLibrary = try? device.makeDefaultLibrary(bundle: .main) {
            library = bundleLibrary
        } else if let defaultLibrary = device.makeDefaultLibrary() {
            library = defaultLibrary
        } else {
            throw RendererError.libraryUnavailable
        }

        mtkView.colorPixelFormat = .bgra8Unorm

        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.label = "Dictation Rainbow Pipeline"
        pipelineDescriptor.vertexFunction = library.makeFunction(name: "rainbow_vertex")
        pipelineDescriptor.fragmentFunction = library.makeFunction(name: "rainbow_fragment")
        pipelineDescriptor.colorAttachments[0].pixelFormat = mtkView.colorPixelFormat

        self.pipelineState = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)

        super.init()

        configure(view: mtkView)
    }

    func configure(view: MTKView) {
        view.device = device
        view.delegate = self
        view.preferredFramesPerSecond = 60
        view.framebufferOnly = false
        view.isPaused = false
        view.enableSetNeedsDisplay = false
        view.colorPixelFormat = .bgra8Unorm
        view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
    }

    func triggerRipple() {
        rippleStartTime = CACurrentMediaTime()
    }

    func updateDrawableSize(_ size: CGSize) {
        drawableSize = size
    }

    private func currentUniforms(for view: MTKView) -> Uniforms {
        let time = Float(CACurrentMediaTime() - startTime)

        var rippleProgress: Float = -1
        if let rippleStartTime {
            let elapsed = CACurrentMediaTime() - rippleStartTime
            if elapsed <= rippleDuration {
                rippleProgress = Float(max(0, min(1, elapsed / rippleDuration)))
            } else {
                self.rippleStartTime = nil
                rippleProgress = -1
            }
        }

        let size = drawableSize == .zero ? view.drawableSize : drawableSize
        return Uniforms(
            resolution: SIMD2(Float(size.width), Float(size.height)),
            time: time,
            intensity: max(0, min(audioLevel, 1)),
            rippleProgress: rippleProgress,
            rippleStrength: rippleStrength,
            rippleWidth: rippleWidth,
            rippleSoftness: 0.18
        )
    }
}

extension MetalRainbowRenderer: MTKViewDelegate {
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        updateDrawableSize(size)
    }

    func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable,
              let descriptor = view.currentRenderPassDescriptor,
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let commandEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else {
            return
        }

        var uniforms = currentUniforms(for: view)
        commandEncoder.setRenderPipelineState(pipelineState)
        commandEncoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 0)
        commandEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
        commandEncoder.endEncoding()

        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}
