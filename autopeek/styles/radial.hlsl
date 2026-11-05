struct Input {float4 pos:SV_POSITION;float4 col:COLOR0;float2 uv:TEXCOORD0;};

float2 localUV(float2 uv, out float visibility) {
    float releaseAge=floor(max(SC_ReleaseAge(),0)*60+.5)/60;
    visibility=SC_ReleaseAge()<0?1:1-smoothstep(0,.28,releaseAge);
    return uv*2-1;
}

float4 main(Input i):SV_Target {
    float visibility;
    float2 p=localUV(i.uv,visibility);
    float radius=length(p)/.94;
    // Continuous falloff: brightest at the center, fully transparent at the edge.
    float falloff=pow(saturate(1-radius),1.55);
    float core=exp(-radius*radius*10);
    float3 tint=lerp(SC_Color(1),float3(1,1,1),core*.20);
    float opacity=falloff*.80*visibility*i.col.a;
    return float4(tint,opacity);
}
