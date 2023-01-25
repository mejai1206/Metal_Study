import MetalKit


class Renderer: NSObject {
    
    static var device: MTLDevice!
    static var commandQueue: MTLCommandQueue!
    var vertexBuffer: MTLBuffer!
    var pipelineState: MTLRenderPipelineState!
    var angle: Int = 0
    
    init(metalView: MTKView) {
        guard
            let device = MTLCreateSystemDefaultDevice(),
            let commandQueue = device.makeCommandQueue() else {
            fatalError("GPU not available")
        }
        
        Renderer.device = device
        Renderer.commandQueue = commandQueue
        metalView.device = device
        
        let library = device.makeDefaultLibrary()
        let vertexFunction = library?.makeFunction(name: "vertex_main")
        let fragmentFunction = library?.makeFunction(name: "fragment_main")
        
        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.vertexFunction = vertexFunction
        pipelineDescriptor.fragmentFunction = fragmentFunction
        pipelineDescriptor.colorAttachments[0].pixelFormat = metalView.colorPixelFormat
        
        var vertexData: [Float] = [
            //x     y    z       r    g    b
            -0.8,  0.4, 0.0,    1.0, 0.0, 0.0,
             0.4, -0.8, 0.0,    0.0, 1.0, 0.0,
             0.8,  0.8, 0.0,    0.0, 0.0, 1.0
        ]
        
        //device에 활용될 새 버퍼메모리를 할당하고 vertexData복사.
        //처리해야 할 device가 알아야 하는 버퍼의 형태.
        vertexBuffer = device.makeBuffer(bytes: &vertexData,
                                         length: MemoryLayout<Float>.stride * vertexData.count, //byte단위. 4 * 18
                                         options: .storageModeShared) //!?
        
        let vertexDescriptor = MTLVertexDescriptor()
        
        vertexDescriptor.attributes[0].format = .float3 //x, y, z
        vertexDescriptor.attributes[0].offset = 0
        vertexDescriptor.attributes[0].bufferIndex = 0
        
        vertexDescriptor.attributes[1].format = .float3 //r, g, b
        vertexDescriptor.attributes[1].offset = MemoryLayout<Float>.stride * 3
        vertexDescriptor.attributes[1].bufferIndex = 0
        
        vertexDescriptor.layouts[0].stride = MemoryLayout<Float>.stride * 6
        
        
        pipelineDescriptor.vertexDescriptor = vertexDescriptor
        
        do {
            pipelineState = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
        } catch let error {
            fatalError(error.localizedDescription)
        }
        
        super.init()
        metalView.clearColor = MTLClearColor(red: 0.0, green: 0.0,
                                             blue: 0.0, alpha: 1.0)
        metalView.delegate = self
    }
}

extension Renderer: MTKViewDelegate {
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        
    }
    
    
    //    The draw(in:) method is called periodically so we have the chance to redraw the contents of the view with Metal.
    //    This is where we will do most of our work.
    func draw(in view: MTKView) {
        guard
            let renderPassDescriptor = view.currentRenderPassDescriptor,
            let commandBuffer = Renderer.commandQueue.makeCommandBuffer(), //범용적
            let renderCommandEncoder =
                commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else { //렌더링을 위해 encoding하여 buffer에 입력.
            return
        }
        
        renderCommandEncoder.setRenderPipelineState(pipelineState)
        renderCommandEncoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        //그리고자 하는 셰이더에 필요한 전역 vertex buffer 설정.
        // vertex function argument table중 buffer항목 첫번째 인덱스에 설정
        
        let aspect = Float(view.bounds.width) / Float(view.bounds.height)
        
        let scale = float4x4(
            [50,    0,  0,   0],
            [0,    50,  0,   0],
            [0,     0,  1,   0],
            [0,     0,  0,   1]
        )
        
        angle = (angle + 1) % 360
        let rad = Float(angle).degreesToRadians
        
        let rotY = float4x4(
            [cos(rad),  0,  -sin(rad),   0],
            [       0,  1,          0,   0],
            [sin(rad),  0,   cos(rad),   0],
            [       0,  0,          0,   1]
        )
        
        var uniforms = Uniforms()
        
        uniforms.modelMatrix = scale * rotY
        
        uniforms.viewMatrix = float4x4(
            [1,   0,  0,   0],
            [0,   1,  0,   0],
            [0,   0,  1,   0],
            [0,   0,  110, 1]
        )
        
        uniforms.projectionMatrix = perspectiveProjection(fovy: Float(45).degreesToRadians, near: 0.001, far: 1000.0, aspect: aspect)
        
        
        renderCommandEncoder.setVertexBytes(&uniforms,
                                            length: MemoryLayout<Uniforms>.stride, index: 1)
        
        
        renderCommandEncoder.drawPrimitives(type: .triangle,
                                            vertexStart: 0,
                                            vertexCount: 3)
        
        renderCommandEncoder.endEncoding()
        guard let drawable = view.currentDrawable else {
            return
        }
        
        // tells the system to replace the existing contents of the view with the newly-drawn contents when the GPU is done executing the previous commands
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
    
    
    func perspectiveProjection(fovy fov: Float, near: Float, far: Float, aspect: Float) -> matrix_float4x4 {
        let y = 1 / tan(fov * 0.5)
        let x = y / aspect
        let z = far / (far - near)
        let X = float4( x,  0,  0,  0)
        let Y = float4( 0,  y,  0,  0)
        let Z = float4( 0,  0,  z, 1)
        let W = float4( 0,  0,  z * -near,  0)
        var ret = matrix_identity_float4x4
        ret.columns = (X, Y, Z, W)
        return ret
    }
}
