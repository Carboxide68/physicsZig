@compute
#version 450
#extension GL_ARB_gpu_shader_int64 : enable
#define BUCKET_PRECISION 8

layout(local_size_x = 16, local_size_y = 16, local_size_z = 1) in;

layout(std430, binding = 0) restrict readonly buffer hash_in {

    uint64_t data[];

} hashes;

layout(std430, binding = 1) restrict buffer counting_buffer {

    uint data[];

} count;

layout(std430, binding = 2) restrict coherent buffer indices_in {

    uint data[];

} indices;

void main() {
    uint WorkGroupIndex =
        gl_WorkGroupID.z * gl_NumWorkGroups.x * gl_NumWorkGroups.y +
        gl_WorkGroupID.y * gl_NumWorkGroups.x +
        gl_WorkGroupID.x;
    float WorkGroupStart = float(WorkGroupIndex)/float(gl_NumWorkGroups.x * gl_NumWorkGroups.y * gl_NumWorkGroups.z);
    float WorkGroupEnd = float(WorkGroupIndex+1)/float(gl_NumWorkGroups.x * gl_NumWorkGroups.y * gl_NumWorkGroups.z);
    float start = mix(WorkGroupStart, WorkGroupEnd, float(gl_LocalInvocationIndex)/float(gl_WorkGroupSize.x * gl_WorkGroupSize.y * gl_WorkGroupSize.z));
    float end = mix(WorkGroupStart, WorkGroupEnd, float(gl_LocalInvocationIndex+1)/float(gl_WorkGroupSize.x * gl_WorkGroupSize.y * gl_WorkGroupSize.z));
    uint ustart = uint(hashes.data.length() * start);
    uint uend = uint(hashes.data.length() * end);

    for (uint i = ustart; i < uend; i++) {
        const uint hash = uint(hashes.data[i] >> (64 - 2 * BUCKET_PRECISION ));
        indices.data[atomicAdd(count.data[hash], 1)] = i;
    }
}

@end