<?php
declare(strict_types=1);
if(PHP_SAPI!=='cli'){http_response_code(404);exit;}
function config(): array {static $c;return $c??=require __DIR__.'/../config.php';}
require __DIR__.'/core.php';require __DIR__.'/bot.php';
try {
    db();$lock=fopen(config()['data_dir'].'/worker.lock','c');
    if(!$lock||!flock($lock,LOCK_EX|LOCK_NB))exit;
    $deadline=microtime(true)+55;
    do {
        reminders();dailyToday();flushOutbox(20);
        db()->prepare("INSERT INTO meta VALUES('last_worker',?) ON CONFLICT(key) DO UPDATE SET value=excluded.value")->execute([nowISO()]);
        if((config()['transport']??'webhook')!=='polling')break;
        $remaining=(int)floor($deadline-microtime(true));if($remaining<1)break;
        $offset=(int)db()->query("SELECT value FROM meta WHERE key='telegram_offset'")->fetchColumn();
        $result=telegram('getUpdates',['offset'=>$offset,'timeout'=>min(10,$remaining),'limit'=>50,'allowed_updates'=>['message','callback_query']]);
        if(!($result['ok']??false)){
            db()->prepare("INSERT INTO meta VALUES('last_poll_error',?) ON CONFLICT(key) DO UPDATE SET value=excluded.value")->execute([json_encode(['at'=>nowISO(),'code'=>$result['error_code']??0,'message'=>$result['description']??'Unavailable'])]);
            sleep(2);continue;
        }
        foreach($result['result'] as $update){
            processUpdate($update);
            // Advance only after the update and its reply have been committed.
            db()->prepare("INSERT INTO meta VALUES('telegram_offset',?) ON CONFLICT(key) DO UPDATE SET value=excluded.value")->execute([(string)($update['update_id']+1)]);
        }
        db()->prepare("INSERT INTO meta VALUES('last_poll',?) ON CONFLICT(key) DO UPDATE SET value=excluded.value")->execute([nowISO()]);
        flushOutbox(20);
    } while(microtime(true)<$deadline);
    flock($lock,LOCK_UN);fclose($lock);
} catch(Throwable $e){fwrite(STDERR,"Flodo worker failed: ".get_class($e)."\n");exit(1);}
