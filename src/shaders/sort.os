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

layout(std430, binding = 2) restrict readonly buffer copy {
	Point points[];
} c;

layout(std430, binding = 3) restrict coherent buffer buckets {
	uint buckets[];
} b;

layout(std430, binding = 5) restrict buffer invocation_buffer {
	uvec2 data[];
} inv;

void main() {
    uint WorkGroupIndex =
        gl_WorkGroupID.z * gl_NumWorkGroups.x * gl_NumWorkGroups.y +
        gl_WorkGroupID.y * gl_NumWorkGroups.x +
        gl_WorkGroupID.x;
	const float WGS =  float(gl_NumWorkGroups.x * gl_NumWorkGroups.y * gl_NumWorkGroups.z);
	const float WorkGroupStart = float(WorkGroupIndex)/WGS;
    const float WorkGroupEnd = float(WorkGroupIndex+1)/WGS;
	const float INV_PER_WG = float(gl_WorkGroupSize.x * gl_WorkGroupSize.y * gl_WorkGroupSize.z);
	const float start = mix(WorkGroupStart, WorkGroupEnd, 
		float(gl_LocalInvocationIndex)/INV_PER_WG);
    const float end = mix(WorkGroupStart, WorkGroupEnd, 
		float(gl_LocalInvocationIndex+1)/INV_PER_WG);
    const uint ustart = uint(c.points.length() * start);
    const uint uend = uint(c.points.length() * end);

	for (uint i = ustart; i < uend; i++) {
		const Point point = c.points[i];
		uint bucket = atomicAdd(b.buckets[point.hash], 1);
		bucket += b.buckets[b.buckets.length() - 16 
					+ uint(floor(float(point.hash)/pow(2, 16 - 4)))];
		//inv.data[WorkGroupIndex * uint(INV_PER_WG) + gl_LocalInvocationIndex] = uvec2(point.hash, uint(floor(float(point.hash)/pow(2, 16 - 4))));
		ps.points[bucket] = point;
	}
}

@end