//
//  OpenGLView.swift
//  HelloOpenGL_Swift
//
//  Created by DR on 8/24/15.
//  Copyright (c) 2015 DR. All rights reserved.
//
//  Based on code posted by Ray Wenderlich:
//  http://www.raywenderlich.com/3664/opengl-tutorial-for-ios-opengl-es-2-0
//

import UIKit
import GLKit


/**
 This view is in charge of rendering the video
 **/
class OpenGLView: UIView {

    /**
     *
     **/
    var pixelBuffer: CVPixelBuffer?

    /// function called at the beggining of the render phase
    private var viewWillRender: (OpenGLView) -> Void

    private var _context: EAGLContext?
    private var _colorRenderBuffer = GLuint()
    private var _depthRenderBuffer = GLuint()
    private var _eaglLayer: CAEAGLLayer?


    // organize reference to shader variables locations
    private struct Uniforms {
        var textureSamplerY = GLuint()
        var textureSamplerUV = GLuint()
    }
    private struct Attributes {
        var vertexPosition = GLuint()
    }
    private struct Locations {
        var uniforms = Uniforms()
        var attributes = Attributes()
    }

    // shader variables locations
    private var _locations = Locations()


    // texture
    private var videoTextureCache: CVOpenGLESTextureCache?
    private var lumaTexture: CVOpenGLESTexture?
    private var chromaTexture: CVOpenGLESTexture?

    // buffers
    private var _vertexBuffer = GLuint()
    private var _indexBuffer = GLuint()

    private struct Vertex {
        var position: (Float, Float, Float)
        var texCoord: (Float, Float)
    }
    private var _vertices = [
        Vertex(position: (1, -1, 0), texCoord: (1, 0)),
        Vertex(position: (1, 1, 0), texCoord: (1, 1)),
        Vertex(position: (-1, 1, 0), texCoord: (0, 1)),
        Vertex(position: (-1, -1, 0), texCoord: (0, 0)),
        ]

    private var _indices: [GLubyte] = [
        0, 1, 2,
        2, 3, 0,
        ]


    init(frame: CGRect, viewWillRender: (OpenGLView) -> Void) {
        self.viewWillRender = viewWillRender
        super.init(frame: frame)

        if self.setupLayer() != 0 {
            NSLog("OpenGLView init():  setupLayer() failed")
            return
        }
        if self.setupContext() != 0 {
            NSLog("OpenGLView init():  setupContext() failed")
            return
        }
        if self.setupDepthBuffer() != 0 {
            NSLog("OpenGLView init():  setupDepthBuffer() failed")
            return
        }
        if self.setupRenderBuffer() != 0 {
            NSLog("OpenGLView init():  setupRenderBuffer() failed")
            return
        }
        if self.setupFrameBuffer() != 0 {
            NSLog("OpenGLView init():  setupFrameBuffer() failed")
            return
        }
        if self.compileShaders() != 0 {
            NSLog("OpenGLView init():  compileShaders() failed")
            return
        }
        if self.setupVBOs() != 0 {
            NSLog("OpenGLView init():  setupVBOs() failed")
            return
        }
        if self.setupDisplayLink() != 0 {
            NSLog("OpenGLView init():  setupDisplayLink() failed")
        }
        if self.setupTexture() != 0 {
            NSLog("OpenGLView init():  setupTexture() failed")
        }
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("OpenGLView init(coder:) has not been implemented")
    }

    override public class var layerClass: Swift.AnyClass {
        get {
            return CAEAGLLayer.self
        }
    }
    //override class func layerClass() -> AnyClass {
    //     return CAEAGLLayer.self
    // }

