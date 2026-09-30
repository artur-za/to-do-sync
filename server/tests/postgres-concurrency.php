<?php
declare(strict_types=1);
if(getenv('FLODO_TEST_DATABASE')!=='1'||!getenv('TEST_DATABASE_URL')){fwrite(STDERR,"Requires an isolated TEST_DATABASE_URL and FLODO_TEST_DATABASE=1\n");exit(1);}
function config(): array {return ['database_url'=>getenv('TEST_DATABASE_URL'),'owner_id'=>'42','mini_app_url'=>'https://example.com/mini/','timezone'=>'Europe/Moscow'];}
require __DIR__.'/../src/core.php';
if(($argv[1]??'')==='writer'){
    for($i=0;$i<10;$i++){
        beginWrite();$id=uuid();$at=nowISO();
        writeRecord('task',$id,['id'=>$id,'title'=>'Concurrency fixture','note'=>'','bucket'=>'later','order'=>0,'createdAt'=>$at,'updatedAt'=>$at,'plannedAt'=>$at]);
        usleep(10000);db()->exec('COMMIT');
    }
    exit;
}
$before=revision();$children=[];
for($i=0;$i<2;$i++)$children[]=proc_open([PHP_BINARY,__FILE__,'writer'],[0=>['pipe','r'],1=>['pipe','w'],2=>['pipe','w']],$pipes);
foreach($children as $child)if(proc_close($child)!==0)throw new RuntimeException('Concurrent writer failed');
if(revision()!==$before+20)throw new RuntimeException('Revision increments were lost');
$q=db()->query("SELECT COUNT(*) AS n,COUNT(DISTINCT version) AS versions FROM records WHERE version>".$before)->fetch();
if((int)$q['n']!==20||(int)$q['versions']!==20)throw new RuntimeException('Concurrent writes share revisions');
$lock=lockOutbox();if($lock!==true)throw new RuntimeException('Could not acquire outbox lock');unlockOutbox($lock,true);
echo "PASS: PostgreSQL concurrent writers preserve all records and unique revisions\n";
