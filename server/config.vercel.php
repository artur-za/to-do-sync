<?php
declare(strict_types=1);
function envRequired(string $name): string {$value=getenv($name);if($value===false||trim($value)==='')throw new RuntimeException('Missing environment: '.$name);return $value;}
$owner=envRequired('OWNER_ID');if(!preg_match('/^[1-9][0-9]+$/',$owner))throw new RuntimeException('Invalid OWNER_ID');
$sync=envRequired('SYNC_TOKEN');$hook=envRequired('WEBHOOK_SECRET');$cron=envRequired('CRON_SECRET');
foreach([$sync,$hook,$cron] as $secret)if(strlen($secret)<43)throw new RuntimeException('Use random 256-bit secrets');
$base=rtrim(envRequired('PUBLIC_URL'),'/');if(!str_starts_with($base,'https://'))throw new RuntimeException('HTTPS required');
return ['database_url'=>envRequired('DATABASE_URL'),'data_dir'=>'/tmp/flodo-unused','bot_token'=>envRequired('BOT_TOKEN'),'owner_id'=>$owner,'sync_token'=>$sync,'webhook_secret'=>$hook,'cron_secret'=>$cron,'mini_app_url'=>$base.'/mini/','timezone'=>getenv('TIMEZONE')?:'Europe/Moscow','transport'=>'webhook'];
