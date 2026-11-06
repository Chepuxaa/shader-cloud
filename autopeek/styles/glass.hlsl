#ifndef SC_OCCLUDED_PASS
#define SC_OCCLUDED_PASS 0
bool SC_IsOccluded(){return false;}
#endif

cbuffer cb:register(b0) {float4x4 mvp;float2 tex;};
sampler sampler0:register(s0);
Texture2D texture0:register(t0);

struct Input {float4 pos:SV_POSITION;float4 col:COLOR0;float2 uv:TEXCOORD0;};

float2 localUV(float2 uv, out float visibility) {
    float releaseAge=floor(max(SC_ReleaseAge(),0)*60+.5)/60;
    visibility=SC_ReleaseAge()<0?1:1-smoothstep(0,.28,releaseAge);
    return uv*2-1;
}

float4 main(Input i):SV_Target {
    float visibility;
    float2 p=localUV(i.uv,visibility);
    float radius=length(p);
    float aa=clamp(fwidth(radius),.0015,.025);
    // Discard the square carrier outside the circular effect, including glow tails.
    clip(.90-radius);
    float edge=.83;
    float rim=1-smoothstep(.009,.009+aa*.75,abs(radius-edge));
    float rimGlow=exp(-abs(radius-edge)*90)*.08*(1-smoothstep(.865,.90,radius));
    float highlight=saturate(.55-p.y*.5-p.x*.22);
    float rimAlpha=saturate(rim*.90+rimGlow);
    float3 rimColor=lerp(SC_Color(1),float3(1,1,1),.30+highlight*.38);
    if(SC_IsOccluded()) {
        float outputAlpha=rimAlpha*visibility*i.col.a;
        clip(outputAlpha-1.0/1024.0);
        return float4(rimColor,outputAlpha);
    }
    float inside=1-smoothstep(edge-aa,edge+aa,radius);
    // The GUI projection supplies full viewport dimensions independently of the
    // downsampled background texture. Local plane UVs only define the circle.
    float2 viewportScale=float2(abs(mvp[0][0]),abs(mvp[1][1]))*.5;
    float2 screenUV=saturate(i.pos.xy*viewportScale);
    float2 pixel=1.0/max(tex,float2(1,1));
    float3 background=0;
    float total=0;
    [unroll]for(int y=-2;y<=2;y++) {
        [unroll]for(int x=-2;x<=2;x++) {
            float weight=exp(-float(x*x+y*y)/3.5);
            float2 offset=float2(x,y)*pixel*3.0;
            background+=texture0.SampleLevel(sampler0,saturate(screenUV+offset),0).rgb*weight;
            total+=weight;
        }
    }
    background/=total;
    float sheen=exp(-pow((p.y+.20+p.x*.38)*3.1,2))*.06;
    float3 glassColor=lerp(background,SC_Color(1),.12)+sheen;
    float3 tint=lerp(glassColor,rimColor,rimAlpha);
    float opacity=saturate(inside*.88+rimAlpha);
    float outputAlpha=opacity*visibility*i.col.a;
    clip(outputAlpha-1.0/1024.0);
    return float4(tint,outputAlpha);
}
