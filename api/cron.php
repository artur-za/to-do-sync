<?php
declare(strict_types=1);
header('Content-Type: application/json');header('Cache-Control: no-store');
$secret=getenv('CRON_SECRET');
if(!$secret||strlen($secret)<43||!hash_equals('Bearer '.$secret,$_SERVER['HTTP_AUTHORIZATION']??'')){http_response_code(401);echo '{"error":"unauthorized"}';exit;}
function config(): array {static $c;return $c??=require __DIR__.'/../server/config.vercel.php';}
require __DIR__.'/../server/src/core.php';require __DIR__.'/../server/src/bot.php';
try {reminders();dailyToday();flushOutbox(3);botMeta('last_worker',nowISO());echo '{"ok":true}';}
catch(Throwable $e){error_log('Flodo cron failed: '.get_class($e));http_response_code(500);echo '{"error":"cron_failed"}';}
