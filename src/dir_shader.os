@vertex
#version 460
layout(location=0) in vec2 in_vertex;

uniform vec2 u_position;
uniform mat3 u_camera_matrix;

out vec3 Color;

const float len = 0.1;

void main() {
    vec3 pos = u_camera_matrix * vec3(in_vertex, 0);
    if (dot(in_vertex, in_vertex) > 0.0001) {
        pos = normalize(pos) * len;
    }
    gl_Position = vec4(pos.x + u_position.x, pos.y + u_position.y, 0, 1);
    if (gl_VertexID < 2) {
        Color = vec3(1, 0, 0);
    } else {
        Color = vec3(0, 1, 0);
    }
}

@fragment
#version 460

in vec3 Color;
out vec4 out_Color;

void main() {
    out_Color = vec4(Color, 1);
}

@end
