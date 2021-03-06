@vertex
#version 450 core

layout(location=0) in vec2 in_Pos;

layout(std430, binding=0) restrict buffer sphere_positions {
    vec2 pos[];
} in_pos;

uniform float u_radius;
uniform mat3 u_assembled_matrix;

void main() {

    const vec2 center_position = in_pos.pos[gl_InstanceID];
    const mat3 model_matrix = mat3(
        u_radius, 0, 0,
        0, u_radius, 0,
        center_position.x, center_position.y, 1
        );
    gl_Position = vec4(u_assembled_matrix * model_matrix * vec3(in_Pos, 1), 1);
    gl_Position.z = 1;

}


@fragment
#version 450 core

uniform vec3 u_color;
out vec4 Color;

void main() {

    Color = vec4(u_color, 1);

}

@end
