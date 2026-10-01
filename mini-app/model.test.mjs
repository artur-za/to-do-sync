import assert from 'node:assert/strict';
import {blankState,merge,operations,move,scheduled,insertionOrder,placeTask} from './model.mjs';
const task={id:'a',title:'Original',note:'Note',bucket:'later',order:1};
const remote=(v,version=1,deleted=false)=>({epoch:'one',revision:version,records:[{kind:'task',id:'a',value:v,version,deleted}]});
let s=merge(blankState(),remote(task));assert.deepEqual(s.local['task/a'],task);assert.equal(operations(s).length,0);
s.local['task/a'].title='Mac';s=merge(s,remote({...task,note:'Telegram'},2));assert.equal(s.local['task/a'].title,'Mac');assert.equal(s.local['task/a'].note,'Telegram');assert.equal(s.conflicts.length,0);assert.equal(operations(s)[0].baseVersion,2);
s=merge(s,remote({...task,note:'Telegram',title:'Other'},3));assert.equal(s.conflicts.length,1);assert.equal(s.local['task/a'].title,'Mac');
s=merge(s,remote(null,4,true));assert.equal(s.local['task/a'],undefined);assert.equal(s.conflicts.length,2);assert.equal(operations(s).length,0);
assert.throws(()=>merge(s,{epoch:'reset',records:[]}));
s=merge(blankState(),remote({...task,noteData:'rich'}));s.local['task/a'].title='Mine';s=merge(s,remote({...task,note:'Plain'},2));assert.equal(s.local['task/a'].noteData,undefined);
s=merge(blankState(),remote(task));delete s.local['task/a'];assert.equal(operations(s)[0].deleted,true);assert.equal(operations(s)[0].baseVersion,1);
const completed=move(task,'done');assert.equal(completed.previousBucket,'later');assert.ok(completed.completedAt);assert.equal(move(completed,'today').completedAt,undefined);
assert.equal(scheduled(null),'later');assert.equal(insertionOrder([{id:'a',order:1},{id:'b',order:3}],'b'),2);assert.equal(insertionOrder([{id:'a',order:1}],'a'),0);
console.log('PASS: Mini App merge, CAS, conflict archive, deletion, rich notes, completion and ordering');

const clock='2026-10-01T09:00:00Z';
for(const bucket of ['today','week','later','done']){
 for(const dueDate of [undefined,clock,'2027-01-01T12:00:00Z']){
  const original={...task,bucket,dueDate,plannedAt:'2026-09-01T09:00:00Z'};
  if(dueDate===undefined)delete original.dueDate;
  assert.deepEqual(placeTask(original,false,null,clock),original);
 }
}
assert.equal(placeTask({...task,dueDate:clock},true,null,clock).bucket,'today');
assert.equal(placeTask(task,true,null,clock).bucket,'later');
assert.equal(placeTask({...task,bucket:'today',dueDate:clock},false,'week',clock).bucket,'week');
console.log('PASS: existing columns survive deadline edits; creation and explicit moves still place tasks');
