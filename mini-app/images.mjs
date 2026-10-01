export const rasterURL = value => typeof value === 'string' && /^data:image\/(jpeg|png);base64,[A-Za-z0-9+/]+={0,2}$/.test(value);
export function validateImages(images) {
 if(!Array.isArray(images)||images.length>8||images.reduce((n,i)=>n+(i.dataURL?.length||0),0)>1500000)throw new Error('В задачу можно добавить до 8 картинок, всего до 1,5 МБ.');
 for(const i of images)if(!rasterURL(i.dataURL))throw new Error('Не удалось прочитать картинку.');
 return images;
}
export async function prepareImage(file) {
 if(!file.type.startsWith('image/'))throw new Error('Выберите изображение.');
 const url=URL.createObjectURL(file),image=new Image();
 try {
  image.src=url;await image.decode();
  let longest=1600;
  for(let attempt=0;attempt<6;attempt++) {
   const scale=Math.min(1,longest/Math.max(image.naturalWidth,image.naturalHeight)),canvas=document.createElement('canvas');
   canvas.width=Math.max(1,Math.round(image.naturalWidth*scale));canvas.height=Math.max(1,Math.round(image.naturalHeight*scale));
   const ctx=canvas.getContext('2d');ctx.fillStyle='#fff';ctx.fillRect(0,0,canvas.width,canvas.height);ctx.drawImage(image,0,0,canvas.width,canvas.height);
   const dataURL=canvas.toDataURL('image/jpeg',.8);
   if(dataURL.length<=400023)return {id:crypto.randomUUID(),dataURL};
   longest*=.75;
  }
  throw new Error('Картинка слишком большая.');
 }finally{URL.revokeObjectURL(url);}
}
let active=null;
export const isImageOpen=()=>!!active;
export function closeImage() {active?.close();}
export function openImage(source,notify,onClose=()=>{}) {
 if(active)return;
 const thumb=source.querySelector('img'),url=thumb?.getAttribute('src');if(!rasterURL(url))return;
 const previous=document.activeElement,oldOverflow=document.body.style.overflow,root=document.createElement('div');
 root.className='image-viewer';root.setAttribute('role','dialog');root.setAttribute('aria-modal','true');root.setAttribute('aria-label','Просмотр изображения');
 const backdrop=document.createElement('div');backdrop.className='image-veil';
 const image=new Image();image.src=url;image.className='image-expanded';image.alt='Вложение задачи';
 const copy=document.createElement('button');copy.className='image-copy';copy.type='button';copy.title='Copy';copy.setAttribute('aria-label','Скопировать картинку');copy.innerHTML='<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6"><rect x="8" y="8" width="12" height="12" rx="3"/><path d="M15 5V4a2 2 0 0 0-2-2H4a2 2 0 0 0-2 2v9a2 2 0 0 0 2 2h1"/></svg>';
 root.append(backdrop,image,copy);document.body.append(root);
 const backgrounds=[...document.body.children].filter(el=>el!==root&&el.id!=='toast'),inertStates=backgrounds.map(el=>el.inert);backgrounds.forEach(el=>el.inert=true);
 const reduced=matchMedia('(prefers-reduced-motion: reduce)').matches;
 const duration=reduced?0:320,easing='cubic-bezier(.2,.8,.2,1)';
 function destination(){const pad=24,w=innerWidth-pad*2,h=innerHeight-120,ratio=Math.min(w/(thumb.naturalWidth||1),h/(thumb.naturalHeight||1));return {left:(innerWidth-thumb.naturalWidth*ratio)/2,top:24+(h-thumb.naturalHeight*ratio)/2,width:thumb.naturalWidth*ratio,height:thumb.naturalHeight*ratio};}
 const rectStyle=r=>({left:r.left+'px',top:r.top+'px',width:r.width+'px',height:r.height+'px'});
 let closing=false,animation;
 function fit(){if(closing)return;const start=image.getBoundingClientRect();animation?.cancel();Object.assign(image.style,rectStyle(destination()));animation=image.animate([rectStyle(start),rectStyle(destination())],{duration,easing});}
 Object.assign(image.style,rectStyle(source.getBoundingClientRect()));
 source.style.visibility='hidden';document.body.style.overflow='hidden';
 // One raster element animates its rectangle, so opening and closing remain continuous.
 fit();backdrop.animate([{opacity:0},{opacity:1}],{duration,easing});copy.animate([{opacity:0},{opacity:1}],{duration,easing});copy.focus({preventScroll:true});
 async function close(){if(closing)return;closing=true;const current=image.getBoundingClientRect();animation?.cancel();const end=source.isConnected?source.getBoundingClientRect():current;Object.assign(image.style,rectStyle(end));
  const back=image.animate([rectStyle(current),rectStyle(end)],{duration:reduced?0:280,easing});backdrop.animate([{opacity:1},{opacity:0}],{duration:reduced?0:280,fill:'forwards'});copy.style.opacity='0';
  await back.finished.catch(()=>{});source.style.visibility='';root.remove();backgrounds.forEach((el,i)=>el.inert=inertStates[i]);document.body.style.overflow=oldOverflow;document.removeEventListener('keydown',keys,true);window.removeEventListener('resize',fit);active=null;if(previous?.isConnected)previous.focus({preventScroll:true});onClose();
 }
 function keys(e){if(e.key==='Escape'){e.preventDefault();e.stopImmediatePropagation();close();}else if(e.key==='Tab'){e.preventDefault();copy.focus();}else{e.stopImmediatePropagation();}}
 document.addEventListener('keydown',keys,true);window.addEventListener('resize',fit);
 root.addEventListener('click',e=>{e.stopPropagation();if(e.target===root||e.target===backdrop)close();});
 copy.addEventListener('click',async()=>{
  try {
   if(!navigator.clipboard?.write||typeof ClipboardItem==='undefined')throw new Error('В этом браузере копирование картинок недоступно.');
   // Start write in the user gesture; Safari accepts a promised PNG blob.
   const png=(async()=>{await image.decode();const canvas=document.createElement('canvas');canvas.width=image.naturalWidth;canvas.height=image.naturalHeight;canvas.getContext('2d').drawImage(image,0,0);return await new Promise((resolve,reject)=>canvas.toBlob(blob=>blob?resolve(blob):reject(new Error('Не удалось скопировать.')),'image/png'));})();
   await navigator.clipboard.write([new ClipboardItem({'image/png':png})]);copy.classList.add('copied');copy.setAttribute('aria-label','Скопировано');setTimeout(()=>{copy.classList.remove('copied');copy.setAttribute('aria-label','Скопировать картинку');},1200);
  }catch(e){notify(e.message||'Не удалось скопировать картинку.');}
 });
 active={close};
}
