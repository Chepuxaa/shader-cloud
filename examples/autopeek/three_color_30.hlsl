// Contract 2: the client injects b6 and SC_* helpers before this source.
// This descriptor has 27 controls and infers 30 user floats without Lua edits.
cbuffer cb:register(b0) { float4x4 mvp; float2 tex; float time; float alpha; };
struct Input { float4 pos:SV_POSITION; float4 col:COLOR0; float2 uv:TEXCOORD0; };

float4 main(Input i):SV_Target {
    float2 packed = floor(i.uv * 0.5);
    float2 p = (i.uv - packed * 2.0) * 2.0 - 1.0;
    p -= float2(SC_Get(27), SC_Get(28));
    float r = length(p);
    clip(0.98 - r);
    float t = SC_Time();
    float angle = atan2(p.y, p.x) + SC_Get(26);
    float radius = SC_Get(7) + sin(t * SC_Get(11) * 6.2831853) * SC_Get(10);
    float aa = max(fwidth(r), SC_Get(14));
    float ring = 1.0 - smoothstep(SC_Get(8), SC_Get(8) + aa, abs(r - radius));
    float glow = exp(-abs(r - radius) * 25.0) * SC_Get(9) * 0.2;
    float accents = pow(saturate(cos(angle * SC_Get(12) + t + r * SC_Get(13))), 12.0) * ring;
    float fill = exp(-pow(r, SC_Get(25)) * 5.0) * SC_Get(15);
    float orbit = exp(-abs(r - radius * 0.7) / max(SC_Get(20), 0.001));
    orbit *= pow(saturate(cos(angle - t * SC_Get(22))), 12.0) * SC_Get(21);
    float core = (1.0 - smoothstep(0.0, SC_Get(23), r)) * SC_Get(24);
    float3 accent = lerp(SC_Color(4), SC_Color(16), SC_Get(19));
    float3 rgb = SC_Color(1) * (fill + core) + SC_Color(4) * (ring + glow);
    rgb += accent * accents + SC_Color(16) * orbit;
    float energy = saturate(fill + core + ring + glow + accents + orbit);
    float boundary = 1.0 - smoothstep(0.98 - SC_Get(29), 0.98, r);
    return float4(saturate(rgb * SC_Get(30)), energy * boundary * i.col.a);
}
