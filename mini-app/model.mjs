export const SETTINGS='00000000-0000-0000-0000-000000000001';
export const key=r=>`${r.kind}/${r.id.toLowerCase()}`;
export const clone=v=>v==null?v:JSON.parse(JSON.stringify(v));
const canonical=v=>v===undefined?'undefined':v===null?'null':Array.isArray(v)?'['+v.map(canonical).join(',')+']':typeof v==='object'?'{'+Object.keys(v).sort().map(k=>JSON.stringify(k)+':'+canonical(v[k])).join(',')+'}':JSON.stringify(v);
export const equal=(a,b)=>canonical(a)===canonical(b);
export function operations(state){return [...new Set([...Object.keys(state.base),...Object.keys(state.local)])].sort().flatMap(k=>{const b=state.base[k],v=state.local[k];if(equal(v,b?.deleted?undefined:b?.value))return [];if(v===undefined&&!b)return [];const [kind,id]=k.split('/');return [{kind,id,baseVersion:b?.version||0,deleted:v===undefined,value:v??null}];});}
export function merge(state,remote){
 if(state.epoch&&state.epoch!==remote.epoch)throw Error('Сервер был заменён. Локальные изменения сохранены; проверьте резервную копию.');
 if(remote.unchanged)return state;
 const result=clone(state);result.epoch=remote.epoch;result.revision=remote.revision;result.conflicts??=[];
 for(const r of remote.records){const k=key(r),b=state.base[k]?.deleted?undefined:state.base[k]?.value,l=state.local[k],v=r.deleted?undefined:r.value;let chosen;
  if(equal(l,b))chosen=v;else if(equal(v,b)||equal(l,v))chosen=l;
  else if(l&&v){chosen={};const fields=[];for(const f of new Set([...Object.keys(b||{}),...Object.keys(l),...Object.keys(v)])){if(equal(l[f],b?.[f]))chosen[f]=v[f];else if(equal(v[f],b?.[f])||equal(l[f],v[f]))chosen[f]=l[f];else {chosen[f]=l[f];if(f!=='updatedAt')fields.push(f);}}
   if(chosen.note!==l.note)chosen.noteData=v.noteData;
   if(fields.length)result.conflicts.push({key:k,fields,base:b,local:l,remote:v,at:new Date().toISOString()});
  }else {chosen=undefined;result.conflicts.push({key:k,fields:['deletion'],base:b,local:l,remote:v,at:new Date().toISOString()});}
  if(chosen===undefined)delete result.local[k];else result.local[k]=clone(chosen);
  result.base[k]=clone(r);
 }
 return result;
}
export function blankState(){return {epoch:null,revision:-1,base:{},local:{},conflicts:[]};}
export function move(task,bucket,now=new Date().toISOString()){const t=clone(task);if(bucket==='done'){if(t.bucket!=='done')t.previousBucket=t.bucket;t.completedAt=now;}else delete t.completedAt;t.bucket=bucket;t.plannedAt=now;t.updatedAt=now;return t;}
export function scheduled(iso,now=new Date()){if(!iso)return 'later';const d=new Date(iso);if(d.toDateString()===now.toDateString())return 'today';const monday=x=>{const t=new Date(x);t.setHours(0,0,0,0);t.setDate(t.getDate()-(t.getDay()+6)%7);return +t;};return monday(d)===monday(now)?'week':'later';}
export function insertionOrder(rows,beforeID){const sorted=rows.toSorted((a,b)=>a.order-b.order);const at=beforeID?sorted.findIndex(t=>t.id===beforeID):-1;if(at===0)return sorted[0].order-1;if(at<0)return (sorted.at(-1)?.order??0)+1;return (sorted[at-1].order+sorted[at].order)/2;}

// Automatic placement only happens once; editing a deadline preserves the column.
export function placeTask(task,isNew,destination,at=new Date().toISOString()){
 let t=clone(task);
 if(isNew){t.bucket=scheduled(t.dueDate,new Date(at));t.plannedAt=at;}
 if(destination)t=move(t,destination,at);
 return t;
}
