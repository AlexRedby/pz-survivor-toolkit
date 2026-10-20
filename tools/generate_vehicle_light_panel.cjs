#!/usr/bin/env node
/**
 * Remove only the heavy dashboard's printed PULL-ON legend.
 * Usage: node tools/generate_vehicle_light_panel.cjs [--output DIRECTORY]
 * Requires @napi-rs/canvas via module resolution or NODE_PATH.
 *
 * Embedded native donor strips come from RealisticDashboardAndGauges (Workshop
 * 3635591071), 42/media/ui/vehicles/heavy/dash/<scale>/dash.png. The same source
 * legend also occurs in dash_no_trunk.png. Each strip lies below it on the
 * same original faceplate. Exact native pixels preserve its grain and shade;
 * source SHA-256 and donor/target bounds are recorded below. No resizing occurs.
 *
 * Draw at background-local (0,0), at authored PNG dimensions, after upstream
 * background render. Pixels outside target are transparent. Window switch,
 * lock/trunk controls, borders and gauges remain untouched.
 * The circular original knob/recess belongs to light_knob_off/on.png, not the
 * background. Replacing lightsTex render removes it; this patch removes only
 * the obsolete legend on dash.png/dash_no_trunk.png.
 * No game files are read or modified by this generator.
 */
'use strict';
const fs=require('node:fs');
const path=require('node:path');
const {createCanvas,loadImage}=require('@napi-rs/canvas');
const samples = {
  "0.75x": {
    "canvas": [
      58,
      100
    ],
    "target": [
      27,
      91,
      31,
      9
    ],
    "donor": [
      27,
      104,
      31,
      9
    ],
    "sourceSha256": "68aaa80ba0bced8566c6da99f65caea141fc72684a9891f20e8e5846351a3f5c",
    "png": "iVBORw0KGgoAAAANSUhEUgAAAB8AAAAJCAYAAADKIfe/AAAABHNCSVQICAgIfAhkiAAAAAFzUkdCAK7OHOkAAADbSURBVDiNfVNbDsMwCMNOz9T7Xyywj83IQe2QokS8bQju+669d0REAAgAIamqINlvAJGZ7aO3TlUdsfKTXjrlZWa2QWcWk+itm2T7ex5vQHoAsdYKkt3U5YgnanWZmQcL0iuhsyG7y2RFdnqiGTCPJxBaFXY29t7N4j9QfKNNCUl2AQ/s7n/UO516yzbjpLsU4MpZwJfExWfuI3pCO/2OmbuDiy+gj0SszEKTPR3fC+nos5q3IxaNPjcl01etqlhrHQ36sjpqAF/a5590Oh2Jo32ieN6TDWexquIDgDEP3wkMujUAAAAASUVORK5CYII="
  },
  "1x": {
    "canvas": [
      77,
      133
    ],
    "target": [
      36,
      122,
      41,
      11
    ],
    "donor": [
      36,
      139,
      41,
      11
    ],
    "sourceSha256": "d4ef92e4238543dc96b48a77043fe19e9d61e7f870c6d4f270c157230431ccf8",
    "png": "iVBORw0KGgoAAAANSUhEUgAAACkAAAALCAYAAADiBKTLAAAABHNCSVQICAgIfAhkiAAAAAFzUkdCAK7OHOkAAAGpSURBVDiNXZVbsiMhDENlHmvK/tcFxvdj5riUdFVXCH7JsqDj8/nUOUcRIUmKiH6rShGh954kac4pSaoqvfc059R7T1XVa/clXpLee503M9snInTO0Vqr9yVpjKHM1JxTww0U92KAYY3fnFPnnI7JTEVE+957GxAAq6rjaR4/QM85NcbQGKNJW6AmAU4wBEhv4Bf8nFOZ2cUpkpm9vvd2YZ8IQMi99/4iQpKGO661GgBOEdEF8KmqLkiTe+8GVFVfL/FM7b3Xvg1kDK21dO9tQmB/OEte1McLu3Tsdh+3/+IHuxGhvfeXDPAl9723te0SbCbp1Blg34siZgBiZ8xVpbVWrwGA7pgW+qWJzGybS/C9pwUgErmW6AS7C5+CxKBRHzcPE/A6DpxDB0nEIJPBGNCga8KLAMZFz/uln/9ac3YpzkR+AblevdGWV899DJ1zmkE/GCQjMZ1j4zChsd9bAjuNOFvUYSrsk2Ot9e+eJNCTuaacPU48PrDiVw8PTSMfNEfee+8Xy+SGkG4EABh5SOxfDR+/j8+vEb+g2Zd9KLwZb9bz+f/M1B9wiiQPTm6MAwAAAABJRU5ErkJggg=="
  },
  "1.4x": {
    "canvas": [
      108,
      187
    ],
    "target": [
      50,
      170,
      58,
      17
    ],
    "donor": [
      50,
      194,
      58,
      17
    ],
    "sourceSha256": "d3ba91dff1c85fc9dbeb6f5ce8899f90db7412246a3473a52719574a83da87ab",
    "png": "iVBORw0KGgoAAAANSUhEUgAAADoAAAARCAYAAACM0L/dAAAABHNCSVQICAgIfAhkiAAAAAFzUkdCAK7OHOkAAAJpSURBVEiJhVdbkiMhDLOBK+X+Bwttz0fKHrUiOlRtLU3AD1l+jL9er3R3u67L3N1w1be7W2b2PiJ6z28ys8/qHt6NiJY1xpD6IuImOzNv+vFsztl7voP71oSX6wEvdgodQAMYhDGGjTGkXATztBAcd7cxxg181Ity65272zJCHp1GI0owohgRFhHtRP0WEc2QzOw9Glh3CgRkFDOIWcKRc3ebc7btZe91XX22VLgNaIXnGG38v4CqPSozYotigrqvbOHFUeV7BayZfSKqUDwpZmczU9KSKck5xCx5ou7Tb0ag4xn6sJRyNKAeYYSRikjdoiKjWquKDO9P+YV7zHMGCFOk9KHNmWmrPrhCqmhgtVT5hILROUQZ5ZSzBRjnHOf6qSjVuWJWs+6JCrxUO2FH0Rlmhh2qMoNb/xBQvse6T/Kko1zZTkVEOcOK2Sg2Bp1ACrKxXBRZJlKc9WDqLfxAYRgdzDMuKlyY0AmkZUR0C+D7J6A5yhypE63nnObutvduG1Y9rN6oJpgTYsoQBu00rSjanQYAzD1FXU4dtvlGXa6Wv6YkFQnVelRhUhR9kqHkncDidKjVfRTzjdsE5wVPKuq8vqt6Ih2L2ph/ON/WRMPOGuWtARNVUcJ7i/MQSzsKrm/Vy0qZihBPShzN+n2tdasJmD4o+7qur2HAqLWhre2DipiKIC41kqnWw3mFtFKjotL1q9WoaciI6pn5X4yenKzJxKgVqPxlxfwOlSvjn5xl8E6OcjHNzE+OljOMHFIIUXq/31/tQxmDsuactvduI9dat298Y1RR1d/K3LLq7t77004gFTLT/gA7LmI5hfFQRgAAAABJRU5ErkJggg=="
  },
  "2x": {
    "canvas": [
      154,
      266
    ],
    "target": [
      72,
      244,
      82,
      22
    ],
    "donor": [
      72,
      278,
      82,
      22
    ],
    "sourceSha256": "d865268fc36f1be52a8e1cb453a8a25151ab34648192871c8f91f023f4286c8b",
    "png": "iVBORw0KGgoAAAANSUhEUgAAAFIAAAAWCAYAAABT5cvhAAAABHNCSVQICAgIfAhkiAAAAAFzUkdCAK7OHOkAAAIGSURBVFiF7ZhLjoMwEAUNOGfK/c9FgFmMCg0Vniwkz85vQ9r4F7rcbXt6v99HKaWs61pKKWWapvJX2H4ex3Gx932/tFuW5WJTn3q8x+a9y1O/Hh9R3/Pdtu22H97z/2utt/XRPM+X9/Qz39Yeeqyavjwet+f9NGH0RzkeNHEQwHuTR7n7/Xw+vxMXOa0Vg+3xEtlpRZlI2g0iO6nyw+SgMwYET5pIl5s01/c4eNqkML6JcDnEYrt/5P/pFcbz9XrdtnN/g8hOqikGJsLsEWyTQH1iGTHRnkQmy9nX45sojw+xjO/5uL1jeiLcsfK04yceeqSaYpNjjD2d9nfOkvY0ekqc7UQuT2KbdwetGNzaVzq7DyI7qyZP2wNpX5nIcIyBEGzHWmdhn0ggAyXSTYxjpOfn/5nG8/f5WnG3tYceqybSkudMQGrfinF4PJHt/WuKnSjF2nQiM7mJzLTfdDYfRHZSdZbzWZbshVqxKXkcJbIcw7x7cDY1sczbZHpf7FsblPrxfjndeg0iO+lMTSYg3c6YRLdHvlUyIW7HCoAIjwcZ6ezv9mm3gRybzw+iLO/6aJy1/0nVMcOEfN27NbI4Sv0gZ+N0r5j6Z8UQ29NtEPW84tJ+Ntmep09yg8hOql7rKdsiez7dhljpvq91wkn10i2STxzpLJ1OdI7RaX5fN/rxiw090g9aIScUqirC7wAAAABJRU5ErkJggg=="
  }
};
async function main() {
 let output=path.resolve(__dirname,'../PZSurvivorToolkit/42/media/ui/PZSurvivorToolkit/beams/heavy');
 const args=process.argv.slice(2);
 for(let i=0;i<args.length;i++) {
  if(args[i]==='--output' && args[i+1]) output=path.resolve(args[++i]);
  else throw new Error('Unknown or incomplete argument: '+args[i]);
 }
 for(const [scale,sample] of Object.entries(samples)) {
  const image=await loadImage(Buffer.from(sample.png,'base64'));
  const canvas=createCanvas(...sample.canvas),ctx=canvas.getContext('2d');
  const [x,y,w,h]=sample.target;
  if(image.width!==w || image.height!==h) throw new Error('Native donor dimensions differ: '+scale);
  ctx.drawImage(image,x,y);
  const pixels=ctx.getImageData(0,0,...sample.canvas).data;
  // Cover the complete obsolete legend without changing neighboring art.
  for(let py=0;py<sample.canvas[1];py++) for(let px=0;px<sample.canvas[0];px++) {
   const alpha=pixels[(py*sample.canvas[0]+px)*4+3];
   const expected=px>=x && px<x+w && py>=y && py<y+h ? 255 : 0;
   if(alpha!==expected) throw new Error('Unexpected coverage: '+scale+' '+px+','+py);
  }
  const dir=path.join(output,scale);fs.mkdirSync(dir,{recursive:true});
  const target=path.join(dir,'light-panel.png');fs.writeFileSync(target,canvas.toBuffer('image/png'));
  console.log(scale+': '+sample.canvas.join('x')+'; opaque xywh '+sample.target.join(',')+' -> '+target);
 }
}
main().catch(error=>{console.error(error);process.exitCode=1;});
