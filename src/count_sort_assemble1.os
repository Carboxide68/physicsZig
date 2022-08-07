@compute
#version 450 core

layout(local_size_x = 4, local_size_y = 4, local_size_z = 1) in;

layout(std430, binding = 0) restrict buffer counting_buffer {

    uint data[];

} count;

layout(std430, binding = 1) restrict buffer accum_buffer {

    uint data[128];

} accum;

void main() {
    uint WorkGroupIndex =
        gl_WorkGroupID.z * gl_NumWorkGroups.x * gl_NumWorkGroups.y +
        gl_WorkGroupID.y * gl_NumWorkGroups.x +
        gl_WorkGroupID.x;
    float WorkGroupStart = float(WorkGroupIndex)/float(gl_NumWorkGroups.x * gl_NumWorkGroups.y * gl_NumWorkGroups.z);
    float WorkGroupEnd = float(WorkGroupIndex+1)/float(gl_NumWorkGroups.x * gl_NumWorkGroups.y * gl_NumWorkGroups.z);
    float start = mix(WorkGroupStart, WorkGroupEnd, float(gl_LocalInvocationIndex)/float(gl_WorkGroupSize.x * gl_WorkGroupSize.y * gl_WorkGroupSize.z));
    float end = mix(WorkGroupStart, WorkGroupEnd, float(gl_LocalInvocationIndex+1)/float(gl_WorkGroupSize.x * gl_WorkGroupSize.y * gl_WorkGroupSize.z));
    uint ustart = uint(count.data.length() * start);
    uint uend = uint(count.data.length() * end);

    uint tot = 0;
    for (uint i = ustart; i < uend; i++) {
        uint tmp = count.data[i];
        count.data[i] = tot;
        tot += tmp;
    }
    accum.data[WorkGroupIndex*16 + gl_LocalInvocationIndex] = tot;
}
@end