@compute
#version 450
#extension GL_ARB_gpu_shader_int64 : enable

layout(local_size_x = 16, local_size_y = 16, local_size_z = 1) in;

layout(std430, binding = 0) restrict readonly buffer hash_in {

    uint64_t data[];

} hashes;

layout(std430, binding = 1) restrict readonly buffer counting_buffer {

    uint data[];

} count;

layout(std430, binding = 2) restrict buffer indices_in {

    uint data[];

} indices;

void main() {
    uint WorkGroupIndex =
        gl_WorkGroupID.z * gl_NumWorkGroups.x * gl_NumWorkGroups.y +
        gl_WorkGroupID.y * gl_NumWorkGroups.x +
        gl_WorkGroupID.x;
    uint start = WorkGroupIndex * 256 + gl_LocalInvocationIndex;
    uint startindex = (start == 0) ? 0 : count.data[start - 1];
    uint endindex = count.data[start];
    uint n = endindex - startindex;

    uint gaps[] = {57, 23, 10, 4, 1};

    for (int i = 0; i < 5; i++) {
        const uint gap = gaps[i];
        for (uint k = gap; k < n; k++) {
            uint temp = indices.data[k+startindex];
            uint64_t temp_hash = hashes.data[temp];
            uint j = k;
            for (; hashes.data[indices.data[j - gap + startindex]] > temp_hash; j -= gap) {
                indices.data[j+startindex] = indices.data[j - gap + startindex];
            }
            indices.data[j+startindex] = temp;
        }
    }
}

@end