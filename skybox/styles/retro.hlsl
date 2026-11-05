struct ps_in { float3 dir : TEXCOORD0; float4 position : SV_Position; };
float grid_line(float coordinate, float footprint) {
    float distance = abs(frac(coordinate+0.5)-0.5);
    float aa = max(footprint,0.002);
    float width = 0.035;
    return (1.0-smoothstep(width-aa,width+aa,distance))*min(1.0,width/aa);
}
float4 main(ps_in i) : SV_Target0 {
    float3 d = normalize(i.dir);
    float time = SC_Get(1) < 0.5 ? 0.0 : SC_Time();
    float az = atan2(d.y,d.x);
    float count = floor(lerp(16.0,64.0,saturate(SC_Get(2)))+0.5);
    float drift = SC_Get(1) > 1.5 ? time*0.035 : 0.0;
    float u = (az+drift)*count/6.2831853;
    float v = 1.2/max(d.z+0.04,0.04)+time*0.85;
    // Angular derivatives avoid a thick line at the atan2 wrap seam.
    float2 tangent = float2(-d.y,d.x);
    float du = (abs(dot(tangent,ddx(d.xy)))+abs(dot(tangent,ddy(d.xy))))
        /max(dot(d.xy,d.xy),0.001)*count/6.2831853;
    float lines = max(grid_line(u,du),grid_line(v,fwidth(v)));
    float grid_fade = smoothstep(0.01,0.13,d.z)*(1.0-smoothstep(0.18,0.80,d.z));
    float height = saturate(d.z*1.4);
    float3 color = lerp(SC_Color(4),SC_Color(8),height);
    color += SC_Color(12)*lines*grid_fade*SC_Get(3)*2.5;

    float ca,sa,ce,se;
    sincos(SC_Get(7),sa,ca);sincos(SC_Get(11),se,ce);
    float3 sun_dir = float3(ce*ca,ce*sa,se);
    float radius = max(SC_Get(15),0.03);
    float distance = sqrt(max(2.0*(1.0-dot(d,sun_dir)),0.000001));
    float aa = max(fwidth(distance),0.0001);
    float disc = 1.0-smoothstep(radius-aa,radius+aa,distance);
    float y = dot(d-sun_dir,float3(-se*ca,-se*sa,ce))/radius;
    float stripe_coord = (y+1.0)*4.5;
    float stripe_aa = min(fwidth(stripe_coord),0.15);
    float gap = lerp(0.48,0.12,saturate(y*0.5+0.5));
    float bands = smoothstep(gap-stripe_aa,gap+stripe_aa,frac(stripe_coord));
    bands = lerp(bands,1.0,smoothstep(0.20,0.45,y));
    float3 sun_color = lerp(SC_Color(12),float3(1.0,0.65,0.16),saturate(y*0.5+0.5));
    float halo = exp(-distance/max(radius*1.8,0.001))*0.18;
    color += SC_Color(12)*halo*SC_Get(3);
    color = lerp(color,sun_color*(0.7+SC_Get(3)*0.6),disc*bands);
    return float4(color,1.0);
}
