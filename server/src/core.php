<?php
declare(strict_types=1);

require_once __DIR__.'/database.php';
function uuid(): string { $b=random_bytes(16);$b[6]=chr((ord($b[6])&15)|64);$b[8]=chr((ord($b[8])&63)|128);$h=bin2hex($b);return substr($h,0,8).'-'.substr($h,8,4).'-'.substr($h,12,4).'-'.substr($h,16,4).'-'.substr($h,20); }
function nowISO(): string { return gmdate('Y-m-d\TH:i:s\Z'); }
function zone(): DateTimeZone { return new DateTimeZone(config()['timezone'] ?? 'Europe/Moscow'); }
function day(?string $iso=null): string { return (new DateTimeImmutable($iso ?? 'now'))->setTimezone(zone())->format('Y-m-d'); }
function epoch(): string { return (string)db()->query("SELECT value FROM meta WHERE key='epoch'")->fetchColumn(); }
function revision(): int { return (int)db()->query("SELECT value FROM meta WHERE key='rev'")->fetchColumn(); }
function record(string $kind,string $id): ?array {
    $q=db()->prepare('SELECT * FROM records WHERE kind=? AND id=?');$q->execute([$kind,strtolower($id)]);$r=$q->fetch();
    return $r ? ['kind'=>$r['kind'],'id'=>$r['id'],'version'=>(int)$r['version'],'deleted'=>(bool)$r['deleted'],'value'=>$r['json']===null?null:json_decode($r['json'],true,512,JSON_THROW_ON_ERROR)] : null;
}
function snapshot(): array {
    $rows=db()->query('SELECT kind,id FROM records ORDER BY version')->fetchAll();
    return ['epoch'=>epoch(),'revision'=>revision(),'records'=>array_map(fn($r)=>record($r['kind'],$r['id']),$rows)];
}
function writeRecord(string $kind,string $id,?array $value): array {
    $id=strtolower($id);$existing=record($kind,$id);
    // Older Mac builds do not decode this field. Omission must not erase attachments.
    // New clients delete explicitly using images: [].
    if ($kind==='task' && $value!==null && !isset($value['images']) && isset($existing['value']['images'])) $value['images']=$existing['value']['images'];
    if ($existing && $existing['value']==$value && $existing['deleted']===($value===null)) return $existing;
    validateRecord($kind,$id,$value);
    $rev=revision()+1;
    db()->prepare("UPDATE meta SET value=? WHERE key='rev'")->execute([(string)$rev]);
    db()->prepare('INSERT INTO records(kind,id,version,deleted,json) VALUES(?,?,?,?,?) ON CONFLICT(kind,id) DO UPDATE SET version=excluded.version,deleted=excluded.deleted,json=excluded.json')->execute([$kind,$id,$rev,$value===null?1:0,$value===null?null:json_encode($value,JSON_UNESCAPED_UNICODE|JSON_THROW_ON_ERROR)]);
    return record($kind,$id);
}
function validID(string $id): bool { return preg_match('/^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/i',$id)===1; }
function validateRecord(string $kind,string $id,?array $value): void {
    if (!in_array($kind,['task','list','settings'],true)||!validID($id)) throw new InvalidArgumentException('Invalid record');
    if ($value===null) return;
    if ($kind==='settings') {
        if (isset($value['pinnedTaskID'])&&!validID($value['pinnedTaskID'])) throw new InvalidArgumentException('Invalid pin');
        return;
    }
    if (strtolower($value['id']??'')!==strtolower($id)) throw new InvalidArgumentException('ID mismatch');
    $key=$kind==='task'?'title':'name';
    if (!is_string($value[$key]??null)||trim($value[$key])===''||mb_strlen($value[$key])>2000) throw new InvalidArgumentException('Invalid title');
    if ($kind==='task') {
        if (!in_array($value['bucket']??'', ['later','week','today','done'],true)) throw new InvalidArgumentException('Invalid bucket');
        foreach (['createdAt','updatedAt','plannedAt'] as $field) if (!isset($value[$field])||!is_string($value[$field])||strtotime($value[$field])===false) throw new InvalidArgumentException('Invalid timestamp');
        foreach (['dueDate','reminder','completedAt'] as $field) if (isset($value[$field])&&(!is_string($value[$field])||strtotime($value[$field])===false)) throw new InvalidArgumentException('Invalid date');
        if (!is_numeric($value['order']??null)||!is_string($value['note']??null)||strlen($value['note'])>200000) throw new InvalidArgumentException('Invalid content');
        if (isset($value['listID'])&&!validID($value['listID'])) throw new InvalidArgumentException('Invalid list');
        if (isset($value['images'])) {
            if (!is_array($value['images']) || !array_is_list($value['images']) || count($value['images']) > 8) throw new InvalidArgumentException('Invalid images');
            $total=0; $ids=[];
            foreach ($value['images'] as $image) {
                if (!is_array($image) || !validID($image['id']??'') || isset($ids[strtolower($image['id'])]) || !is_string($image['dataURL']??null)) throw new InvalidArgumentException('Invalid image');
                $ids[strtolower($image['id'])]=true; $url=$image['dataURL']; $total+=strlen($url);
                if ($total>1500000 || !preg_match('~^data:image/(jpeg|png);base64,([A-Za-z0-9+/]+={0,2})$~D',$url,$m)) throw new InvalidArgumentException('Invalid image data');
                $bytes=base64_decode($m[2],true); $size=$bytes===false?false:@getimagesizefromstring($bytes);
                if (!$size || $size[0]>4096 || $size[1]>4096 || $size['mime']!=='image/'.$m[1]) throw new InvalidArgumentException('Invalid raster image');
            }
        }
        if (isset($value['noteData'])&&(!is_string($value['noteData'])||strlen($value['noteData'])>6000000)) throw new InvalidArgumentException('Attachment too large');
    } else {
        if (!preg_match('/^#[a-f0-9]{6}$/i',$value['color']??'')) throw new InvalidArgumentException('Invalid color');
        if (isset($value['icon'])&&(!is_string($value['icon'])||strlen($value['icon'])>100)) throw new InvalidArgumentException('Invalid icon');
    }
}
function alive(string $kind): array { return array_values(array_filter(array_map(fn($r)=>$r['value'],array_filter(snapshot()['records'],fn($r)=>$r['kind']===$kind&&!$r['deleted'])))); }
function task(string $id): ?array { $r=record('task',$id);return $r&&!$r['deleted']?$r['value']:null; }
function moveTask(array $t,string $bucket): array {
    if ($bucket==='done') {if ($t['bucket']!=='done') $t['previousBucket']=$t['bucket'];$t['completedAt']=nowISO();}
    else unset($t['completedAt']);
    $t['bucket']=$bucket;$t['updatedAt']=nowISO();$t['plannedAt']=nowISO();return $t;
}
function scheduled(?string $date): string {
    if (!$date) return 'later';$now=new DateTimeImmutable('now',zone());$d=(new DateTimeImmutable($date))->setTimezone(zone());
    return $d->format('Y-m-d')===$now->format('Y-m-d')?'today':($d->format('o-W')===$now->format('o-W')?'week':'later');
}
// Compatibility hook: deadlines and calendar changes never move existing tasks.
function reconcile(): void {}

