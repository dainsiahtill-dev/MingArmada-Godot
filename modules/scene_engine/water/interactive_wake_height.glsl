#[compute]
#version 450
// Independent damped wave equation and Gaussian-dipole interaction.
// Reference: docs/research/wake-flow-online-research-2026-10-14.md sections 2-3.
layout(local_size_x=8, local_size_y=8, local_size_z=1) in;
layout(rg32f,set=0,binding=0) readonly uniform image2D previous_state;
layout(rg32f,set=0,binding=1) writeonly uniform image2D next_state;
layout(std430,set=0,binding=2) readonly buffer Sources { vec4 sources[]; };
layout(set=0,binding=3) uniform sampler2D wet_mask;
layout(push_constant,std430) uniform Parameters {
    vec4 origins; // old minimum XZ, new minimum XZ
    vec4 grid; // resolution, cell metres, dt, wave speed
    vec4 decay; // damping, max height, max velocity, foam decay
    vec4 flow; // ambient XZ m/s, foam diffusion m2/s, edge width cells
    ivec4 counts; // emitter count, wake count, reset, reserved
    vec4 motion; // seconds before newest input, wave activity foam, edge damping, reserved
    vec4 mask_bounds;
} p;
bool wet(vec2 world) {
    if(p.counts.w==0) return true;
    vec2 uv=(world-p.mask_bounds.xy)/(p.mask_bounds.zw-p.mask_bounds.xy);
    if(any(lessThan(uv,vec2(0)))||any(greaterThanEqual(uv,vec2(1)))) return true;
    return textureLod(wet_mask,uv,0.0).r>0.5;
}
vec2 cell(ivec2 xy) {
    int n=int(p.grid.x);
    if(p.counts.z!=0 || any(lessThan(xy,ivec2(0))) || any(greaterThanEqual(xy,ivec2(n)))) return vec2(0);
    if(!wet(p.origins.xy+(vec2(xy)+0.5)*p.grid.y)) return vec2(0);
    return imageLoad(previous_state,xy).rg;
}
vec2 sample_state(vec2 xy) {
    ivec2 base=ivec2(floor(xy)); vec2 a=fract(xy);
    return mix(mix(cell(base),cell(base+ivec2(1,0)),a.x),mix(cell(base+ivec2(0,1)),cell(base+ivec2(1,1)),a.x),a.y);
}
void main() {
    ivec2 xy=ivec2(gl_GlobalInvocationID.xy); int n=int(p.grid.x);
    if(any(greaterThanEqual(xy,ivec2(n)))) return;
    float dx=p.grid.y, dt=p.grid.z;
    vec2 world=p.origins.zw+(vec2(xy)+0.5)*dx;
    if(!wet(world)) {imageStore(next_state,xy,vec4(0));return;}
    vec2 from=vec2(xy)+(p.origins.zw-p.origins.xy-p.flow.xy*dt)/dx;
    vec2 old=sample_state(from);
    float lap=sample_state(from+vec2(1,0)).r+sample_state(from-vec2(1,0)).r+sample_state(from+vec2(0,1)).r+sample_state(from-vec2(0,1)).r-4.0*old.r;
    float force=0.0;
    for(int i=0;i<p.counts.x;i++) {
        vec4 pos=sources[i*3]; vec4 vel=sources[i*3+1]; float weight=sources[i*3+2].x;
        vec2 center=pos.xz-(vel.xz+p.flow.xy)*p.motion.x;
        vec2 d=(world-center)/pos.w; float r2=dot(d,d);
        // Zero-net signed kernels: fore/aft dipole plus positive core/negative ring.
        force+=weight*vel.w*exp(-0.5*r2)*(0.30*dot(d,vel.xz)+0.45*vel.y*(1.0-0.5*r2));
    }
    float velocity=(old.g+dt*(p.grid.w*p.grid.w*lap/(dx*dx)+force))*exp(-p.decay.x*dt);
    float edge=min(min(float(xy.x)+0.5,float(xy.y)+0.5),min(float(n-xy.x)-0.5,float(n-xy.y)-0.5));
    float absorb=exp(-p.motion.z*dt*pow(1.0-clamp(edge/max(p.flow.w,1.0),0.0,1.0),2.0));
    velocity=clamp(velocity*absorb,-p.decay.z,p.decay.z);
    float height=clamp((old.r+dt*velocity)*absorb,-p.decay.y,p.decay.y);
    if(isnan(height)||isinf(height)||isnan(velocity)||isinf(velocity)) {height=0.0;velocity=0.0;}
    imageStore(next_state,xy,vec4(height,velocity,0,0));
}
