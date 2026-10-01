import assert from 'node:assert/strict';
import {validateImages,rasterURL} from './images.mjs';
const image={id:'one',dataURL:'data:image/png;base64,AAAA'};
assert.deepEqual(validateImages([image]),[image]);
for(const url of ['javascript:alert(1)','https://example.com/image.png','data:image/svg+xml;base64,AAAA','data:image/png;base64,\"onerror=alert(1)','data:image/png;base64,'])assert.equal(rasterURL(url),false);
assert.throws(()=>validateImages(Array(9).fill(image)));
assert.throws(()=>validateImages([{...image,dataURL:'data:image/png;base64,'+'A'.repeat(1500000)}]));
console.log('PASS: image formats and payload limits');