function syncChanges(array $body): array {
    if (isset($body['epoch'])&&$body['epoch']!==epoch()) throw new DomainException('Server identity changed');
    $ops=$body['operations']??[];
    if(!is_array($ops)||count($ops)>5000)throw new InvalidArgumentException('Invalid operations');
    foreach($ops as $op) {if(!is_array($op)||!is_int($op['baseVersion']??null))throw new InvalidArgumentException('Invalid version');validateRecord($op['kind']??'', $op['id']??'',($op['deleted']??false)?null:($op['value']??null));}
    beginWrite();
    try {
        reconcile();$conflicts=[];
        foreach($ops as $op) {
            $kind=$op['kind'];$id=strtolower($op['id']);$current=record($kind,$id);$value=($op['deleted']??false)?null:($op['value']??null);
            if($current && $current['value']==$value)continue;
            if(($current['version']??0)!==$op['baseVersion']) {
                $conflicts[]=$kind.'/'.$id;
                db()->prepare('INSERT INTO conflicts(kind,record_id,payload,created_at) VALUES(?,?,?,?)')->execute([$kind,$id,json_encode($op,JSON_UNESCAPED_UNICODE),nowISO()]);continue;
            }
            writeRecord($kind,$id,$value);
        }
        $result=(!$ops&&($body['revision']??-1)===revision())?['epoch'=>epoch(),'revision'=>revision(),'records'=>[],'unchanged'=>true]:snapshot();$result['conflicts']=$conflicts;db()->exec('COMMIT');return $result;
    } catch(Throwable $e){db()->exec('ROLLBACK');throw $e;}
}
function session(?array $data=null): ?array {
    $id=(string)config()['owner_id'];
    if($data!==null){db()->prepare('INSERT INTO sessions VALUES(?,?,?) ON CONFLICT(user_id) DO UPDATE SET json=excluded.json,expires=excluded.expires')->execute([$id,json_encode($data),time()+900]);return $data;}
    $q=db()->prepare('SELECT json FROM sessions WHERE user_id=? AND expires>?');$q->execute([$id,time()]);$v=$q->fetchColumn();return $v?json_decode($v,true):null;
}
function clearSession(): void { db()->prepare('DELETE FROM sessions WHERE user_id=?')->execute([(string)config()['owner_id']]); }
function queueTelegram(string $method,array $payload,?string $key=null): void {db()->prepare('INSERT INTO outbox(unique_key,method,json) VALUES(?,?,?) ON CONFLICT(unique_key) DO NOTHING')->execute([$key,$method,json_encode($payload,JSON_UNESCAPED_UNICODE|JSON_THROW_ON_ERROR)]);}
function telegram(string $method,array $payload): array {
    $ch=curl_init('https://api.telegram.org/bot'.config()['bot_token'].'/'.$method);
    curl_setopt_array($ch,[CURLOPT_POST=>true,CURLOPT_POSTFIELDS=>json_encode($payload),CURLOPT_HTTPHEADER=>['Content-Type: application/json'],CURLOPT_RETURNTRANSFER=>true,CURLOPT_CONNECTTIMEOUT=>5,CURLOPT_TIMEOUT=>max(12,(int)($payload['timeout']??0)+8)]);
    // Optional verified Telegram endpoint when the hosting network cannot reach its default DC.
    if(!empty(config()['telegram_api_ip']))curl_setopt($ch,CURLOPT_RESOLVE,['api.telegram.org:443:'.config()['telegram_api_ip']]);
    $raw=curl_exec($ch);$status=curl_getinfo($ch,CURLINFO_RESPONSE_CODE);curl_close($ch);
    $response=is_string($raw)?json_decode($raw,true):null;
    return is_array($response)?$response:['ok'=>false,'error_code'=>$status?:503,'description'=>'Telegram unavailable'];
}
/** Bind visible numbers only after Telegram acknowledges delivery. */
function deliveredBotView(array $outbox,array $response): void {
    if(!($response['ok']??false)||!preg_match('/^today-view:([^:]+):/', $outbox['unique_key']??'', $m))return;
    $q=db()->prepare('SELECT value FROM meta WHERE key=?');$q->execute(['bot_view:'.$m[1]]);$view=$q->fetchColumn();if(!$view)return;
    $q=db()->prepare('INSERT INTO meta VALUES(?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value');
    $q->execute(['bot_current_view',$view]);
    if(isset($response['result']['message_id']))$q->execute(['bot_message:'.$response['result']['message_id'],$view]);
}
function flushOutbox(int $limit=6): void {
    // Serialize deliveries across webhook and sync requests without holding a DB transaction over HTTP.
    $lock=lockOutbox();if($lock===false)return;
    try {$deadline=microtime(true)+40;foreach(db()->query('SELECT * FROM outbox WHERE sent=0 AND next_attempt<='.time().' ORDER BY id LIMIT '.max(1,min(20,$limit)))->fetchAll() as $r){
        $result=telegram($r['method'],json_decode($r['json'],true));$ok=$result['ok']??false;
        deliveredBotView($r,$result);
        $permanent=($result['error_code']??0)===403||(($result['error_code']??0)===400);
        db()->prepare('UPDATE outbox SET sent=?,attempts=attempts+1,next_attempt=? WHERE id=?')->execute([$ok||$permanent?1:0,time()+min(3600,30*(2**min(6,(int)$r['attempts']))),$r['id']]);
        if((!$ok&&!$permanent)||microtime(true)>$deadline)break;
    }}catch(Throwable $e){unlockOutbox($lock,false);throw $e;}
    unlockOutbox($lock,true);
}
function reminders(): void {
    beginWrite();
    try {reconcile();foreach(alive('task') as $t){
        if($t['bucket']==='done'||empty($t['reminder'])||strtotime($t['reminder'])>time())continue;
        $q=db()->prepare('INSERT INTO reminders VALUES(?,?) ON CONFLICT(task_id,at) DO NOTHING');$q->execute([$t['id'],$t['reminder']]);if(!$q->rowCount())continue;
        queueTelegram('sendMessage',['chat_id'=>config()['owner_id'],'text'=>'⏰ '.$t['title'],'reply_markup'=>['inline_keyboard'=>[[['text'=>'Открыть задачи','web_app'=>['url'=>config()['mini_app_url']]]]]]],'reminder:'.$t['id'].':'.$t['reminder']);
    }db()->exec('COMMIT');}catch(Throwable $e){db()->exec('ROLLBACK');throw $e;}
}
