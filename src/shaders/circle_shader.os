@vertex
#version 450 core

layout(location=0) in vec2 in_Pos;

struct Point {
    vec2 pos;
    uint id;
    uint hash;
};

layout(std430, binding=0) restrict readonly buffer sphere_positions {
    Point points[];
} ps;

layout(std430, binding=1) restrict readonly buffer auxillary_data {
    vec2 vel[];
} aux;


out flat uint instance;

uniform float u_radius;
uniform mat3 u_assembled_matrix;

void main() {

    const Point point = ps.points[gl_InstanceID];
    const uint id = point.id;
    const vec2 pos = point.pos;
    const mat3 model_matrix = mat3(
        u_radius, 0, 0,
        0, u_radius, 0,
        -pos.x, -pos.y, 1
        );
    gl_Position = vec4(u_assembled_matrix * model_matrix * vec3(in_Pos, 1), 1);
    gl_Position.z = 1;
    instance = id;
}

@fragment
#version 450 core

in flat uint instance;

out vec4 Color;

void main() {

    Color = vec4(float(instance % 1000)/1000, float(instance % 100)/100, float(instance % 10)/10, 1);

}

@end
