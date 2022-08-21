@compute
#version 450 core
#extension GL_ARB_gpu_shader_int64 : enable

layout(local_size_x = 16, local_size_y = 16, local_size_z = 1) in;

layout(std430, binding = 0) restrict readonly buffer points_in {

    vec2 data[];

} points;

layout(std430, binding = 1) restrict writeonly buffer hash_out {

    uint64_t data[];

} hashes;

uniform vec2 u_config_size;
uniform vec2 u_config_pos;
uniform uint u_config_maxdepth;


uint64_t hash(vec2 point) {

    float xpos = (point.x - u_config_pos.x)/u_config_size.x;
    float ypos = (point.y - u_config_pos.y)/u_config_size.y;

    if (xpos > 1.0 || xpos < -1.0 ||
        ypos > 1.0 || ypos < -1.0    ) {
        return ~0ul;
    }

    uint64_t result = 0;
    uint64_t exponent = 1UL << 62;
    for (uint i = 0; i < u_config_maxdepth; i++) {
        const uint x_flag = (xpos > 0) ? 1 : 0;
        const uint y_flag = (ypos > 0) ? 0 : 1;

        result |= exponent * uint64_t(x_flag | y_flag*2u);
        exponent = exponent/4;

        xpos = (xpos*2.0) + (1.0 - 2.0*float(x_flag));
        ypos = (ypos*2.0) + (1.0 - 2.0*float(1 - y_flag));
    }

    return result;
}

void main() {

    uint index = gl_WorkGroupID.x * gl_WorkGroupSize.x * gl_WorkGroupSize.y * gl_WorkGroupSize.z + gl_LocalInvocationIndex;

    if (index >= points.data.length()) return;

    vec2 point = points.data[index];
    hashes.data[index] = hash(point);

}

@end
