uniform sampler2D SamplerY;
uniform sampler2D SamplerUV;

varying mediump vec2 vCoords;

void main(void) {
    mediump vec3 yuv;
    mediump vec3 rgb;
    
    yuv.x = texture2D(SamplerY, vCoords).r;
    yuv.yz = texture2D(SamplerUV, vCoords).rg - vec2(0.5, 0.5);
    
    // Using BT.709 which is the standard for HDTV (see https://developer.apple.com/library/ios/samplecode/GLCameraRipple/Listings/GLCameraRipple_Shaders_Shader_fsh.html#//apple_ref/doc/uid/DTS40011222-GLCameraRipple_Shaders_Shader_fsh-DontLinkElementID_9)
    rgb = mat3(      1,       1,      1,
               0, -.18732, 1.8556,
               1.57481, -.46813,      0) * vec3(yuv.xyz);
    
    gl_FragColor = vec4(rgb, 1.0);
}
