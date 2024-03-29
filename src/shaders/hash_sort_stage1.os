@compute
#version 450 core

struct Point {
	vec2 pos,
	uint id,
	uint pad,
};

layout(local_size_x = 16, local_size_y = 16, local_size_z = 4) in;

layout(std430, binding = 0) restrict readonly buffer points {
	Point points[];
} ps;

layout(std430, binding = 1) restrict writeonly buffer hashes {
	uint hashes[];
} h;

layout(std430, binding = 2) restrict writeonly buffer copy {
	Point points[];
} c;

layout(std430, binding = 3) restrict buffer buckets {
	u32 buckets[];
} b;

uniform vec2 u_pos;
uniform vec2 u_size;

uint hash(vec2 point) {
	const int MAX_INT = 2147483647;
	const int HALF_MAX_INT = MAX_INT / 2;

	uint hashed = 0;
	int xq = int(MAX_INT * double((point.x - u_pos.x)/u_size.x))
	int yq = int(MAX_INT * double((point.y - u_pos.y)/u_size.y))
	uint exp = 1 << 14;

	for (uint i = 0; i < 8; i++) {
		const int x_flag = (xq > 0) ? 1 : 0;
		const int y_flag = (yq > 0) ? 0 : 1;

		hashed |= ((y_flag << 1) | x_flag) << exp;
		exp = exp >> 2;

		xq = (xq + (HALF_MAX_INT - MAX_INT * x_flag)) * 2;
		yq = (yq + (HALF_MAX_INT - MAX_INT * (1 - y_flag))) * 2;
	}
	return hashed;
}

void main() {
    uint WorkGroupIndex =
        gl_WorkGroupID.z * gl_NumWorkGroups.x * gl_NumWorkGroups.y +
        gl_WorkGroupID.y * gl_NumWorkGroups.x +
        gl_WorkGroupID.x;
    const float WorkGroupStart = float(WorkGroupIndex)/float(gl_NumWorkGroups.x * gl_NumWorkGroups.y * gl_NumWorkGroups.z);
    const float WorkGroupEnd = float(WorkGroupIndex+1)/float(gl_NumWorkGroups.x * gl_NumWorkGroups.y * gl_NumWorkGroups.z);
    const float start = mix(WorkGroupStart, WorkGroupEnd, float(gl_LocalInvocationIndex)/float(gl_WorkGroupSize.x * gl_WorkGroupSize.y * gl_WorkGroupSize.z));
    const float end = mix(WorkGroupStart, WorkGroupEnd, float(gl_LocalInvocationIndex+1)/float(gl_WorkGroupSize.x * gl_WorkGroupSize.y * gl_WorkGroupSize.z));
    const uint ustart = uint(ps.points.length() * start);
    const uint uend = uint(ps.points.length() * end);

	for (uint i = ustart; i < uend; i++) {
		c.points[i] = ps.points[i];
		const uint hash = hash(ps.points[i].pos);
		h.hashes[i] = hash;
		atomicAdd(b.buckets[has], 1);
	}
}

