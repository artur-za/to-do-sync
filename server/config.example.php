<?php
// Prefer outside public_html; otherwise deny HTTP access and verify ALL SQLite sidecars.
// Never commit real credentials.
return [
    'data_dir'=>__DIR__.'/data',
    'timezone'=>'Europe/Moscow',
    'mini_app_url'=>'https://YOUR_DOMAIN/flodo-open/mini/index.php',
    'transport'=>'polling', // cron every minute; webhook is also supported
    'telegram_api_ip'=>null, // optional verified API endpoint; TLS validation stays enabled
    'owner_id'=>'YOUR_TELEGRAM_USER_ID',
    'bot_token'=>'FROM_BOTFATHER',
    'sync_token'=>'GENERATE_32_RANDOM_BYTES_OR_MORE',
    'webhook_secret'=>'GENERATE_32_RANDOM_BYTES_OR_MORE',
];