    private func compileShader(_ shaderName: String, shaderType: GLenum, shader: UnsafeMutablePointer<GLuint>) -> Int {
        let shaderPath = Bundle.main.path(forResource: shaderName, ofType:"glsl")
        var error: NSError?
        let shaderString: NSString?
        do {
            shaderString = try NSString(contentsOfFile: shaderPath!, encoding:String.Encoding.utf8.rawValue)
        } catch let error1 as NSError {
            error = error1
            shaderString = nil
        }
        if error != nil {
            NSLog("OpenGLView compileShader():  error loading shader: %@", error!.localizedDescription)
            return -1
        }

        shader.pointee = glCreateShader(shaderType)
        if shader.pointee == 0 {
            NSLog("OpenGLView compileShader():  glCreateShader failed")
            return -1
        }
        var shaderStringUTF8 = shaderString!.utf8String
        var shaderStringLength: GLint = GLint(Int32(shaderString!.length))
        glShaderSource(shader.pointee, 1, &shaderStringUTF8, &shaderStringLength)

        glCompileShader(shader.pointee)
        var success = GLint()
        glGetShaderiv(shader.pointee, GLenum(GL_COMPILE_STATUS), &success)

        if success == GL_FALSE {
            let infoLog = UnsafeMutablePointer<GLchar>.allocate(capacity: 256)
            var infoLogLength = GLsizei()

            glGetShaderInfoLog(shader.pointee, GLsizei(sizeof(GLchar.self) * 256), &infoLogLength, infoLog)
            NSLog("OpenGLView compileShader():  glCompileShader() failed:  %@", String(cString: infoLog))

            infoLog.deallocate(capacity: 256)
            return -1
        }

        return 0
    }

    private func compileShaders() -> Int {
        let vertexShader = UnsafeMutablePointer<GLuint>.allocate(capacity: 1)
        if (self.compileShader("SimpleVertex", shaderType: GLenum(GL_VERTEX_SHADER), shader: vertexShader) != 0 ) {
            NSLog("OpenGLView compileShaders():  compileShader() failed")
            return -1
        }

        let fragmentShader = UnsafeMutablePointer<GLuint>.allocate(capacity: 1)
        if (self.compileShader("SimpleFragment", shaderType: GLenum(GL_FRAGMENT_SHADER), shader: fragmentShader) != 0) {
            NSLog("OpenGLView compileShaders():  compileShader() failed")
            return -1
        }

        let program = glCreateProgram()
        glAttachShader(program, vertexShader.pointee)
        glAttachShader(program, fragmentShader.pointee)
        glLinkProgram(program)

        var success = GLint()

        glGetProgramiv(program, GLenum(GL_LINK_STATUS), &success)
        if success == GL_FALSE {
            let infoLog = UnsafeMutablePointer<GLchar>.allocate(capacity: 1024)
            var infoLogLength = GLsizei()

            glGetProgramInfoLog(program, GLsizei(sizeof(GLchar.self) * 1024), &infoLogLength, infoLog)
            NSLog("OpenGLView compileShaders():  glLinkProgram() failed:  %@", String(cString:  infoLog))

            infoLog.deallocate(capacity: 1024)
            fragmentShader.deallocate(capacity: 1)
            vertexShader.deallocate(capacity: 1)

            return -1
        }

        glUseProgram(program)

        // get variable locations
        _locations.attributes.vertexPosition = GLuint(glGetAttribLocation(program, "aVertexPosition"))
        glEnableVertexAttribArray(_locations.attributes.vertexPosition)

        // texture
        _locations.uniforms.textureSamplerY = GLuint(glGetUniformLocation(program, "SamplerY"))
        _locations.uniforms.textureSamplerUV = GLuint(glGetUniformLocation(program, "SamplerUV"))

        fragmentShader.deallocate(capacity: 1)
        vertexShader.deallocate(capacity: 1)
        return 0
    }

