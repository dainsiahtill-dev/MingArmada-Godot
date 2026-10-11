// Direct shaders.mjs common. Only names and explicit color-space boundaries adapt.
uniform float u_time = 0.0;
uniform float u_tide = 0.0;
uniform vec3 u_eye = vec3(0.0);
uniform vec3 u_sun = vec3(-0.505076,0.808122,0.303046);
uniform vec3 u_sun_color = vec3(1.0,.95,.82);

vec3 reference_to_linear(vec3 color) {
	return mix(color/12.92,pow((color+.055)/1.055,vec3(2.4)),step(vec3(.04045),color));
}
vec3 reference_to_display(vec3 color) {
	return mix(color*12.92,1.055*pow(max(color,vec3(0.0)),vec3(1.0/2.4))-.055,step(vec3(.0031308),color));
}
vec3 source_sky(vec3 ray) {
	float h=clamp(ray.y,0.0,1.0);
	vec3 col=mix(vec3(.55,.76,.81),vec3(.13,.37,.58),pow(h,.55));
	col=mix(col,vec3(.80,.55,.35),clamp((1.0-u_sun.y)*.45,0.0,.5)*(1.0-h));
	float s=max(dot(ray,u_sun),0.0);
	return col+u_sun_color*(pow(s,320.0)*1.1+pow(s,16.0)*.1);
}
float source_noise(vec2 p) {return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453);}
float source_value_noise(vec2 p) {
	vec2 i=floor(p),f=fract(p);f=f*f*(3.0-2.0*f);
	return mix(mix(source_noise(i),source_noise(i+vec2(1,0)),f.x),mix(source_noise(i+vec2(0,1)),source_noise(i+1.0),f.x),f.y);
}
