<?php
require __DIR__.'/../src/mini-auth.php';
$token='TEST_TOKEN_NOT_REAL';$now=1790770000;$user=['id'=>42,'first_name'=>'Test'];
function signed(array $fields,string $token):string {ksort($fields);$lines=[];foreach($fields as $k=>$v)$lines[]=$k.'='.$v;$fields['hash']=hash_hmac('sha256',implode("\n",$lines),hash_hmac('sha256',$token,'WebAppData',true));return http_build_query($fields);}
$raw=signed(['auth_date'=>(string)$now,'query_id'=>'test','user'=>json_encode($user)],$token);
$cases=[miniAppUser($raw,$token,'42',$now)!==null,miniAppUser($raw,$token,'99',$now)===null,miniAppUser($raw,$token.'wrong','42',$now)===null,miniAppUser($raw,$token,'42',$now+86401)===null,miniAppUser($raw,$token,'42',$now-31)===null,miniAppUser($raw.'&user=x',$token,'42',$now)===null,miniAppUser(str_replace('Test','Changed',$raw),$token,'42',$now)===null,miniAppUser('',$token,'42',$now)===null,miniAppUser(signed(['auth_date'=>(string)$now,'user'=>json_encode($user),'signature'=>'test-signature'],$token),$token,'42',$now)!==null];
foreach($cases as $i=>$ok)if(!$ok)throw new RuntimeException('Auth test failed: '.$i);
echo 'PASS: '.count($cases)." Mini App authentication checks\n";
