// Contract 2: the client injects b6 and SC_* helpers before this source.
// The greatest occupied slot is 18 (accent_color uses slots 16, 17 and 18).
struct Input { float4 pos:SV_POSITION; float4 col:COLOR0; float2 uv:TEXCOORD0; };

float4 main(Input i):SV_Target {
    // Keep only the fractional UV payload; runtime values come from SC_*.
    float2 p = i.uv * 2.0 - 1.0;
    float r = length(p);
    clip(0.98 - r);
    float t = SC_Time();
    float radius = SC_Get(7) + sin(t * SC_Get(11) * 6.2831853) * SC_Get(10);
    float aa = max(fwidth(r), SC_Get(14));
    float ring = 1.0 - smoothstep(SC_Get(8), SC_Get(8) + aa, abs(r - radius));
    float glow = exp(-abs(r - radius) * 25.0) * SC_Get(9) * 0.2;
    float angle = atan2(p.y, p.x);
    float accents = pow(saturate(cos(angle * SC_Get(12) + t + r * SC_Get(13))), 12.0) * ring;
    float fill = exp(-r * r * 5.0) * SC_Get(15);
    float3 rgb = SC_Color(1) * fill + SC_Color(4) * (ring + glow) + SC_Color(16) * accents;
    float energy = saturate(fill + ring + glow + accents);
    float boundary = 1.0 - smoothstep(0.90, 0.98, r);
    return float4(saturate(rgb), energy * boundary * i.col.a);
}
