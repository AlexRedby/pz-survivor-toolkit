#!/usr/bin/env node
/**
 * Bake the approved Polaris heavy-dashboard rocker from a shared rigid cap.
 * Requires Node.js and @napi-rs/canvas (available via normal module resolution
 * or NODE_PATH). No game installation or mockup HTML is read by this tool.
 *
 * Usage: node tools/generate_vehicle_light_rocker.cjs [--output DIRECTORY]
 * Optional --high-symbol FILE and --low-symbol FILE replace the embedded
 * original 15x12 dashboard symbol PNGs. The default embeds the approved source
 * pixels so a fresh checkout reproduces the shipped artwork by itself.
 * Every target size is sampled directly from its 160x304 (4x logical 40x76)
 * master, with 16-degree travel and one 0.3-pixel optical-softening pass.
 */
'use strict';
const fs = require('node:fs');
const path = require('node:path');
const { createCanvas, loadImage } = require('@napi-rs/canvas');

// Approved native dashboard symbol pixels, before reflection/white treatment.
const symbols={"high":"data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAA8AAAAMCAYAAAC9QufkAAABL0lEQVR4nJXSu0sdYRAF8N+9vkHh+sBHJSKxkaRIoWIriKViYauNjRhSpBFLO1tJ518QyH+QwqCVrSCioBA7Cx9IuKDGDQNzYb2dBxa+nf3OOTNntlIUhRKq6MynkrUn1PGiCa2lczv60YcJfMA4fuE3bksCvbirFEURDh0YwQy28DEvnafQHnaxjiFc4Kaa7lGYw36+r2UH8/iJJfzFKAaxiZ642JZt7OAQG/iD53SP2jJqQchaCHaFc7T9GcP4gssSsYx7POY5xOpBfs0Pgel0iPCaUcuW3zhHgsc4wHes5mzRyUCO1HB+yHNkUY+0Gysby0QXcYWj3PsszvAN2zjBdZncEOjGFFYwmfW7DDMEfuTug/S1TA5EeC0p1PjD/uVokc0CTvEpRm0mvwv/AW3RSspvUyCRAAAAAElFTkSuQmCC","low":"data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAA8AAAAMCAYAAAC9QufkAAAACXBIWXMAAAhNAAAITQEhiCGBAAABzUlEQVQokZWSMWtUQRSFvzszb/btxugmCirYiJhGZDWFBhuLgNqIEQvLuLG0WrDRSkllQESCncSsYCWSFFppEY1YWBlsgoX+AxPUmLw38+ZauGrYzgO3udxzDpx7hG043p43QJ5SygHprUtgc6U7FenDnwNak3PeWrsbMcNoGlHVwymlQ8Ar4DXwtV9AWpNzAtSMMfud92PGuhvWuaMA5dbmp1iGEdU0C8wAH4EloLvSnVo0gBORvca68ayWPxzYNeTqgzvbqA67zJ/xef5MRC4aazeATs90oTU5t2CATESGjHPTvt5Yts6dr2J88m720lqtMfDN1xvLLvMHREwTuNcjd4DbDhBVHbXO7RM4LcZ8XrpzTgGcryHGYLMMJ7K++SN0gAs9kUUDJGBdVRExJxFpnr31xgNoSr9HlVAUTeBRv3MUkfcpxqWUqgfAHtX0fPzmy+8xhMFQFEOxLBGRdaC93VkAjrXnnbX2oM/rM77emHCZ/1LF+DYUW6b4uXEqlMUqcB14AdzvJf7vz6NXHzuf13cAJxC5rFV1JIaSGMIaMA2sAneBCaAJdP6SAcauPRURsarqVFWqEIgxVJpSXOlOpW2FugJ86G/cf+EXOh60u4PnWlUAAAAASUVORK5CYII="};
const config={travel:16,softness:.3};
let art;
const angle=mode=>({off:-1,low:0,high:1}[mode])*config.travel*Math.PI/180;
function rotated(y,z,mode){const a=angle(mode),c=Math.cos(a),s=Math.sin(a),d=z+1.6;return {y:y*c-d*s,z:y*s+d*c-1.6};}
function faceZ(y){return 6.4+.8*Math.cos(y/30*Math.PI/2)-1.4*Math.pow(Math.abs(y)/30,16);}
function round(ctx,x,y,w,h,r){ctx.beginPath();ctx.roundRect(x,y,w,h,r);}
function makeTexture(){
 const canvas=createCanvas(200,480);const c=canvas.getContext('2d');c.scale(8,8);
 let g=c.createLinearGradient(0,0,25,0);g.addColorStop(0,'#353636');g.addColorStop(.18,'#3c3d3c');g.addColorStop(.72,'#393a39');g.addColorStop(1,'#303130');c.translate(12.5,30);c.fillStyle=g;c.fillRect(-12.5,-30,25,60);
 const pixels=c.getImageData(0,0,200,480);let seed=41;for(let i=0;i<pixels.data.length;i+=4){seed=(seed*1664525+1013904223)>>>0;const n=((seed>>>24)/255-.5)*4;for(let k=0;k<3;k++)pixels.data[i+k]+=n;}c.putImageData(pixels,0,0);
 c.strokeStyle='rgba(15,16,15,.5)';c.lineWidth=.45;c.fillStyle='#51514d';round(c,-8.1,-22.8,16.2,17.2,2);c.fill();c.stroke();c.fillStyle='rgba(145,145,135,.14)';round(c,-7.8,-22.5,15.6,16.6,1.8);c.fill();
 c.save();c.globalAlpha=.76;c.drawImage(art.high,-6.15,-19.6,12.3,10.4);c.drawImage(art.low,-6.3,-1.7,12.6,10.4);c.restore();
 for(const y of [15,18,21]){c.fillStyle='#303130';round(c,-9,y,18,.9,.4);c.fill();c.fillStyle='#4d4e4a';round(c,-8.8,y+.65,17.6,.45,.2);c.fill();}
 return c.getImageData(0,0,200,480);
}
function renderSprite(mode,texture){
 const out=createCanvas(160,304);const ctx=out.getContext('2d');ctx.scale(4,4);
 ctx.shadowColor='rgba(0,0,0,.55)';ctx.shadowBlur=1.5;ctx.shadowOffsetY=.6;
 let g=ctx.createLinearGradient(4,2,36,75);g.addColorStop(0,'#626360');g.addColorStop(.1,'#484947');g.addColorStop(.6,'#363735');g.addColorStop(1,'#292a29');ctx.fillStyle=g;round(ctx,3.2,2.2,33.6,71.6,5.1);ctx.fill();ctx.shadowBlur=0;ctx.shadowOffsetY=0;
 ctx.strokeStyle='rgba(115,116,108,.23)';ctx.lineWidth=.5;round(ctx,3.8,2.7,32.4,70.5,4.6);ctx.stroke();
 ctx.fillStyle='#181a19';round(ctx,6,5.7,28,65,3.9);ctx.fill();
 g=ctx.createLinearGradient(0,5.7,0,70.7);g.addColorStop(0,'#111312');g.addColorStop(.5,'#222422');g.addColorStop(1,'#111211');ctx.fillStyle=g;round(ctx,6.6,6.2,26.8,64.2,3.3);ctx.fill();
 // A raised cap casts a deeper shadow into the fixed opening.
 ctx.save();round(ctx,6.6,6.2,26.8,64.2,3.3);ctx.clip();
 const outline=[];
 for(let y=-30;y<=30;y++)outline.push([-12.25+1.25*Math.pow(Math.abs(y)/30,14),y]);
 for(let y=30;y>=-30;y--)outline.push([12.25-1.25*Math.pow(Math.abs(y)/30,14),y]);
 ctx.beginPath();outline.forEach(([x,y],i)=>{const r=rotated(y,faceZ(y)-.7,mode),z=Math.max(0,r.z),sx=20+x+z*.38,sy=38+r.y+z*.52;i?ctx.lineTo(sx,sy):ctx.moveTo(sx,sy);});ctx.closePath();
 ctx.fillStyle='rgba(0,0,0,.82)';ctx.shadowColor='rgba(0,0,0,.72)';ctx.shadowBlur=2.5;ctx.shadowOffsetY=.6;ctx.fill();ctx.restore();
 const W=160,H=304,data=ctx.getImageData(0,0,W,H),zbuf=new Float32Array(W*H);zbuf.fill(-1e5);
 const light=[-.36,-.48,.8],tex=texture.data,tw=texture.width,th=texture.height;
 function vertex(x,y,z,u=0,v=0){const r=rotated(y,z,mode),f=205/(205-r.z);return {x:(20+x*f)*4,y:(38+r.y*f)*4,z:r.z,u,v,q:f};}
 function tri(a,b,c,normal,textured=false){
  const area=(b.x-a.x)*(c.y-a.y)-(b.y-a.y)*(c.x-a.x);if(Math.abs(area)<.001)return;
  const minX=Math.max(0,Math.floor(Math.min(a.x,b.x,c.x))),maxX=Math.min(W-1,Math.ceil(Math.max(a.x,b.x,c.x))),minY=Math.max(0,Math.floor(Math.min(a.y,b.y,c.y))),maxY=Math.min(H-1,Math.ceil(Math.max(a.y,b.y,c.y)));
  const an=angle(mode),ny=normal[1]*Math.cos(an)-normal[2]*Math.sin(an),nz=normal[1]*Math.sin(an)+normal[2]*Math.cos(an);if(nz<=-.08)return;
  const diffuse=Math.max(0,normal[0]*light[0]+ny*light[1]+nz*light[2]);const shade=.38+.75*diffuse;
  for(let y=minY;y<=maxY;y++)for(let x=minX;x<=maxX;x++){
   const px=x+.5,py=y+.5,w0=((b.x-px)*(c.y-py)-(b.y-py)*(c.x-px))/area,w1=((c.x-px)*(a.y-py)-(c.y-py)*(a.x-px))/area,w2=1-w0-w1;if(w0<-.00001||w1<-.00001||w2<-.00001)continue;
   const z=w0*a.z+w1*b.z+w2*c.z,ind=y*W+x;if(z<=zbuf[ind])continue;
   // The bezel occludes cap material behind its panel plane.
   if(z<-.25&&(y<29||y>275||x<29||x>131))continue;
   zbuf[ind]=z;const k=ind*4;
   if(textured){const q=w0*a.q+w1*b.q+w2*c.q,u=(w0*a.u*a.q+w1*b.u*b.q+w2*c.u*c.q)/q,v=(w0*a.v*a.q+w1*b.v*b.q+w2*c.v*c.q)/q;
    const ti=(Math.min(th-1,Math.max(0,Math.floor(v*(th-1))))*tw+Math.min(tw-1,Math.max(0,Math.floor(u*(tw-1)))))*4;for(let j=0;j<3;j++)data.data[k+j]=Math.min(255,tex[ti+j]*shade*(.44+.56*Math.max(0,Math.min(1,z/4.5))));
   }else{for(let j=0;j<3;j++)data.data[k+j]=[72,73,69][j]*(.52+.58*diffuse);}
   data.data[k+3]=255;
  }
 }
 function quad(a,b,c,d,n,t=false){tri(a,b,c,n,t);tri(a,c,d,n,t);}
 const ny=64,nx=18,halfWidth=y=>12.25-1.25*Math.pow(Math.abs(y)/30,14);
 for(let j=0;j<ny;j++)for(let i=0;i<nx;i++){
  const y0=-30+j*60/ny,y1=-30+(j+1)*60/ny,u0=i/nx,u1=(i+1)/nx,x00=(2*u0-1)*halfWidth(y0),x01=(2*u1-1)*halfWidth(y0),x10=(2*u0-1)*halfWidth(y1),x11=(2*u1-1)*halfWidth(y1);
  const zz=(x,y)=>faceZ(y)-.7*Math.pow(Math.abs(x)/halfWidth(y),12),ym=(y0+y1)/2,xm=(x00+x01)/2;
  const dx=-.7*12*Math.sign(xm)*Math.pow(Math.abs(xm)/halfWidth(ym),11)/halfWidth(ym),dy=-.8*Math.PI/60*Math.sin(ym/30*Math.PI/2)-1.4*16*Math.sign(ym)*Math.pow(Math.abs(ym)/30,15)/30,len=Math.hypot(dx,dy,1),n=[-dx/len,-dy/len,1/len];
  quad(vertex(x00,y0,zz(x00,y0),u0,j/ny),vertex(x01,y0,zz(x01,y0),u1,j/ny),vertex(x11,y1,zz(x11,y1),u1,(j+1)/ny),vertex(x10,y1,zz(x10,y1),u0,(j+1)/ny),n,true);
 }
 // End and side walls belong to the same rigid cap.
 for(const y of [-30,30])for(let i=0;i<nx;i++){const hw=halfWidth(y),x0=-hw+i*2*hw/nx,x1=-hw+(i+1)*2*hw/nx,ztop=x=>faceZ(y)-.7*Math.pow(Math.abs(x)/hw,12);quad(vertex(x0,y,-2.2),vertex(x1,y,-2.2),vertex(x1,y,ztop(x1)),vertex(x0,y,ztop(x0)),[0,Math.sign(y),0]);}
 for(const sign of [-1,1])for(let j=0;j<ny;j++){const y0=-30+j*60/ny,y1=y0+60/ny;quad(vertex(sign*halfWidth(y0),y0,-2.2),vertex(sign*halfWidth(y1),y1,-2.2),vertex(sign*halfWidth(y1),y1,faceZ(y1)-.7),vertex(sign*halfWidth(y0),y0,faceZ(y0)-.7),[sign,0,0]);}
 ctx.setTransform(1,0,0,1,0,0);ctx.putImageData(data,0,0);
 // The exposed end's bevel catches light; the pressed end stays in the recess.
 if(mode!=='low'){
  const y=mode==='off'?-30:30;ctx.beginPath();
  for(let i=0;i<=36;i++){const x=-10.6+i*21.2/36,z=faceZ(y)-.7*Math.pow(Math.abs(x)/11,12),p=vertex(x,y,z);i?ctx.lineTo(p.x,p.y):ctx.moveTo(p.x,p.y);}
  ctx.strokeStyle=mode==='off'?'rgba(146,148,135,.72)':'rgba(110,112,101,.72)';ctx.lineWidth=2.2;ctx.stroke();
 }
 // One optical softening pass, matching the small native panel artwork.
 // Copy pixels explicitly: native canvas drawImage may retain the source
 // backing surface when it is cleared before the pending draw is resolved.
 if(config.softness>0){const copy=createCanvas(W,H);copy.getContext('2d').putImageData(ctx.getImageData(0,0,W,H),0,0);ctx.clearRect(0,0,W,H);ctx.filter='blur('+config.softness+'px)';ctx.drawImage(copy,0,0);ctx.filter='none';}
 return out;
}
function whiteSymbol(source,isLow){const c=createCanvas(source.width,source.height);const x=c.getContext('2d');x.translate(c.width,0);x.scale(-1,1);if(isLow)x.filter='grayscale(1) brightness(2.7)';x.drawImage(source,0,0);return c;}