    @objc private func render(displayLink: CADisplayLink) -> Int {
        self.viewWillRender(self)

        // no texture to display yet
        if pixelBuffer == nil {
            return 0
        }

        glBlendFunc(GLenum(GL_ONE), GLenum(GL_ONE_MINUS_SRC_ALPHA))
        glEnable(GLenum(GL_BLEND))
        glClearColor(0, 104.0/255.0, 55.0/255.0, 1.0)
        glClear(GLbitfield(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT))
        glEnable(GLenum(GL_DEPTH_TEST))


        // set view port
        glViewport(0, 0, GLsizei(self.frame.size.width), GLsizei(self.frame.size.height))

        glBindBuffer(GLenum(GL_ARRAY_BUFFER), _vertexBuffer)
        glBindBuffer(GLenum(GL_ELEMENT_ARRAY_BUFFER), _indexBuffer)

        let positionSlotFirstComponent = UnsafePointer<Int>(bitPattern: 0)
        glEnableVertexAttribArray(_locations.attributes.vertexPosition)
        glVertexAttribPointer(_locations.attributes.vertexPosition, 3, GLenum(GL_FLOAT), GLboolean(GL_FALSE), GLsizei(sizeof(Vertex.self)), positionSlotFirstComponent)

        // load texture
        self.refreshTextures()


        let vertexBufferOffset = UnsafePointer<Void>(bitPattern: 0)
        glDrawElements(GLenum(GL_TRIANGLES), GLsizei((_indices.count * sizeof(GLubyte.self))/sizeof(GLubyte.self)),
                       GLenum(GL_UNSIGNED_BYTE), vertexBufferOffset)

        _context!.presentRenderbuffer(Int(GL_RENDERBUFFER))
        return 0
    }

    private func setupContext() -> Int {
        let api: EAGLRenderingAPI = EAGLRenderingAPI.openGLES2
        _context = EAGLContext(api: api)

        if _context == nil {
            NSLog("Failed to initialize OpenGLES 2.0 context")
            return -1
        }
        if !EAGLContext.setCurrent(_context) {
            NSLog("Failed to set current OpenGL context")
            return -1
        }
        return 0
    }

    private func setupDepthBuffer() -> Int {
        glGenRenderbuffers(1, &_depthRenderBuffer)
        glBindRenderbuffer(GLenum(GL_RENDERBUFFER), _depthRenderBuffer)
        glRenderbufferStorage(GLenum(GL_RENDERBUFFER), GLenum(GL_DEPTH_COMPONENT16), GLsizei(self.frame.size.width), GLsizei(self.frame.size.height))
        return 0
    }

