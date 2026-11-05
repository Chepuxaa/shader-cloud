struct ps_in { float3 dir : TEXCOORD0; float4 position : SV_Position; };
float4 main(ps_in i) : SV_Target0 {
    float3 d = normalize(i.dir);
    float az = atan2(d.y,d.x);
    float elevation = asin(clamp(d.z,-1.0,1.0));
    float phase = SC_Get(1) < 0.5 ? 0.0 : SC_Time()*0.65;
    float bend = 0.0;
    if (SC_Get(1) > 1.5)
        bend = sin(az*3.0+SC_Time())*SC_Get(2)*0.22;
    float bands = (elevation+bend)*SC_Get(7)-phase;
    float distance = abs(frac(bands+0.5)-0.5);
    float aa = max(fwidth(bands),0.001);
    float stripe = 1.0-smoothstep(SC_Get(11)-aa,SC_Get(11)+aa,distance);
    float halo = exp(-distance*distance/0.015)*SC_Get(3);
    float horizon = saturate(length(d.xy)*4.0);
    float h = saturate(d.z*0.5+0.5);
    float3 color = lerp(SC_Color(4),SC_Color(8),h);
    color += SC_Color(12)*(stripe+halo)*horizon;
    return float4(color,1.0);
}
