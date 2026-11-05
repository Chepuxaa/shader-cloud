struct ps_in { float3 dir : TEXCOORD0; float4 position : SV_Position; };
uint star_hash(uint x) {
    x ^= x >> 16;
    x *= 0x7feb352du;
    x ^= x >> 15;
    x *= 0x846ca68bu;
    return x ^ (x >> 16);
}
float3 star_layer(float3 direction, float scale, uint seed, float density, float time) {
    float3 p = direction * scale;
    float aa = max(length(ddx(p)), length(ddy(p))) * 0.65;
    uint3 cell = (uint3)(int3)floor(p);
    uint h = star_hash(cell.x * 73856093u ^ cell.y * 19349663u ^ cell.z * 83492791u ^ seed);
    uint h2 = star_hash(h + 0x9e3779b9u);
    float chance = float(h2 & 65535u) / 65535.0;
    if (chance > density) return float3(0,0,0);

    // One jittered point per 3D cell; margins prevent stars clipping at cell edges.
    float3 jitter = float3(h & 1023u, (h >> 10) & 1023u, (h >> 20) & 1023u) / 1023.0;
    float3 center = 0.2 + jitter * 0.6;
    float radius = lerp(0.04, 0.105, float((h2 >> 16) & 255u) / 255.0);
    float distance = length(frac(p) - center);
    float width = max(aa, 0.008);
    float disc = 1.0 - smoothstep(radius - width, radius + width, distance);
    float energy = min(1.0, radius * radius / max(aa * aa, 0.00001));
    float phase = float(h & 65535u) / 65535.0 * 6.2831853;
    float frequency = lerp(0.35, 1.1, float(h2 >> 24) / 255.0);
    float twinkle = 0.78 + 0.22 * sin(time * frequency + phase);
    if (SC_Get(1) > 0.5 && SC_Get(1) < 1.5) {
        float pulse = 0.5 + 0.5 * sin(time * lerp(1.0,2.2,jitter.z) + phase);
        twinkle = lerp(0.15,1.0,pulse*pulse*(3.0-2.0*pulse));
    }
    float3 tint = lerp(float3(1.0,0.83,0.67), float3(0.72,0.84,1.0), jitter.y);
    return tint * disc * energy * twinkle;
}
float4 main(ps_in i) : SV_Target0 {
    float3 d = normalize(i.dir);
    float time = SC_Get(1) < 0.5 ? 0.0 : SC_Time();
    if (SC_Get(1) > 1.5) {
        float s,c;
        sincos(time * 0.008, s,c);
        d.xy = float2(c*d.x-s*d.y, s*d.x+c*d.y);
    }
    float height = saturate(d.z * 0.5 + 0.5);
    float3 sky = lerp(SC_Color(4), SC_Color(8), height);
    float az = atan2(d.y,d.x);
    float mist = pow(saturate(1.0-abs(d.z+sin(az*2.0)*0.22)*2.5),3.0);
    float cloud = 0.5+0.5*sin(az*7.0+d.z*11.0+sin(az*3.0-d.z*8.0));
    sky += lerp(float3(0.10,0.025,0.20),SC_Color(12)*0.18,cloud)*mist*SC_Get(7);
    float density = saturate(SC_Get(2));
    float3 stars = star_layer(d,72.0,1357u,density*0.60,time);
    stars += star_layer(d,135.0,8641u,density*0.35,time) * 0.45;
    float above_horizon = smoothstep(-0.08,0.15,d.z);
    return float4(sky + stars*SC_Color(12)*SC_Get(3)*2.5*above_horizon,1.0);
}
