attribute vec4 aVertexPosition;

varying vec2 vCoords;

void main(void) {
    gl_Position = aVertexPosition;
    vCoords = 0.5 + aVertexPosition.xy * 0.5;
    vCoords.y = 1.0 - vCoords.y;
}
