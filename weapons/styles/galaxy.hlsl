// Camera angles and client dimensions come from the Fatality Lua API.
struct Input {float4 screen:SV_Position;};
float hash(float3 p) {
 p=frac(p*.1031);p+=dot(p,p.yzx+33.33);return frac((p.x+p.y)*p.z);
}
float3 hash3(float3 p) {return float3(hash(p),hash(p+19.19),hash(p+47.47));}
float noise(float3 p) {
 float3 a=floor(p),f=frac(p);f=f*f*(3-2*f);
 return lerp(lerp(lerp(hash(a),hash(a+float3(1,0,0)),f.x),
                  lerp(hash(a+float3(0,1,0)),hash(a+float3(1,1,0)),f.x),f.y),
             lerp(lerp(hash(a+float3(0,0,1)),hash(a+float3(1,0,1)),f.x),
                  lerp(hash(a+float3(0,1,1)),hash(a+1),f.x),f.y),f.z);
}
float fbm(float3 p) {
 float v=0,a=.57;
 [unroll]for(int i=0;i<4;i++){v+=a*noise(p);p=p*2.03+13.4;a*=.47;}
 return v;
}
float3 unit(float3 v,float3 fallback) {float l=dot(v,v);return l>1e-12?v*rsqrt(max(l,1e-12)):fallback;}

float3 worldRay(Input i) {
 float pitch=radians(SC_FrameCamera().x),yaw=radians(SC_FrameCamera().y),roll=radians(SC_FrameCamera().z);
 float cp=cos(pitch),sp=sin(pitch),cy=cos(yaw),sy=sin(yaw),cr=cos(roll),sr=sin(roll);
 float3 forward=float3(cp*cy,cp*sy,-sp);
 float3 right0=float3(sy,-cy,0),up0=float3(sp*cy,sp*sy,cp);
 float3 right=right0*cr-up0*sr,up=up0*cr+right0*sr;
 float2 size=max(SC_FrameViewport().zw,1);
 float2 ndc=((i.screen.xy-SC_FrameViewport().xy)/size)*float2(2,-2)+float2(-1,1);
 // Source's reference horizontal FOV is projected at 4:3; only orientation is used.
 return unit(forward+right*ndc.x*(size.x/size.y)*SC_FrameCamera().w+up*ndc.y*SC_FrameCamera().w,forward);
}
float3 stars(float3 ray,float scale,float density,float time) {
 const float PI=3.14159265359;
 float azimuth=atan2(ray.y,ray.x);
 float elevation=asin(clamp(ray.z,-1,1));
 float2 uv=float2(azimuth/(2*PI)+.5,elevation/PI+.5);
 float rows=floor(max(50,180/sqrt(scale)));
 float2 cells=float2(rows*2,rows),q=uv*cells,cell=floor(q);
 float stretch=max(cos(elevation),.08);
 // Wrap angular derivatives so the longitude seam cannot become a bright stripe.
 float2 dx=ddx(uv),dy=ddy(uv);
 dx.x=min(abs(dx.x),abs(1-abs(dx.x)));
 dy.x=min(abs(dy.x),abs(1-abs(dy.x)));
 float footprint=max(length(dx*cells*float2(stretch,1)),length(dy*cells*float2(stretch,1)));
 float3 result=0;
 [unroll]for(int y=-1;y<=1;y++) {
  [unroll]for(int x=-1;x<=1;x++) {
   float2 candidate=cell+float2(x,y);
   float2 wrapped=float2(candidate.x-floor(candidate.x/cells.x)*cells.x,candidate.y);
   float3 random=hash3(float3(wrapped,53.7));
   float2 center=candidate+.2+random.xy*.6;
   float2 delta=(q-center)*float2(stretch,1);
   float radius=.04+.04*random.z;
   float spread=radius*radius+footprint*footprint*.18;
   float energy=radius*radius/max(spread,1e-6);
   float distance2=dot(delta,delta);
   float core=exp(-2*distance2/max(spread,1e-6))*energy;
   float halo=exp(-distance2/max(spread*8,1e-6))*energy*.035;
   float active=step(1-(.025+density*.15)*stretch,hash(float3(wrapped,91.3)));
   float twinkle=.88+.12*sin(time*(.5+random.z)+random.z*41);
   float3 tint=lerp(float3(.62,.78,1),float3(1,.82,.67),random.z*random.z);
   result+=tint*(core+halo)*active*twinkle;
  }
 }
 return result*step(.0001,density);
}
float4 main(Input i):SV_Target0 {
 float scale=1.0,time=SC_Time();
 float3 ray=worldRay(i);
 float3 p=ray*(7/scale)+float3(13.1,7.3,21.7);
 float3 flow=float3(time*.014,-time*.009,time*.005);
 float cloud=fbm(p+flow);
 float detail=fbm(p*2.4+float3(cloud*.8,cloud*.5,-cloud*.6)+flow*.5);
 float wisps=pow(saturate((cloud*.65+detail*.35)*1.6-.3),1.6);
 float colorMix=smoothstep(.26,.68,cloud);
 float3 nebula=lerp(float3(.025,.11,.28),float3(.33,.055,.55),colorMix);
 float3 color=float3(.003,.004,.014)+nebula*wisps*(.25+2*0.65);
 color+=float3(.015,.07,.16)*pow(saturate(detail*1.6-.5),2)*0.65;
 color+=stars(ray,scale,0.5,time)*1.15;
 color*=1.0;
 color=color/(1+color*.45);
 return float4(color,1);
}
