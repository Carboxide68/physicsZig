@compute
#version 450 core

layout(local_size_x = 4, local_size_y = 4, local_size_z = 1) in;

layout(std430, binding = 3) restrict buffer buckets {
	uint buckets[];
} b;


void main() {

	const uint id = gl_LocalInvocationIndex;
	const uint start = id * 65536/16;
	const uint end = (id + 1) * 65536/16;

	uint tot = 0;
	for (uint i = start; i < end; i++) {
		const uint tmp = b.buckets[i];
		b.buckets[i] += tot;
		tot += tmp;
	}
	for (uint i = id; i < 16; i++) {
		atomicAdd(b.buckets[b.buckets.len - 16 + i], tot);
	}
}