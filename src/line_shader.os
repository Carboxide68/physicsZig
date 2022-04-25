@vertex
#version 450 core

layout(location=0) in vec2 in_Pos;

uniform mat3 u_model_matrix;
uniform mat3 u_assembled_matrix;

void main() {
    gl_Position = vec4(u_assembled_matrix * u_model_matrix * vec3(in_Pos, 1), 1);
    gl_Position.z = 1;
}

@fragment
#version 450 core

out vec4 Color;

void main() {

    Color = vec4(0, 0, 0, 1);

}

@end