    private func setupDisplayLink() -> Int {
        let displayLink: CADisplayLink = CADisplayLink(target: self, selector: #selector(OpenGLView.render(displayLink:)))
        displayLink.add(to: RunLoop.current, forMode: RunLoopMode(rawValue: RunLoopMode.defaultRunLoopMode.rawValue))
        return 0
    }

    private func setupFrameBuffer() -> Int {
        var framebuffer: GLuint = 0
        glGenFramebuffers(1, &framebuffer)
        glBindFramebuffer(GLenum(GL_FRAMEBUFFER), framebuffer)
        glFramebufferRenderbuffer(GLenum(GL_FRAMEBUFFER), GLenum(GL_COLOR_ATTACHMENT0),
                                  GLenum(GL_RENDERBUFFER), _colorRenderBuffer)
        glFramebufferRenderbuffer(GLenum(GL_FRAMEBUFFER), GLenum(GL_DEPTH_ATTACHMENT), GLenum(GL_RENDERBUFFER), _depthRenderBuffer)
        return 0
    }

    private func setupLayer() -> Int {
        _eaglLayer = self.layer as? CAEAGLLayer
        if _eaglLayer == nil {
            NSLog("setupLayer:  _eaglLayer is nil")
            return -1
        }
        _eaglLayer!.isOpaque = true
        return 0
    }

    func refreshTextures() -> Void {
        guard let pixelBuffer = pixelBuffer else { return }
        let textureWidth: GLsizei = GLsizei(CVPixelBufferGetWidth(pixelBuffer))
        let textureHeight: GLsizei = GLsizei(CVPixelBufferGetHeight(pixelBuffer))

        guard let videoTextureCache = videoTextureCache else { return }

        self.cleanUpTextures()

        // Y plane
        glActiveTexture(GLenum(GL_TEXTURE0))

        var err = CVOpenGLESTextureCacheCreateTextureFromImage(kCFAllocatorDefault,
                                                           videoTextureCache,
                                                           pixelBuffer,
                                                           nil,
                                                           GLenum(GL_TEXTURE_2D),
                                                           GL_RED_EXT,
                                                           textureWidth,
                                                           textureHeight,
                                                           GLenum(GL_RED_EXT),
                                                           GLenum(GL_UNSIGNED_BYTE),
                                                           0,
                                                           &lumaTexture)

        if err != kCVReturnSuccess {
            print("Error at CVOpenGLESTextureCacheCreateTextureFromImage %d", err)
            return
        }
        guard let lumaTexture = lumaTexture else { return }

        glBindTexture(CVOpenGLESTextureGetTarget(lumaTexture), CVOpenGLESTextureGetName(lumaTexture))
        glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_MIN_FILTER), GL_LINEAR)
        glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_MAG_FILTER), GL_LINEAR)
        glTexParameterf(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_WRAP_S), GLfloat(GL_CLAMP_TO_EDGE))
        glTexParameterf(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_WRAP_T), GLfloat(GL_CLAMP_TO_EDGE))


        // UV plane
        glActiveTexture(GLenum(GL_TEXTURE1))

        err = CVOpenGLESTextureCacheCreateTextureFromImage(kCFAllocatorDefault,
                                                               videoTextureCache,
                                                               pixelBuffer,
                                                               nil,
                                                               GLenum(GL_TEXTURE_2D),
                                                               GL_RG_EXT,
                                                               textureWidth/2,
                                                               textureHeight/2,
                                                               GLenum(GL_RG_EXT),
                                                               GLenum(GL_UNSIGNED_BYTE),
                                                               1,
                                                               &chromaTexture)

        if err != kCVReturnSuccess {
            print("Error at CVOpenGLESTextureCacheCreateTextureFromImage %d", err)
            return
        }
        guard let chromaTexture = chromaTexture else { return }

        glBindTexture(CVOpenGLESTextureGetTarget(chromaTexture), CVOpenGLESTextureGetName(chromaTexture))
        glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_MIN_FILTER), GL_LINEAR)
        glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_MAG_FILTER), GL_LINEAR)
        glTexParameterf(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_WRAP_S), GLfloat(GL_CLAMP_TO_EDGE))
        glTexParameterf(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_WRAP_T), GLfloat(GL_CLAMP_TO_EDGE))
    }

    private func setupTexture() -> Int {
        // init cache
        let err = CVOpenGLESTextureCacheCreate(kCFAllocatorDefault, nil, _context!, nil, &videoTextureCache)
        if err != kCVReturnSuccess {
            print("!!!Error at CVOpenGLESTextureCacheCreate %d", err)
            return -1
        }

        return 0
    }

    private func cleanUpTextures() -> Void {
        if lumaTexture != nil {
            lumaTexture = nil
        }
        if chromaTexture != nil {
            chromaTexture = nil
        }

        // Periodic texture cache flush every frame
        if let videoTextureCache = videoTextureCache {
            CVOpenGLESTextureCacheFlush(videoTextureCache, 0)
        }
    }

    private func setupRenderBuffer() -> Int {
        glGenRenderbuffers(1, &_colorRenderBuffer)
        glBindRenderbuffer(GLenum(GL_RENDERBUFFER), _colorRenderBuffer)

        if _context == nil {
            NSLog("setupRenderBuffer():  _context is nil")
            return -1
        }
        if _eaglLayer == nil {
            NSLog("setupRenderBuffer():  _eagLayer is nil")
            return -1
        }
        if (_context!.renderbufferStorage(Int(GL_RENDERBUFFER), from: _eaglLayer!) == false) {
            NSLog("setupRenderBuffer():  renderbufferStorage() failed")
            return -1
        }
        return 0
    }

    private func setupVBOs() -> Int {
        // first object
        glGenBuffers(1, &_vertexBuffer)
        glBindBuffer(GLenum(GL_ARRAY_BUFFER), _vertexBuffer)
        glBufferData(GLenum(GL_ARRAY_BUFFER), (_vertices.count * sizeof(Vertex.self)), _vertices, GLenum(GL_STATIC_DRAW))

        glGenBuffers(1, &_indexBuffer)
        glBindBuffer(GLenum(GL_ELEMENT_ARRAY_BUFFER), _indexBuffer)
        glBufferData(GLenum(GL_ELEMENT_ARRAY_BUFFER), (_indices.count * sizeof(GLubyte.self)), _indices, GLenum(GL_STATIC_DRAW))
        return 0
    }
}
