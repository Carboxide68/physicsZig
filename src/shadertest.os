@vertex
#version 450 core

layout(location=0) in vec3 in_pos;

uniform mat4 u_model_matrix;
uniform mat4 u_camera_matrix;

void main() {

    gl_Position = vec4(in_pos, 1) * u_model_matrix * u_camera_matrix;

}

@fragment
#version 450 core

uniform vec3 u_color;
out vec4 Color;

void main() {

    Color = vec4(u_color, 1);

}

@end
