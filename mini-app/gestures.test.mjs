import assert from 'node:assert/strict';
import {installBoardGestures} from './gestures.mjs';
function harness({compact=false,row=true,button=false,enabled=true}={}){
 const listeners={},calls=[],timers=new Map();let now=0,seq=0;
 const root={addEventListener:(n,f)=>listeners[n]=f,removeEventListener:n=>delete listeners[n]};
 const target={closest:s=>s==='.tasks'?{}:s==='.row'?(row?{}:null):(button?{}:null)};
 const hooks={context:()=>({compact,enabled}),pending:v=>calls.push(['pending',v]),swipeMove:dx=>calls.push(['swipe',dx]),swipeEnd:v=>calls.push(['swipeEnd',v]),dragStart:()=>calls.push(['dragStart']),dragMove:()=>calls.push(['dragMove']),dragEnd:v=>calls.push(['dragEnd',v])};
 const dispose=installBoardGestures(root,hooks,{now:()=>now,set:(fn)=>{timers.set(++seq,fn);return seq;},clear:id=>timers.delete(id)});
 function emit(type,x=100,y=100,extra={}){const p={identifier:1,clientX:x,clientY:y};const e={target,touches:[p],changedTouches:[p],pointerId:1,pointerType:'mouse',isPrimary:true,button:0,cancelable:true,prevented:false,preventDefault(){this.prevented=true;},...p,...extra};listeners[type]?.(e);return e;}
 return {calls,emit,dispose,tick:ms=>{now+=ms;if(ms>=350){const jobs=[...timers.values()];timers.clear();jobs.forEach(f=>f());}}};
}
// Mobile: pointercancel can be emitted by the WebView while TouchEvents still continue.
{
 const h=harness();h.emit('pointerdown',100,100,{pointerType:'touch'});h.emit('touchstart');assert.equal(h.calls.filter(c=>c[0]==='pending').length,1);
 assert(h.emit('touchmove',30,105).prevented);h.emit('pointercancel',30,105,{pointerType:'touch'});h.tick(100);h.emit('touchend',20,105);
 assert.equal(h.calls.find(c=>c[0]==='swipeEnd')[1].cancel,false);assert(!h.calls.some(c=>c[0]==='dragStart'));
}
// Compact mode still permits horizontal swipes; only holding unlocks dragging.
{
 const h=harness({compact:true});h.emit('touchstart');h.emit('touchmove',180,104);h.tick(400);h.emit('touchend',180,104);
 assert(h.calls.some(c=>c[0]==='swipeEnd'));assert(!h.calls.some(c=>c[0]==='dragStart'));
}
// Native vertical scrolling never gets preventDefault and cancels pending long press.
for(const compact of [false,true]){
 const h=harness({compact});h.emit('touchstart');assert(!h.emit('touchmove',103,150).prevented);h.tick(400);h.emit('touchend',103,150);assert(!h.calls.some(c=>['dragStart','swipe','swipeEnd'].includes(c[0])));
}
{
 const h=harness({compact:true});h.emit('touchstart');h.tick(350);assert(h.emit('touchmove',110,200).prevented);h.emit('touchend',110,200);assert.deepEqual(h.calls.filter(c=>c[0].startsWith('drag')).map(c=>c[0]),['dragStart','dragMove','dragEnd']);assert.equal(h.calls.find(c=>c[0]==='dragEnd')[1],true);
}
{
 const h=harness({compact:false});h.emit('touchstart');h.tick(400);h.emit('touchmove',200,100);h.emit('touchend',200,100);assert(!h.calls.some(c=>c[0]==='dragStart'));
}
// Blank space and empty columns are valid swipe areas.
{
 const h=harness({row:false});h.emit('touchstart');h.emit('touchmove',20,100);h.emit('touchend',20,100);assert(h.calls.some(c=>c[0]==='swipeEnd'));
}
// Cancel and two fingers never commit a swipe or move a task.
for(const cancel of ['touchcancel','multitouch']){
 const h=harness();h.emit('touchstart');h.emit('touchmove',200,100);if(cancel==='touchcancel')h.emit(cancel);else h.emit('touchmove',200,100,{touches:[{},{}]});assert.equal(h.calls.find(c=>c[0]==='swipeEnd')[1].cancel,true);
}
for(const options of [{button:true},{enabled:false}]){const h=harness(options);h.emit('touchstart');h.emit('touchmove',200,100);h.emit('touchend',200,100);assert.equal(h.calls.length,0);}
{
 const h=harness({compact:true});h.emit('pointerdown');h.emit('pointermove',100,170);h.emit('pointerup');assert(h.calls.some(c=>c[0]==='dragEnd'&&c[1]===true));h.dispose();
}
console.log('PASS: touch and mouse gestures, compact swipes, blank area, vertical scroll, long press, cancellation, controls and multitouch');
