struct ps_in { float3 dir : TEXCOORD0; float4 position : SV_Position; };
uint portal_hash(uint x) {
    x ^= x >> 16;x *= 0x7feb352du;
    x ^= x >> 15;x *= 0x846ca68bu;
    return x ^ (x >> 16);
}
float random_cell(int2 p) {
    uint h = portal_hash((uint)p.x*73856093u ^ (uint)p.y*19349663u ^ 2467u);
    return float(h & 65535u)/65535.0;
}
float noise2(float2 p) {
    int2 cell = (int2)floor(p);
    float2 f = frac(p);f=f*f*(3.0-2.0*f);
    return lerp(lerp(random_cell(cell),random_cell(cell+int2(1,0)),f.x),
        lerp(random_cell(cell+int2(0,1)),random_cell(cell+int2(1,1)),f.x),f.y);
}
float4 main(ps_in i) : SV_Target0 {
    float3 d = normalize(i.dir);
    float3 background = SC_Color(4)*lerp(1.2,0.55,saturate(d.z));
    float ca,sa,ce,se;
    sincos(SC_Get(7),sa,ca);sincos(SC_Get(11),se,ce);
    float3 center = float3(ce*ca,ce*sa,se);
    float3 right = float3(-sa,ca,0);
    float3 up = float3(-se*ca,-se*sa,ce);
    float forward = dot(d,center);
    if (forward < 0.02) return float4(background,1.0);
    float2 p = float2(dot(d,right),dot(d,up))/forward/max(tan(SC_Get(15)),0.03);
    float r = max(length(p),0.0001);
    if (r > 4.0) return float4(background,1.0);
    float angle = atan2(p.y,p.x+0.0000001);
    float time = SC_Get(1) < 0.5 ? 0.0 : SC_Time();
    float strength = saturate(SC_Get(2));
    float twist = angle+time*0.3;
    if (SC_Get(1) > 1.5) twist += log(max(r,0.04))*strength*3.5;
    float2 q = float2(cos(twist),sin(twist))*r;
    float n = noise2(q*3.0+time*0.08)*0.55
        +noise2(q*6.1-time*0.13)*0.30+noise2(q*12.3)*0.15;
    float ring_radius = 1.0+(n-0.5)*strength*0.16;
    float ring_width = max(fwidth(r),0.012);
    float core = exp(-abs(r-ring_radius)/max(ring_width,0.024));
    float halo = exp(-abs(r-1.0)*6.0)*0.65;
    float phase = angle*5.0+log(max(r,0.04))*strength*8.0+time*1.3;
    float arms = pow(saturate(0.5+0.5*sin(phase)),6.0);
    arms *= exp(-abs(r-1.35)*1.8)*(0.25+n)*smoothstep(0.80,1.12,r);
    float edge_fade = 1.0-smoothstep(2.5,4.0,r);
    float3 color = background+SC_Color(8)*arms*strength*SC_Get(3)*1.8*edge_fade;
    float hole = 1.0-smoothstep(0.70,0.94,r);
    color *= lerp(1.0,0.02,hole);
    float3 ring_color = lerp(SC_Color(12),SC_Color(8),n*0.3);
    color += ring_color*(core*2.3+halo)*SC_Get(3)*edge_fade;
    return float4(color,1.0);
}
