struct Input { float4 screen:SV_Position; };

float3 comicUnit(float3 value,float3 fallback) {
 float squared=dot(value,value);
 return squared>1e-16 ? value*rsqrt(max(squared,1e-16)) : fallback;
}

float4 main(Input i):SV_Target0 {
 float2 size=max(SC_FrameViewport().zw,1);
 float2 ndc=(i.screen.xy-SC_FrameViewport().xy)/size*float2(2,-2)+float2(-1,1);
 // D3D11 pixel-position W carries the perspective distance, not its reciprocal.
 float3 surface=float3(ndc.x*(size.x/size.y)*SC_FrameCamera().w,
                       ndc.y*SC_FrameCamera().w,1)*max(abs(i.screen.w),1e-5);
 float3 normal=comicUnit(cross(ddx(surface),ddy(surface)),float3(0,0,-1));
 float3 eye=comicUnit(-surface,float3(0,0,-1));
 normal*=dot(normal,eye)<0 ? -1 : 1;
 float3 light=normalize(float3(-.45,.70,-.60));
 float diffuse=saturate(dot(normal,light));
 float levels=clamp(floor(SC_Get(13)+.5),2,6);
 float aa=.018;
 float shade=0;
 [unroll]for(int band=1;band<=5;band++) {
  float threshold=(band-.5)/(levels-1);
  shade+=smoothstep(threshold-aa,threshold+aa,diffuse)*step((float)band,levels-1);
 }
 shade/=levels-1;
 float lift=saturate(SC_Get(17));
 float3 color=lerp(SC_Color(4),SC_Color(1),lift+(1-lift)*shade);

 float3 halfway=comicUnit(light+eye,eye);
 float highlight=smoothstep(.94,.97,saturate(dot(normal,halfway)));
 highlight*=saturate(SC_Get(18))*(.35+.65*shade)*.65;
 color=lerp(color,SC_Color(10),highlight);

 float strength=saturate(SC_Get(15));
 float coverage=(1-shade)*strength*.7;
 float spacing=clamp(SC_Get(16),3,12);
 float2 screen=i.screen.xy-SC_FrameViewport().xy;
 float2 grid=float2(screen.x*.8660254-screen.y*.5,screen.x*.5+screen.y*.8660254)/spacing;
 float distance=length(frac(grid)-.5);
 float radius=sqrt(max(coverage,0)*.318309886);
 float dotAA=.65/spacing;
 float dots=1-smoothstep(max(radius-dotAA,0),radius+dotAA,distance);
 dots*=smoothstep(0,.025,coverage)*strength*.85;
 color=lerp(color,SC_Color(7),dots);

 // Ink stays inside the existing weapon silhouette; no extra geometry pass.
 float edges=saturate(SC_Get(14));
 float facing=saturate(dot(normal,eye));
 float width=lerp(.035,.20,edges);
 float edgeAA=.018;
 float ink=(1-smoothstep(width,width+edgeAA,facing))*edges;
 color=lerp(color,SC_Color(7),ink);
 return float4(saturate(color),1);
}
