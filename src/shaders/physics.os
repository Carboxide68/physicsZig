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

//layout(std430, binding = 1) restrict buffer boxes {
//    vec2 lines[2][];
//} box;

layout(std430, binding = 2) restrict readonly buffer copy {
	Point points[];
} c;

layout(std430, binding = 3) restrict buffer buckets {
	uint buckets[];
} b;

layout(std430, binding = 4) restrict writeonly buffer aux_data {
    vec2 vel[];
} aux;

layout(std430, binding = 5) restrict readonly buffer aux_copy {
    vec2 vel[];
} ac;

struct Box {
    vec4 lines[4];
};

Box box = Box(vec4[4](
    vec4(-10,  10 , 10,  10),
    vec4( 10,  10,  10, -10),
    vec4( 10, -10, -10, -10),
    vec4(-10, -10, -10,  10)
));
uniform float u_radius;
uniform vec2 u_size;
uniform float u_ts;

vec2 collide(vec2 p1, vec2 p2, vec2 v1, vec2 v2, float r) {
    const vec2 ZERO = vec2(0, 0);
    const vec2 between = p1 - p2;
    const float len_between2 = dot(between, between);
    if (r * r * 4 < len_between2) return ZERO;

    const vec2 velo_diff = v1 - v2;
    const float velo_betw_dot = dot(velo_diff, between);
    if (velo_betw_dot >= 0) return ZERO;

    const float vel_coef = velo_betw_dot/len_between2;
    const vec2 velocity = between * vel_coef;
    return velocity;
}

vec2 lineCollide(vec2 p, vec2 vel, vec2 line[2], float r) {
    const float PADDING = 0.1;

    const vec2 ZERO = vec2(0, 0);
    const vec2 l_diff = line[1] - line[0];
    const vec2 between = p - line[0];

    if (dot(l_diff, between) < 0) return ZERO;

    const vec2 orth_line = vec2(-l_diff.y, l_diff.x);
    const float l_length2 = dot(l_diff, l_diff);
    if (l_length2 < dot(between, between)) return ZERO;

    const float l_length = sqrt(l_length2);
    const vec2 normal_orth_line = orth_line/l_length;
    const float len_between = dot(normal_orth_line, between);
    const float vel_between = dot(normal_orth_line, vel);
    float len_sign = (len_between > 0) ? 1 : -1;
    float vel_sign = (vel_between > 0) ? 1 : -1;
    if (len_sign == vel_sign) return ZERO;

    if (abs(len_between) > r + PADDING) return ZERO;
    const float velocity = vel_between * -2;
    const vec2 to_line = normal_orth_line * velocity;
    return to_line;
}

uint hash(vec2 point) {
	const int MAX_INT = 2147483646;
	const int HALF_MAX_INT = MAX_INT / 2;

	uint hashed = 0;
	int xq = int(MAX_INT * double(point.x/u_size.x));
	int yq = int(MAX_INT * double(point.y/u_size.y));
	uint exp = 1 << 14;

	for (uint i = 0; i < 8; i++) {
		const int x_flag = (xq > 0) ? 1 : 0;
		const int y_flag = (yq > 0) ? 0 : 1;

		hashed |= uint(((y_flag << 1) | x_flag) * exp);
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
    const uint ustart = uint(c.points.length() * start);
    const uint uend = uint(c.points.length() * end);

    for (uint i = ustart; i < uend; i++) {
        const Point point = c.points[i];
        const uint id = point.id;
        const vec2 pos = point.pos;
        const float r = u_radius;
        vec2 vel = ac.vel[id];

        const vec2 points[4] = {
            vec2(pos.x - r, pos.y + r),
            vec2(pos.x + r, pos.y + r),
            vec2(pos.x - r, pos.y - r),
            vec2(pos.x + r, pos.y - r),
        };

        for (uint k = 0; k < 4; k++) {
            const vec2 p = points[k];
            if (abs(p.x) >= u_size.x || abs(p.y) >= u_size.y) continue;
            const vec2 pn = vec2(p.x/u_size.x, p.y/u_size.y);

            const uint h = hash(pn);
            const uint arr_end = b.buckets[h];
            const uint arr_start = (h == 0) ? 0 : b.buckets[h - 1];

            for (uint j = arr_start; j < arr_end; j++) {
                const Point other = c.points[j];
                const vec2 vo = ac.vel[other.id];

                vel = collide(pos, other.pos, vel, vo, u_radius);
            }
        }

        vec2 line_vel = vec2(0, 0);
        for (uint k = 0; k < box.lines.length(); k++) {
            const vec2 lines[2] = vec2[2](vec2(box.lines[k].xy), vec2(box.lines[k].zw));
            line_vel += lineCollide(pos, vel, lines, u_radius);
        }
        vel += line_vel;
        aux.vel[id] = vel;
        ps.points[i].pos = point.pos + vel * u_ts;
    }
}

@end
