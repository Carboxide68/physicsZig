@compute
#version 450 core

layout(local_size_x = 16, local_size_y = 16, local_size_z = 4) in;

struct Point {
	vec2 pos;
	uint id;
	uint hash;
};

layout(std430, binding = 0) restrict writeonly buffer points {
	Point points[];
} ps;

layout(std430, binding = 1) restrict buffer Invocation_Data {
	uvec4 data[];
} inv;

layout(std430, binding = 2) restrict readonly buffer copy {
	Point points[];
} c;

layout(std430, binding = 3) restrict buffer buckets {
	uint buckets[];
} b;

void main() {
    uint WorkGroupIndex =
        gl_WorkGroupID.z * gl_NumWorkGroups.x * gl_NumWorkGroups.y +
        gl_WorkGroupID.y * gl_NumWorkGroups.x +
        gl_WorkGroupID.x;
	const float WGS =  float(gl_NumWorkGroups.x * gl_NumWorkGroups.y * gl_NumWorkGroups.z);
	const float INV_PER_WG = float(gl_WorkGroupSize.x * gl_WorkGroupSize.y * gl_WorkGroupSize.z);
	const float WorkGroupStart = float(WorkGroupIndex)/WGS;
    const float WorkGroupEnd = float(WorkGroupIndex+1)/WGS;
	const float start = mix(WorkGroupStart, WorkGroupEnd, 
		float(gl_LocalInvocationIndex)/INV_PER_WG);
    const float end = mix(WorkGroupStart, WorkGroupEnd, 
		float(gl_LocalInvocationIndex+1)/INV_PER_WG);
    const uint ustart = uint(c.points.length() * start);
    const uint uend = uint(c.points.length() * end);
    const uint INV = gl_LocalInvocationIndex + uint(INV_PER_WG) * WorkGroupIndex;

	for (uint i = ustart; i < uend; i++) {
		const Point point = c.points[i];
		uint bucket = atomicAdd(b.buckets[point.hash], 1);
		inv.data[i].x = bucket;
		bucket += b.buckets[b.buckets.length() - 16 
					+ uint(floor(float(point.hash)/pow(2, 16 - 4)))];
		inv.data[i].y = uint(floor(float(point.hash)/pow(2, 16 - 4)));
		inv.data[i].z = point.hash;
		ps.points[bucket] = point;
	}
}

@end