/** One recognizer for touch and mouse. Touch uses cancelable TouchEvents in mobile WebViews. */
export function installBoardGestures(root, hooks, clock={now:()=>performance.now(),set:(fn,delay)=>setTimeout(fn,delay),clear:timer=>clearTimeout(timer)}) {
 let gesture=null;
 const stopTimer=()=>{if(gesture?.timer){clock.clear(gesture.timer);gesture.timer=null;}};
 function finish(cancel=false){
  if(!gesture)return;const g=gesture;stopTimer();gesture=null;
  if(g.mode==='drag')hooks.dragEnd(!cancel);
  else if(g.mode==='horizontal')hooks.swipeEnd({dx:g.dx,elapsed:clock.now()-g.at,cancel});
  hooks.pending(false);
 }
 function begin(e,point,source){
  if(gesture)finish(true);
  const context=hooks.context(),target=e.target;
  if(!context.enabled||!target?.closest?.('.tasks')||target.closest('button,input,textarea,select,a'))return;
  gesture={source,id:point.identifier??e.pointerId,x:point.clientX,y:point.clientY,dx:0,at:clock.now(),mode:'pending',row:target.closest('.row'),compact:context.compact,timer:null};
  hooks.pending(true);
  if(gesture.compact&&gesture.row)gesture.timer=clock.set(()=>{
   if(!gesture||gesture.mode!=='pending')return;
   gesture.mode='drag';hooks.dragStart(gesture);
  },350);
 }
 function move(e,point){
  if(!gesture)return;const g=gesture,dx=point.clientX-g.x,dy=point.clientY-g.y;
  if(g.mode==='pending'){
   if(Math.hypot(dx,dy)<10)return;stopTimer();
   if(Math.abs(dx)>Math.abs(dy)*1.15)g.mode='horizontal';
   else if(Math.abs(dy)>Math.abs(dx)*1.15){
    // Mouse can drag a compact row immediately; finger scrolls unless it was held first.
    if(g.source==='mouse'&&g.compact&&g.row){g.mode='drag';hooks.dragStart(g);}
    else {finish(true);return;}
   }else return;
  }
  if(e.cancelable)e.preventDefault();
  if(g.mode==='drag')hooks.dragMove(point);
  else if(g.mode==='horizontal'){g.dx=dx;hooks.swipeMove(dx);}
 }
 const handlers={
  touchstart:e=>{if(e.touches.length!==1){finish(true);return;}begin(e,e.touches[0],'touch');},
  touchmove:e=>{if(gesture?.source!=='touch')return;if(e.touches.length!==1){finish(true);return;}const p=[...e.touches].find(t=>t.identifier===gesture.id);if(p)move(e,p);},
  touchend:e=>{if(gesture?.source==='touch'&&[...e.changedTouches].some(t=>t.identifier===gesture.id))finish();},
  touchcancel:()=>{if(gesture?.source==='touch')finish(true);},
  pointerdown:e=>{if(e.pointerType==='touch'||e.button!==0||e.isPrimary===false)return;begin(e,e,'mouse');},
  pointermove:e=>{if(gesture?.source==='mouse'&&e.pointerId===gesture.id)move(e,e);},
  pointerup:e=>{if(gesture?.source==='mouse'&&e.pointerId===gesture.id)finish();},
  pointercancel:e=>{if(gesture?.source==='mouse'&&e.pointerId===gesture.id)finish(true);},
  keydown:e=>{if(e.key==='Escape')finish(true);},
  visibilitychange:()=>{if(root.hidden)finish(true);}
 };
 for(const [type,fn] of Object.entries(handlers))root.addEventListener(type,fn,{passive:type!=='touchmove'&&type!=='pointermove'});
 return ()=>{finish(true);for(const [type,fn] of Object.entries(handlers))root.removeEventListener(type,fn);};
}
