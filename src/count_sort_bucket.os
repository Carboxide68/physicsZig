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

bool GT(uint first, uint second) {
    const uint index_first = indices.data[first];
    const uint index_second = indices.data[second];
    const uint64_t first_hash = hashes.data[index_first];
    const uint64_t second_hash = hashes.data[index_second];
    return first_hash > second_hash;
}

bool LT(uint first, uint second) {
    const uint index_first = indices.data[first];
    const uint index_second = indices.data[second];
    const uint64_t first_hash = hashes.data[index_first];
    const uint64_t second_hash = hashes.data[index_second];
    return first_hash < second_hash;
}

void swap(uint first, uint second) {
    const uint tmp = indices.data[first];
    indices.data[first] = indices.data[second];
    indices.data[second] = tmp;
}

void main() {
    uint WorkGroupIndex =
        gl_WorkGroupID.z * gl_NumWorkGroups.x * gl_NumWorkGroups.y +
        gl_WorkGroupID.y * gl_NumWorkGroups.x +
        gl_WorkGroupID.x;
    const uint start = WorkGroupIndex * 256 + gl_LocalInvocationIndex;
    const uint startindex = (start == 0) ? 0 : count.data[start - 1];
    const uint endindex = count.data[start];
    const uint n = endindex - startindex;

    uint gaps[] = {57, 23, 10, 4, 1};

    for (int i = 0; i < gaps.length(); i++) {
        const uint gap = gaps[i];
        for (uint k = gap; k < n; k++) {
            const uint temp_index = indices.data[k+startindex];
            const uint64_t temp_hash = hashes.data[temp_index];

            int j = int(k);
            while (true) {
                if (j < gap) break;
                const uint t_i = indices.data[j+startindex - gap];
                const uint64_t t_h = hashes.data[t_i];
                if (t_h <= temp_hash) break;
                indices.data[j+startindex] = t_i;
                j -= int(gap);
            }
            indices.data[j+startindex] = temp_index;
        }
    }
}

@end
