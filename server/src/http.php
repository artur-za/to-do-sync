<?php
declare(strict_types=1);
if(!function_exists('config')) {function config(): array {static $c;return $c??=require __DIR__.'/../config.php';}}
require __DIR__.'/core.php';require __DIR__.'/bot.php';require __DIR__.'/mini-auth.php';
header('Content-Type: application/json; charset=utf-8');header('Cache-Control: no-store');header('X-Content-Type-Options: nosniff');header('X-Robots-Tag: noindex, nofollow');
function jsonReply(array $data,int $status=200): never {http_response_code($status);echo json_encode($data,JSON_UNESCAPED_UNICODE|JSON_THROW_ON_ERROR);exit;}
function bearerOK(string $value): bool {return hash_equals('Bearer '.config()['sync_token'],$value);}
$route=$_GET['route']??'health';
try {
    if($route==='health')jsonReply(['ok'=>true,'service'=>'flodo-open','version'=>1]);
    if($route==='webhook'){
        if($_SERVER['REQUEST_METHOD']!=='POST'||!hash_equals(config()['webhook_secret'],$_SERVER['HTTP_X_TELEGRAM_BOT_API_SECRET_TOKEN']??''))jsonReply(['error'=>'unauthorized'],401);
        $raw=file_get_contents('php://input',false,null,0,1048577);if(strlen($raw)>1048576)jsonReply(['error'=>'too_large'],413);
        $update=json_decode($raw,true,64,JSON_THROW_ON_ERROR);if(!is_array($update))jsonReply(['error'=>'invalid_update'],400);
        processUpdate($update);flushOutbox();jsonReply(['ok'=>true]);
    }
    if($route==='mini-sync'){
        if($_SERVER['REQUEST_METHOD']!=='POST')jsonReply(['error'=>'method'],405);
        if(!($miniUser=miniAppUser($_SERVER['HTTP_X_TELEGRAM_INIT_DATA']??'',config()['bot_token'],(string)config()['owner_id'])))jsonReply(['error'=>'telegram_auth_required'],401);
        $raw=file_get_contents('php://input',false,null,0,16000001);if(strlen($raw)>16000000)jsonReply(['error'=>'too_large'],413);
        $body=json_decode($raw,true,64,JSON_THROW_ON_ERROR);if(!is_array($body))jsonReply(['error'=>'invalid_body'],400);
        $result=syncChanges($body);$result['owner']=(string)$miniUser['id'];jsonReply($result);
    }
    if(!bearerOK($_SERVER['HTTP_AUTHORIZATION']??$_SERVER['REDIRECT_HTTP_AUTHORIZATION']??''))jsonReply(['error'=>'unauthorized'],401);
    if($route==='sync'){
        if($_SERVER['REQUEST_METHOD']!=='POST')jsonReply(['error'=>'method'],405);
        $raw=file_get_contents('php://input',false,null,0,16000001);if(strlen($raw)>16000000)jsonReply(['error'=>'too_large'],413);
        $body=json_decode($raw,true,64,JSON_THROW_ON_ERROR);if(!is_array($body))jsonReply(['error'=>'invalid_body'],400);
        $result=syncChanges($body);
        db()->prepare("INSERT INTO meta VALUES('last_mac_sync',?) ON CONFLICT(key) DO UPDATE SET value=excluded.value")->execute([nowISO()]);
        // An open Mac provides a fallback reminder tick; worker.php handles offline delivery via cron.
        reminders();flushOutbox(3);jsonReply($result);
    }
    if($route==='conflicts'){
        $rows=db()->query("SELECT * FROM conflicts WHERE kind<>'undo-task' ORDER BY id DESC LIMIT 100")->fetchAll();jsonReply(['conflicts'=>$rows]);
    }
    jsonReply(['error'=>'not_found'],404);
} catch(InvalidArgumentException|JsonException $e){jsonReply(['error'=>'invalid_request'],400);}
catch(DomainException $e){jsonReply(['error'=>'server_identity_changed'],409);}
catch(Throwable $e){error_log('Flodo request failed: '.get_class($e));jsonReply(['error'=>'server_error'],500);}
