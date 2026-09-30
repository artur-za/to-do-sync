<?php
declare(strict_types=1);
const SETTINGS_ID='00000000-0000-0000-0000-000000000001';
function miniURL(): string {return config()['mini_app_url'];}
function shortText(string $text,int $n=1000): string {return mb_strlen($text)>$n?mb_substr($text,0,$n-1).'…':$text;}
function botMeta(string $key,?string $value=null): ?string {
    if($value!==null){db()->prepare('INSERT INTO meta VALUES(?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value')->execute([$key,$value]);return $value;}
    $q=db()->prepare('SELECT value FROM meta WHERE key=?');$q->execute([$key]);$v=$q->fetchColumn();return $v===false?null:$v;
}
function openMiniApp(): void {queueTelegram('sendMessage',['chat_id'=>config()['owner_id'],'text'=>'Редактирование задач — в Mini App.','reply_markup'=>['inline_keyboard'=>[[['text'=>'Открыть задачи','web_app'=>['url'=>miniURL()]]]]]]);}
/** Numbers exist only in these delivered Telegram list snapshots, never in task titles. */
function todayList(string $prefix=''): void {
    $tasks=array_values(array_filter(alive('task'),fn($t)=>$t['bucket']==='today'));
    usort($tasks,fn($a,$b)=>($a['order']<=>$b['order'])?:strcmp($a['id'],$b['id']));
    $view=['day'=>day(),'ids'=>array_column($tasks,'id')];$viewID=uuid();
    botMeta('bot_view:'.$viewID,json_encode($view));
    $html=fn(string $value): string=>htmlspecialchars($value,ENT_QUOTES|ENT_SUBSTITUTE,'UTF-8');
    $header=($prefix!==''?$html($prefix)."\n\n":'').'Сегодня · '.count($tasks)."\n";
    $parts=[];$text=$header;
    $lists=array_column(alive('list'),null,'id');
    $formatDate=function(string $iso,bool $withTime=false): string {
        $date=(new DateTimeImmutable($iso))->setTimezone(zone());
        $format=$date->format('Y')===(new DateTimeImmutable('now',zone()))->format('Y')?'d.m':'d.m.Y';
        return $date->format($format.($withTime?' H:i':''));
    };
    foreach($tasks as $i=>$t){
        $line="\n<code>#".($i+1).'</code> '.$html(shortText(preg_replace('/\s+/u',' ',$t['title']),900));
        $meta=[];$list=$lists[$t['listID']??'']??null;
        if($list){$name=preg_replace('/\s+/u',' ',trim($list['name']));$tag=preg_match('/^[\p{L}\p{N}_-]+$/u',$name)?'#'.$name:'#['.$name.']';$meta[]='<code>'.$html($tag).'</code>';}
        if(!empty($t['dueDate']))$meta[]='<code>'.$formatDate($t['dueDate']).'</code>';
        if(!empty($t['reminder']))$meta[]='⏰ <code>'.$formatDate($t['reminder'],true).'</code>';
        if($meta)$line.=' '.implode(' ',$meta);
        if(mb_strlen($text.$line)>3600){$parts[]=$text;$text='Сегодня · продолжение';}$text.=$line;
    }
    if(!$tasks)$text.="\nНа сегодня задач нет.";
    $parts[]=$text;
    foreach($parts as $i=>$part)queueTelegram('sendMessage',['chat_id'=>config()['owner_id'],'text'=>$part,'parse_mode'=>'HTML','reply_markup'=>['remove_keyboard'=>true]],'today-view:'.$viewID.':'.$i);
}
function parseTaskText(string $text,?DateTimeImmutable $clock=null): array {
    $clock??=new DateTimeImmutable('now',zone());$text=str_replace(["\r\n","\r"],"\n",trim($text));
    $parts=preg_split('/\n[\t ]*\n/u',$text,2);$title=$parts[0];$note=$parts[1]??'';$bucket=null;$due=null;$group=null;
    $aliases=['today'=>'today','сегодня'=>'today','week'=>'week','неделя'=>'week','later'=>'later','позже'=>'later'];
    $title=preg_replace_callback('/(?<!\S)#(?:\[([^\]\r\n]+)\]|([\p{L}\p{N}_-]+))/u',function($m)use(&$bucket,&$due,&$group,$aliases,$clock){
        $tag=trim($m[1]!==''?$m[1]:($m[2]??''));$lower=mb_strtolower($tag);
        if(isset($aliases[$lower])){if($bucket!==null&&$bucket!==$aliases[$lower])throw new InvalidArgumentException('Укажи одну колонку: #today, #week или #later.');$bucket=$aliases[$lower];}
        elseif(ctype_digit($tag)){$n=(int)$tag;if($n<1||$n>(int)$clock->format('t'))throw new InvalidArgumentException('Такого дня в текущем месяце нет. Например: задача #'.min(25,(int)$clock->format('t')).'.');$date=$clock->setDate((int)$clock->format('Y'),(int)$clock->format('m'),$n)->setTime(12,0);if($due!==null&&$due!==$date->format('Y-m-d\TH:i:sP'))throw new InvalidArgumentException('Укажи один дедлайн.');$due=$date->format('Y-m-d\TH:i:sP');}
        else {if($group!==null&&mb_strtolower($group)!==$lower)throw new InvalidArgumentException('У задачи может быть один список. Для имени с пробелами: #[Название группы].');$group=$tag;}
        return '';
    },$title);
    $title=trim(preg_replace('/\s+/u',' ',$title));if($title==='')throw new InvalidArgumentException('Добавь название задачи рядом с хештегами. Только #номер завершает задачу из последнего списка Today.');
    if(mb_strlen($title)>2000||strlen($note)>200000)throw new InvalidArgumentException('Текст слишком длинный. Сократи название или заметку.');
    // Explicit column wins. A date alone chooses Today/Week/Later; other input defaults to Week.
    if($bucket===null){$bucket='week';if($due){$d=new DateTimeImmutable($due);$bucket=$d->format('Y-m-d')===$clock->format('Y-m-d')?'today':($d->format('o-W')===$clock->format('o-W')?'week':'later');}}
    return ['title'=>$title,'note'=>$note,'bucket'=>$bucket,'dueDate'=>$due,'group'=>$group];
}
function completeNumber(int $number,?int $replyTo=null): void {
    $raw=$replyTo?botMeta('bot_message:'.$replyTo):botMeta('bot_current_view');$view=$raw?json_decode($raw,true):null;
    if(!$view||($view['day']??'')!==day()){todayList('Список обновился. Используй номер из этого сообщения.');return;}
    $id=$view['ids'][$number-1]??null;$t=$id?task($id):null;
    if(!$t||$t['bucket']!=='today'){todayList('Этой задачи уже нет в Today. Ничего не изменено.');return;}
    writeRecord('task',$id,moveTask($t,'done'));
    if((record('settings',SETTINGS_ID)['value']['pinnedTaskID']??null)===$id)writeRecord('settings',SETTINGS_ID,['pinnedTaskID'=>null]);
    todayList('✅ Выполнено: '.shortText($t['title'],350));
}
function handleText(array $event): void {
    $text=trim($event['text']);if($text==='')return;
    if(preg_match('/^#([0-9]+)$/D',$text,$m)){completeNumber((int)$m[1],isset($event['reply_to_message']['message_id'])?(int)$event['reply_to_message']['message_id']:null);return;}
    $command=mb_strtolower(explode('@',explode(' ',$text,2)[0],2)[0]);
    if(in_array($command,['/start','/today'])){todayList();return;}
    if($command==='/app'){openMiniApp();return;}
    if($command==='/help'){todayList("Текст → новая задача на неделю.\n#today / #сегодня · #week / #неделя · #later / #позже\n#ВШЭ или #[Название группы] → список (новый создастся).\n#25 рядом с текстом → дедлайн 25-го числа этого месяца.\nПустая строка отделяет название от заметки. Хештеги разбираются в названии.\nТолько #номер → выполнить задачу из последнего полученного списка. Можно ответить #номером на конкретный список.\nВсе правки — в Mini App.");return;}
    if(str_starts_with($text,'/')){todayList('Доступны /today и /app. Задачу можно просто написать сообщением.');return;}
    try{$parsed=parseTaskText($text);}catch(InvalidArgumentException $e){queueTelegram('sendMessage',['chat_id'=>config()['owner_id'],'text'=>$e->getMessage(),'reply_markup'=>['remove_keyboard'=>true]]);return;}
    $listID=null;if($parsed['group']){foreach(alive('list') as $l)if(mb_strtolower($l['name'])===mb_strtolower($parsed['group'])){$listID=$l['id'];break;}if(!$listID){$listID=uuid();writeRecord('list',$listID,['id'=>$listID,'name'=>$parsed['group'],'color'=>'#378DFF']);}}
    $id=uuid();$at=nowISO();$orders=array_column(alive('task'),'order');
    $t=['id'=>$id,'title'=>$parsed['title'],'note'=>$parsed['note'],'bucket'=>$parsed['bucket'],'createdAt'=>$at,'updatedAt'=>$at,'plannedAt'=>$at,'order'=>($orders?min($orders):0)-1];
    if($listID)$t['listID']=$listID;if($parsed['dueDate'])$t['dueDate']=(new DateTimeImmutable($parsed['dueDate']))->setTimezone(new DateTimeZone('UTC'))->format('Y-m-d\TH:i:s\Z');
    writeRecord('task',$id,$t);$labels=['week'=>'This week','today'=>'Today','later'=>'Later'];todayList('Добавлено в '.$labels[$t['bucket']].': '.shortText($t['title'],350));
}
function processUpdate(array $update): bool {
    $event=$update['callback_query']??$update['message']??null;$chat=isset($update['callback_query'])?($event['message']['chat']??null):($event['chat']??null);
    if(!$event||($chat['type']??'')!=='private'||(string)($event['from']['id']??'')!==(string)config()['owner_id']||(string)($chat['id']??'')!==(string)config()['owner_id'])return false;
    if(!is_int($update['update_id']??null))return false;
    beginWrite();try{
        $q=db()->prepare('INSERT INTO updates VALUES(?,?) ON CONFLICT(id) DO NOTHING');$q->execute([$update['update_id'],time()]);if(!$q->rowCount()){db()->exec('COMMIT');return true;}
        reconcile();clearSession();
        if(isset($update['callback_query'])){queueTelegram('answerCallbackQuery',['callback_query_id'=>$event['id'],'text'=>'Все изменения — в Mini App']);openMiniApp();}
        elseif(isset($event['text']))handleText($event);
        else queueTelegram('sendMessage',['chat_id'=>config()['owner_id'],'text'=>'Напиши задачу текстом. Редактирование — в Mini App.','reply_markup'=>['remove_keyboard'=>true]]);
        db()->exec('COMMIT');return true;
    }catch(Throwable $e){db()->exec('ROLLBACK');throw $e;}
}

/** Queue once per Moscow day. A delayed worker catches up after 09:00. */
function dailyToday(?DateTimeImmutable $clock=null): void {
    $clock=($clock??new DateTimeImmutable('now'))->setTimezone(new DateTimeZone('Europe/Moscow'));
    if((int)$clock->format('H')<9)return;
    $date=$clock->format('Y-m-d');beginWrite();
    try {if(botMeta('daily_today_date')!==$date){reconcile();todayList();botMeta('daily_today_date',$date);}db()->exec('COMMIT');}
    catch(Throwable $e){db()->exec('ROLLBACK');throw $e;}
}
