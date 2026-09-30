<?php
declare(strict_types=1);
/** Validate Telegram's raw initData, never initDataUnsafe or a client-supplied user ID. */
function miniAppUser(string $raw,string $token,string $owner,?int $now=null): ?array {
    if($raw===''||strlen($raw)>16384)return null;
    $data=[];
    foreach(explode('&',$raw) as $pair){
        $parts=explode('=',$pair,2);$key=urldecode($parts[0]);
        if(!preg_match('/^[a-z_]+$/',$key)||array_key_exists($key,$data))return null;
        $data[$key]=urldecode($parts[1]??'');
    }
    $hash=$data['hash']??'';unset($data['hash']);
    if(!preg_match('/^[a-f0-9]{64}$/',$hash)||!ctype_digit($data['auth_date']??''))return null;
    $time=(int)$data['auth_date'];$now??=time();if($time>$now+30||$time<$now-86400)return null;
    ksort($data,SORT_STRING);$check=implode("\n",array_map(fn($k)=>$k.'='.$data[$k],array_keys($data)));
    $secret=hash_hmac('sha256',$token,'WebAppData',true);
    if(!hash_equals(hash_hmac('sha256',$check,$secret),$hash))return null;
    $user=json_decode($data['user']??'',true);
    if(!is_array($user)||(string)($user['id']??'')!==$owner)return null;
    return $user;
}
