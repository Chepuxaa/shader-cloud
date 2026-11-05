struct Input {float3 localPosition:TEXCOORD8;float4 screen:SV_Position;};
float hash(float3 p) {p=frac(p*.1031);p+=dot(p,p.yzx+33.33);return frac((p.x+p.y)*p.z);}
float3 unit(float3 v,float3 fallback) {float l=dot(v,v);return l>1e-12?v*rsqrt(max(l,1e-12)):fallback;}
float scanline(float coordinate,float width) {
 float distance=abs(frac(coordinate+.5)-.5);
 float aa=max(fwidth(coordinate),.012);
 return 1-smoothstep(width,width+aa,distance);
}
float4 main(Input i):SV_Target0 {
 float time=SC_Time();
 float2 size=max(SC_FrameViewport().zw,1);
 float2 ndc=((i.screen.xy-SC_FrameViewport().xy)/size)*float2(2,-2)+float2(-1,1);
 float3 surface=float3(ndc.x*(size.x/size.y)*SC_FrameCamera().w,ndc.y*SC_FrameCamera().w,1)*max(i.screen.w,1e-6);
 float3 normal=unit(cross(ddx(surface),ddy(surface)),float3(0,0,1));
 float3 eye=unit(-surface,float3(0,0,-1));
 float rim=pow(saturate(1-abs(dot(normal,eye))),2.1);
 float stripes=scanline(i.localPosition.z*2.5-time*1.7,.055);
 float micro=scanline(i.localPosition.z*11.0,.025)*.07;
 float sweepCoordinate=abs(frac(i.localPosition.z*.095-time*.22+.5)-.5);
 float sweep=exp(-sweepCoordinate*sweepCoordinate*550);
 float shimmer=.94+.06*sin(time*7.3+i.localPosition.z*.35);
 // A short digital dropout every five seconds; geometry and depth stay intact.
 float event=1-step(.14,frac(time/5)*5);
 float3 block=floor(i.localPosition*float3(.6,1.8,3.2));
 float glitch=event*step(.64,hash(block+floor(time*24)));
 float3 tint=SC_Color(4);
 float3 color=tint*.03*(1+rim*2);
 color+=tint*.78*(stripes*.65+micro);
 color+=tint*(rim*1.6+sweep*.5);
 color*=shimmer*(1-glitch*.75);
 color+=tint*.85*glitch*scanline(i.localPosition.z*3.2+time*13,.1)*.6;
 color=color/(1+color*.35);
 return float4(color,1);
}
