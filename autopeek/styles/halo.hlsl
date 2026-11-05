struct Input {float4 pos:SV_POSITION;float4 col:COLOR0;float2 uv:TEXCOORD0;};

float stroke(float r,float target,float width,float aa) {
    return 1-smoothstep(width,width+aa,abs(r-target));
}

float4 main(Input i):SV_Target {
    float elapsed=SC_Time();
    if(elapsed>2.65)elapsed=2.65+fmod(elapsed-2.65,2.4);
    elapsed=floor(elapsed*60+.5)/60;
    float releaseAge=floor(max(SC_ReleaseAge(),0)*60+.5)/60;
    float visibility=SC_ReleaseAge()<0?1:1-smoothstep(0,.28,releaseAge);
    float2 p=i.uv*2-1;
    float r=length(p);
    clip(.94-r);
    float aa=clamp(fwidth(r),.0015,.025);
    float2 direction=float2(cos(elapsed*.65),sin(elapsed*.65));
    float arc=pow(saturate(dot(p/max(r,.0001),direction)*.5+.5),20);
    float opposite=pow(saturate(-dot(p/max(r,.0001),direction)*.5+.5),28)*.45;
    float accents=arc+opposite;
    float contour=stroke(r,.82,.0055,aa);
    float inner=stroke(r,.785,.0018,aa)*.16;
    float glow=exp(-abs(r-.82)*80)*(.035+accents*.09);
    float phase=frac(elapsed/2.4);
    float pulse=stroke(r,.10+phase*.66,.008,aa)*sin(phase*3.14159265)*.18;
    float fill=exp(-r*r*3.8)*.055;
    float boundary=1-smoothstep(.87,.94,r);
    float energy=contour*(.48+accents*.48)+inner+glow+pulse+fill;
    float3 tint=lerp(SC_Color(1),float3(1,1,1),saturate(contour*(.22+accents*.45)+pulse*.3));
    float opacity=saturate(energy)*boundary*visibility*i.col.a;
    return float4(tint,opacity);
}
