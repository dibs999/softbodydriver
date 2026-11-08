const fs = require('node:fs');
const base = process.env.ENGINE_PCM_DIR || require('node:path').resolve(__dirname, '../../build-wheels/asset-sources');
const rate = 24000;
function read(name) {
  const buf = fs.readFileSync(base + '/' + name + '.pcm');
  return Float64Array.from(new Int16Array(buf.buffer, buf.byteOffset, buf.length / 2), x => x / 32768);
}
function spectrum(x, time) {
  const n=2048, dec=4, step=rate/dec/n;
  const a=new Float64Array(n), b=new Float64Array(n);
  let start=Math.round(time*rate-n*dec/2), rms=0;
  for(let i=0,j=0;i<n;i++){
    const k=start+i*dec;
    let value=0;
    for(let d=0;d<dec;d++) value += (x[k+d] || 0)/dec;
    rms+=value*value;
    a[j] = value * (.5-.5*Math.cos(2*Math.PI*i/n));
    let bit=n>>1;
    while(bit && (j&bit)){j^=bit;bit>>=1;} j^=bit;
  }
  for(let k=2;k<=n;k*=2) for(let j=0;j<k/2;j++){
    const r=Math.cos(2*Math.PI*j/k), s=-Math.sin(2*Math.PI*j/k);
    for(let i=j;i<n;i+=k){
      const l=i+k/2,u=a[l]*r-b[l]*s,v=a[l]*s+b[l]*r;
      a[l]=a[i]-u;b[l]=b[i]-v;a[i]+=u;b[i]+=v;
    }
  }
  const mag = a.map((y,i)=>Math.hypot(y,b[i]));
  const peaks=[];
  for(let i=5;i<350;i++) if(mag[i]>=mag[i-1] && mag[i]>mag[i+1]){
    const j=.5*(mag[i-1]-mag[i+1])/(mag[i-1]+mag[i+1]-2*mag[i]);
    peaks.push([(i+j)*step,mag[i]]);
  }
  peaks.sort((a,b)=>b[1]-a[1]);
  return [Math.sqrt(rms/n),peaks.slice(0,8)];
}
if(require.main===module){
  const [name,step='0.5']=process.argv.slice(2);
  const x=read(name);
  for(let t=.25;t<x.length/rate;t+=Number(step)){
    const [r,p]=spectrum(x,t);
    console.log(t.toFixed(2),r.toFixed(3),p.slice(0,5).map(([f,v])=>Math.round(f)+':'+v.toFixed(1)).join(' '));
  }
}
module.exports={read,spectrum,rate};
