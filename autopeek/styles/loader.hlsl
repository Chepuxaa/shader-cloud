struct Input {float4 pos:SV_POSITION;float4 col:COLOR0;float2 uv:TEXCOORD0;};

float4 main(Input i):SV_Target {
    float2 p=i.uv*2-1;
    float radius=length(p);
    clip(radius-.69);
    clip(.93-radius);

    const float tau=6.28318530718;
    float segments=clamp(floor(SC_Get(4)+.5),12,48);
    float turn=atan2(p.y,p.x)/tau+.25;
    float sector=floor(turn*segments+.5);
    float angle=(sector/segments-.25)*tau;
    float2 normal=float2(cos(angle),sin(angle));
    float2 tangent=float2(-normal.y,normal.x);
    float2 local=float2(dot(p,tangent),dot(p,normal)-.82);
    float2 halfSize=float2(tau*.82/segments*.32,.026);
    float2 q=abs(local)-halfSize;
    float distance=length(max(q,0))+min(max(q.x,q.y),0);
    float aa=clamp(fwidth(radius),.0015,.02);
    float block=1-smoothstep(-aa*.5,aa*.5,distance);

    // Only the light moves; every rectangle stays fixed on the ground.
    float age=frac(SC_Time()*.5-sector/segments);
    float trail=pow(saturate(1-age/.44),1.6);
    float head=pow(trail,4);
    float glow=exp(-max(distance,0)*140)*.09;
    float energy=block*(.11+trail*.89)+glow*(.12+trail*.88);
    float visibility=SC_ReleaseAge()<0?1:1-smoothstep(0,.26,SC_ReleaseAge());
    float opacity=saturate(energy)*visibility*i.col.a;
    clip(opacity-1.0/1024.0);
    float3 tint=lerp(SC_Color(1),float3(1,1,1),head*.48);
    return float4(tint,opacity);
}
