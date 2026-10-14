#[compute]
#version 450
// Persistent foam density + world-XZ visual drift. This is NOT Navier-Stokes.
// Transport, diffusion and exponential decay use standard equations;
// Crest / Rare / Atlas references and differences documented in the research paper.
layout(local_size_x=8, local_size_y=8, local_size_z=1) in;
layout(rgba32f,set=0,binding=0) readonly uniform image2D previous_foam;
layout(rgba32f,set=0,binding=1) writeonly uniform image2D next_foam;
layout(rg32f,set=0,binding=2) readonly uniform image2D height_state;
layout(rgba32f,set=0,binding=3) writeonly uniform image2D surface_output;
layout(std430,set=0,binding=4) readonly buffer Sources { vec4 sources[]; };
layout(set=0,binding=5) uniform sampler2D wake_shape;
layout(set=0,binding=6) uniform sampler2D wet_mask;
layout(push_constant,std430) uniform Parameters {
    vec4 origins; vec4 grid; vec4 decay; vec4 flow; ivec4 counts; vec4 motion; vec4 mask_bounds;
    vec4 drift; // outward speed m/s, drag 1/s, source multiplier, velocity smoothing m2/s
} p;
bool wet(vec2 world) {
    if(p.counts.w==0) return true;
    vec2 uv=(world-p.mask_bounds.xy)/(p.mask_bounds.zw-p.mask_bounds.xy);
    if(any(lessThan(uv,vec2(0)))||any(greaterThanEqual(uv,vec2(1)))) return true;
    return textureLod(wet_mask,uv,0.0).r>0.5;
}
vec4 cell(ivec2 xy) {
    int n=int(p.grid.x);
    if(p.counts.z!=0 || any(lessThan(xy,ivec2(0))) || any(greaterThanEqual(xy,ivec2(n)))) return vec4(0);
    if(!wet(p.origins.xy+(vec2(xy)+0.5)*p.grid.y)) return vec4(0);
    return imageLoad(previous_foam,xy);
}
vec4 sample_foam(vec2 xy) {
    ivec2 b=ivec2(floor(xy)); vec2 a=fract(xy);
    return mix(mix(cell(b),cell(b+ivec2(1,0)),a.x),mix(cell(b+ivec2(0,1)),cell(b+ivec2(1,1)),a.x),a.y);
}
float height(ivec2 xy) {
    if(any(lessThan(xy,ivec2(0)))||any(greaterThanEqual(xy,ivec2(int(p.grid.x))))) return 0.0;
    return imageLoad(height_state,xy).r;
}
void main() {
    ivec2 xy=ivec2(gl_GlobalInvocationID.xy); int n=int(p.grid.x);
    if(any(greaterThanEqual(xy,ivec2(n)))) return;
    float dx=p.grid.y, dt=p.grid.z;
    vec2 world=p.origins.zw+(vec2(xy)+0.5)*dx;
    if(!wet(world)) {imageStore(next_foam,xy,vec4(0));imageStore(surface_output,xy,vec4(0));return;}
    vec2 current=vec2(xy)+(p.origins.zw-p.origins.xy)/dx;
    vec2 local_drift=sample_foam(current).gb;
    vec2 from=current-(p.flow.xy+local_drift)*dt/dx;
    vec4 old=sample_foam(from);
    vec4 lap=sample_foam(from+vec2(1,0))+sample_foam(from-vec2(1,0))+sample_foam(from+vec2(0,1))+sample_foam(from-vec2(0,1))-4.0*old;
    local_drift=(old.gb+p.drift.w*dt*lap.gb/(dx*dx))*exp(-p.drift.y*dt);
    vec2 hv=imageLoad(height_state,xy).rg;
    vec2 slope=vec2(height(xy+ivec2(1,0))-height(xy-ivec2(1,0)),height(xy+ivec2(0,1))-height(xy-ivec2(0,1)))/(2.0*dx);
    float foam=max(0.0,old.r+p.flow.z*dt*lap.r/(dx*dx))*exp(-p.decay.w*dt);
    float divergence=(sample_foam(current+vec2(1,0)).g-sample_foam(current-vec2(1,0)).g
        +sample_foam(current+vec2(0,1)).b-sample_foam(current-vec2(0,1)).b)/(2.0*dx);
    // Dilute expanding drift; never manufacture foam by compression alone.
    foam*=exp(-max(0.0,divergence)*dt);
    // Activity proxy (not Jacobian foam): small and subordinate to paired stern sources.
    foam+=dt*p.motion.y*abs(hv.g)*length(slope);
    for(int i=0;i<p.counts.y;i++) {
        int at=48+i*3; vec4 pose=sources[at]; vec4 shape=sources[at+1];
        vec2 forward=pose.zw; vec2 stern=pose.xy-forward*shape.y*p.motion.x;
        vec2 delta=world-stern; float aft=-dot(delta,forward);
        float span=max(1.0,shape.x*1.8); float half_width=shape.x*0.75+max(0.0,aft)*0.18;
        vec2 sideways=vec2(-forward.y,forward.x);
        float side=dot(delta,sideways);float u=0.5+side/(2.0*half_width);
        float added=0.0;
        if(aft>=0.0 && aft<span && u>0.0 && u<1.0) {
            // Original wake U maps cross-stream exactly: two alpha peaks, empty center.
            float mask=textureLod(wake_shape,vec2(u,aft/span),0.0).a;
            float fade=smoothstep(0.0,0.5,aft)*(1.0-smoothstep(span*0.55,span,aft));
            added=dt*mask*fade*shape.z*clamp(shape.y*0.18,0.0,1.5)*p.drift.z;
        }
        // Extrapolate birth drift into a wider empty-water support than the narrow
        // alpha ridges, so semi-Lagrangian transport can carry foam off its source.
        // Once the ship leaves, this world vector evolves only from stored state.
        float support=1.0-smoothstep(half_width,half_width+max(2.0,shape.x*0.6),abs(side));
        support*=smoothstep(-0.5,0.0,aft)*(1.0-smoothstep(span,span+shape.x*0.6,aft));
        float fresh_fraction=added/max(foam+added,0.000001);
        float empty_support=(1.0-smoothstep(0.0,0.03,foam))*(1.0-exp(-8.0*dt));
        float influence=max(fresh_fraction,empty_support)*support*shape.z*clamp(shape.y,0.0,1.0);
        vec2 born_drift=sideways*sign(side)*p.drift.x;
        local_drift=mix(local_drift,born_drift,clamp(influence,0.0,1.0));
        foam+=added;
    }
    float edge=min(min(float(xy.x)+0.5,float(xy.y)+0.5),min(float(n-xy.x)-0.5,float(n-xy.y)-0.5));
    float absorb=exp(-p.motion.z*dt*pow(1.0-clamp(edge/max(p.flow.w,1.0),0.0,1.0),2.0));
    foam*=absorb;local_drift*=absorb;
    if(isnan(foam)||isinf(foam)) foam=0.0;
    foam=clamp(foam,0.0,1.0);
    if(any(isnan(local_drift))||any(isinf(local_drift))) local_drift=vec2(0);
    local_drift=clamp(local_drift,vec2(-1.5),vec2(1.5));
    imageStore(next_foam,xy,vec4(foam,local_drift,0));
    imageStore(surface_output,xy,vec4(hv.r,slope,foam));
}