const scales = { '0.75x': .75, '1x': 1, '1.4x': 1.4, '2x': 2 };
async function main() {
 const args = process.argv.slice(2);
 const options = { output: path.resolve(__dirname, '../PZSurvivorToolkit/42/media/ui/PZSurvivorToolkit/beams/heavy') };
 for (let i=0; i<args.length; i++) {
  if (args[i]==='--help') {
   console.log('Usage: node tools/generate_vehicle_light_rocker.cjs [--output DIRECTORY] [--high-symbol PNG] [--low-symbol PNG]');
   return;
  }
  const key = { '--output':'output', '--high-symbol':'high', '--low-symbol':'low' }[args[i]];
  if (!key || !args[i+1] || args[i+1].startsWith('--')) throw new Error('Unknown option or missing value: '+args[i]);
  options[key] = path.resolve(args[++i]);
 }
 const [high,low] = await Promise.all([
  loadImage(options.high || symbols.high), loadImage(options.low || symbols.low)
 ]);
 art={high:whiteSymbol(high,false),low:whiteSymbol(low,true)};
 const texture=makeTexture();
 for (const mode of ['off','low','high']) {
  const master=renderSprite(mode,texture);
  for (const [scale,factor] of Object.entries(scales)) {
   const width=Math.round(29*factor),height=Math.round(55*factor);
   const out=createCanvas(width,height), ctx=out.getContext('2d');
   ctx.imageSmoothingEnabled=true;
   ctx.imageSmoothingQuality='high';
   ctx.drawImage(master,0,0,width,height);
   const directory=path.join(options.output,scale);
   fs.mkdirSync(directory,{recursive:true});
   const filename=path.join(directory,'rocker-'+mode+'.png');
   fs.writeFileSync(filename,out.toBuffer('image/png'));
   console.log(path.relative(process.cwd(),filename)+': '+width+'x'+height);
  }
 }
}
main().catch(error => { console.error(error.message); process.exitCode=1; });
