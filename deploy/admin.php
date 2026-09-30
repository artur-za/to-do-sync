<?php
declare(strict_types=1);
if(PHP_SAPI!=='cli')exit(1);
umask(0077);
function config(): array {static $c;return $c??=require __DIR__.'/config.php';}
require __DIR__.'/src/core.php';
function api(string $method,array $body=[]): mixed {$r=telegram($method,$body);if(!($r['ok']??false))throw new RuntimeException('Telegram method failed: '.$method.' ('.($r['error_code']??0).')');return $r['result']??[];}
try {
    $action=$argv[1]??'status';
    if($action==='setup-bot'){
        $endpoint=$argv[2]??'';
        if(!str_starts_with($endpoint,'https://')||str_contains($endpoint,'?'))throw new RuntimeException('Pass HTTPS base URL without query, e.g. https://todo.example.com');
        $me=api('getMe');$current=api('getWebhookInfo');
        $webhook=rtrim($endpoint,'/').'/index.php?route=webhook';
        if(!empty($current['url'])&&$current['url']!==$webhook&&!in_array('--replace-webhook',$argv,true))throw new RuntimeException('Bot has another webhook. Stop the old installation before using --replace-webhook.');
        if(config()['transport']==='polling')api('deleteWebhook',['drop_pending_updates'=>false]);
        else api('setWebhook',['url'=>$webhook,'secret_token'=>config()['webhook_secret'],'drop_pending_updates'=>false,'allowed_updates'=>['message','callback_query']]);
        api('setMyCommands',['commands'=>[['command'=>'today','description'=>'Задачи на сегодня'],['command'=>'app','description'=>'Открыть задачи']]]);
        $menu=['type'=>'web_app','text'=>'Открыть','web_app'=>['url'=>config()['mini_app_url']]];
        api('setChatMenuButton',['menu_button'=>$menu]);
        api('setChatMenuButton',['chat_id'=>config()['owner_id'],'menu_button'=>$menu]);
        echo 'Bot @'.$me['username']." configured. Main Mini App is a separate BotFather setting.\n";
    } elseif($action==='status') {
        $db=db();$me=api('getMe');$hook=api('getWebhookInfo');
        $meta=$db->query("SELECT key,value FROM meta WHERE key IN ('last_worker','last_poll','daily_today_date')")->fetchAll();
        echo json_encode(['bot_username'=>$me['username'],'main_mini_app'=>$me['has_main_web_app']??false,'webhook_url'=>$hook['url'],'pending_updates'=>$hook['pending_update_count']??0,'transport'=>config()['transport'],'meta'=>$meta],JSON_PRETTY_PRINT|JSON_UNESCAPED_UNICODE)."\n";
    } elseif($action==='client-config') {
        $endpoint=$argv[2]??'';
        if(!str_starts_with($endpoint,'https://'))throw new RuntimeException('HTTPS endpoint required');
        // Secret output only for an explicit command: redirect via SSH into a chmod-600 file.
        echo json_encode(['endpoint'=>$endpoint,'token'=>config()['sync_token']],JSON_THROW_ON_ERROR)."\n";
    } else throw new RuntimeException('Actions: setup-bot BASE_URL | status | client-config SYNC_ENDPOINT');
} catch(Throwable $e){fwrite(STDERR,$e->getMessage()."\n");exit(1);}
