<?php
declare(strict_types=1);
function config(): array {static $c;return $c??=require __DIR__.'/../server/config.vercel.php';}
require __DIR__.'/../server/src/http.php';
