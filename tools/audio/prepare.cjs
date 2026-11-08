const fs = require('node:fs');
const path = require('node:path');
const {read, spectrum, rate} = require('./analyze.cjs');
// Remove fixed electrical/recording tones, then stabilise short acceleration recordings
// to one reference firing rate before looping. This prevents revs rising inside each loop.
function notch(x, hz, q) {
  const w=2*Math.PI*hz/rate, a=Math.sin(w)/(2*q), c=Math.cos(w);
  let x1=0,x2=0,y1=0,y2=0;
  for(let i=0;i<x.length;i++) {
    const s=x[i], y=(s-2*c*x1+x2+2*c*y1-(1-a)*y2)/(1+a);
    x2=x1;x1=s;y2=y1;y1=y;x[i]=y;
  }
}
const clips = require('./clips.json');
const target=path.resolve(__dirname,'../../game/audio/engine');
for(const [name,[source,from,to,f0]] of Object.entries(clips)) {
 const raw=read(source), x=raw.slice();
 if(source==='maserati') notch(x,85,18);
 if(source==='rover') notch(x,50,5);
 if(source==='mini') {notch(x,950,7);notch(x,1000,12);}
 let dc=0, lp=0;
 const hp=1-Math.exp(-2*Math.PI*22/rate), cut=source==='rover'?4500:6500;
 const a=1-Math.exp(-2*Math.PI*cut/rate);
 for(let i=0;i<x.length;i++){dc+=hp*(x[i]-dc);lp+=a*(x[i]-dc-lp);x[i]=lp;}
 // Estimate nearby firing harmonics, constrain tracking to avoid octave jumps.
 const track=[];
 for(let t=from;t<=to+.05;t+=.04) {
   const peaks=spectrum(x,t)[1];
   const candidates=peaks.filter(p=>Math.abs(p[0]/f0-1)<.24);
   candidates.sort((a,b)=>(b[1]/(1+12*Math.abs(b[0]/f0-1)))-(a[1]/(1+12*Math.abs(a[0]/f0-1))));
   track.push(candidates.length?candidates[0][0]:f0);
 }
 const out=[];
 let cursor=from*rate, filtered=f0;
 while(cursor<to*rate-2){
   const ti=(cursor/rate-from)/.04, j=Math.min(track.length-2,Math.floor(ti)), f=ti-j;
   filtered+=.002*((track[j]*(1-f)+track[j+1]*f)-filtered);
   const k=Math.floor(cursor), mix=cursor-k;
   out.push(x[k]*(1-mix)+x[k+1]*mix);
   cursor+=Math.max(.75,Math.min(1.30,f0/filtered));
 }
 // Match phase at the loop boundary using cross-correlation, with a raised-cosine seam.
 const n=Math.min(1400,Math.floor(out.length*.14));
 let best=-1e9,end=out.length-n-1;
 for(let p=Math.round(out.length*.72);p+n<out.length;p++){
   let ab=0,aa=0,bb=0;
   for(let j=0;j<n;j+=5){const a=out[j],b=out[p+j];ab+=a*b;aa+=a*a;bb+=b*b;}
   const score=ab/Math.sqrt(Math.max(1e-12,aa*bb))-.08*Math.abs(Math.log((aa+1e-12)/(bb+1e-12)))+.10*p/out.length;
   if(score>best){best=score;end=p;}
 }
 const y=Float64Array.from(out.slice(n,end+n));
 for(let i=0;i<n;i++){const t=.5-.5*Math.cos(Math.PI*i/(n-1));y[end-n+i]=out[end+i]*(1-t)+out[i]*t;}
 let sq=0,peak=0;for(const s of y){sq+=s*s;peak=Math.max(peak,Math.abs(s));}
 const gain=Math.min(.15/Math.sqrt(sq/y.length),.66/peak);
 const b=Buffer.alloc(44+y.length*2);b.write('RIFF');b.writeUInt32LE(b.length-8,4);b.write('WAVEfmt ',8);b.writeUInt32LE(16,16);b.writeUInt16LE(1,20);b.writeUInt16LE(1,22);b.writeUInt32LE(rate,24);b.writeUInt32LE(rate*2,28);b.writeUInt16LE(2,32);b.writeUInt16LE(16,34);b.write('data',36);b.writeUInt32LE(y.length*2,40);
 for(let i=0;i<y.length;i++)b.writeInt16LE(Math.round(y[i]*gain*32767),44+i*2);
 fs.writeFileSync(path.join(target,name+'.wav'),b);
 console.log(name,(y.length/rate).toFixed(2)+'s','seam',Math.abs(y[0]-y[y.length-1]).toFixed(4));
}
