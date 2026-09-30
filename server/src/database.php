<?php
declare(strict_types=1);
function postgres(): bool {return !empty(config()['database_url']);}
function db(): PDO {
    static $db;
    if($db)return $db;
    $options=[PDO::ATTR_ERRMODE=>PDO::ERRMODE_EXCEPTION,PDO::ATTR_DEFAULT_FETCH_MODE=>PDO::FETCH_ASSOC];
    if(postgres()){
        $u=parse_url(config()['database_url']);
        if(!$u||!in_array($u['scheme']??'',['postgres','postgresql'],true)||empty($u['host'])||empty($u['path']))throw new RuntimeException('Invalid database URL');
        parse_str($u['query']??'',$q);$ssl=$q['sslmode']??'require';
        if(!in_array($ssl,['require','verify-ca','verify-full'],true)&&getenv('FLODO_TEST_DATABASE')!=='1')throw new RuntimeException('PostgreSQL requires TLS');
        $host=$u['host'];$name=rawurldecode(ltrim($u['path'],'/'));
        if(strpbrk($host.$name.$ssl,";\r\n")!==false)throw new RuntimeException('Invalid database parameters');
        $db=new PDO('pgsql:host='.$host.';port='.($u['port']??5432).';dbname='.$name.';sslmode='.$ssl,rawurldecode($u['user']??''),rawurldecode($u['pass']??''),$options);
        // Dedicated DB/schema, transaction-scoped locks: safe with transaction poolers.
        $db->beginTransaction();$db->query('SELECT pg_advisory_xact_lock(739204,0)');
        $db->exec(schema('BIGSERIAL PRIMARY KEY'));
    }else{
        $path=config()['data_dir'];if(!is_dir($path))mkdir($path,0700,true);
        $db=new PDO('sqlite:'.$path.'/flodo.sqlite',null,null,$options);
        $db->exec('PRAGMA journal_mode=WAL; PRAGMA busy_timeout=10000;');
        $db->exec(schema('INTEGER PRIMARY KEY AUTOINCREMENT'));
        chmod($path.'/flodo.sqlite',0600);
    }
    $q=$db->prepare('INSERT INTO meta(key,value) VALUES(?,?) ON CONFLICT(key) DO NOTHING');
    $q->execute(['epoch',uuid()]);$q->execute(['rev','0']);
    if(postgres())$db->commit();
    return $db;
}
function schema(string $serial): string {return "
    CREATE TABLE IF NOT EXISTS meta (key TEXT PRIMARY KEY,value TEXT NOT NULL);
    CREATE TABLE IF NOT EXISTS records (kind TEXT NOT NULL,id TEXT NOT NULL,version BIGINT NOT NULL,deleted INTEGER NOT NULL DEFAULT 0,json TEXT,PRIMARY KEY(kind,id));
    CREATE TABLE IF NOT EXISTS conflicts (id $serial,kind TEXT,record_id TEXT,payload TEXT,created_at TEXT);
    CREATE TABLE IF NOT EXISTS updates (id BIGINT PRIMARY KEY,created_at BIGINT NOT NULL);
    CREATE TABLE IF NOT EXISTS sessions (user_id TEXT PRIMARY KEY,json TEXT,expires BIGINT);
    CREATE TABLE IF NOT EXISTS outbox (id $serial,unique_key TEXT UNIQUE,method TEXT NOT NULL,json TEXT NOT NULL,sent INTEGER DEFAULT 0,attempts INTEGER DEFAULT 0,next_attempt BIGINT DEFAULT 0);
    CREATE TABLE IF NOT EXISTS reminders (task_id TEXT,at TEXT,PRIMARY KEY(task_id,at));
";}
function beginWrite(): void {
    if(postgres()){db()->beginTransaction();db()->query('SELECT pg_advisory_xact_lock(739204,1)');}
    else db()->exec('BEGIN IMMEDIATE');
}
function lockOutbox(): mixed {
    if(postgres()){
        db()->beginTransaction();$locked=db()->query('SELECT pg_try_advisory_xact_lock(739204,2)')->fetchColumn();
        if(!$locked){db()->rollBack();return false;}return true;
    }
    $lock=fopen(config()['data_dir'].'/outbox.lock','c');
    if(!$lock||!flock($lock,LOCK_EX|LOCK_NB)){if($lock)fclose($lock);return false;}
    return $lock;
}
function unlockOutbox(mixed $lock,bool $success): void {
    if(postgres()){if($success)db()->commit();else db()->rollBack();}
    else{flock($lock,LOCK_UN);fclose($lock);}
}
