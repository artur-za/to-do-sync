<?php
// Run with PHP CLI as the same user that runs web PHP and cron. No network calls.
declare(strict_types=1);
if(PHP_SAPI!=='cli')exit(1);
umask(0077);
function fail(string $message): never {fwrite(STDERR,$message."\n");exit(1);}
if($argc!==3)fail('Usage: php install.php /absolute/public-root /absolute/private-root');
if(PHP_VERSION_ID<80200)fail('PHP 8.2+ required');
foreach(['curl','mbstring','pdo_sqlite'] as $extension)if(!extension_loaded($extension))fail('Missing PHP extension: '.$extension);
[$script,$public,$private]=$argv;
foreach([$public,$private] as $path){if(!str_starts_with($path,'/')||str_contains($path,"\n"))fail('Use absolute paths');if(!is_dir($path)&&!mkdir($path,0700,true))fail('Cannot create directory');}
$public=realpath($public);$private=realpath($private);
if($public===$private||str_starts_with($private,$public.'/')||str_starts_with($public,$private.'/'))fail('Public and private roots must be disjoint. Never place private under web root.');
$lock=fopen($private.'/install.lock','c');if(!$lock||!flock($lock,LOCK_EX|LOCK_NB))fail('Deployment already running');
$incoming=require __DIR__.'/private/config.php';
$existing=is_file($private.'/config.php')?require $private.'/config.php':null;
if($existing&&($existing['owner_id']!==$incoming['owner_id']||$existing['bot_token']!==$incoming['bot_token']))fail('Existing owner/bot differs. Refusing to overwrite an existing installation.');
if($existing&&$existing['mini_app_url']!==$incoming['mini_app_url'])fail('Mini App URL differs. Update the existing config intentionally before deploying.');
if(!$existing){copy(__DIR__.'/private/config.php',$private.'/config.php');chmod($private.'/config.php',0600);}
$config=$existing??require $private.'/config.php';
if(!is_dir($config['data_dir']))mkdir($config['data_dir'],0700,true);
if(is_file($config['data_dir'].'/flodo.sqlite')){
    $backupDir=$private.'/backups';if(!is_dir($backupDir))mkdir($backupDir,0700);
    $db=new PDO('sqlite:'.$config['data_dir'].'/flodo.sqlite');$db->setAttribute(PDO::ATTR_ERRMODE,PDO::ERRMODE_EXCEPTION);$db->exec('PRAGMA busy_timeout=10000');
    $backup=$backupDir.'/'.gmdate('Ymd-His').'-'.bin2hex(random_bytes(3)).'.sqlite';
    $db->exec('VACUUM INTO '.$db->quote($backup));chmod($backup,0600);$db=null;
}
$release='releases/'.gmdate('Ymd-His').'-'.bin2hex(random_bytes(4));mkdir($private.'/'.$release.'/src',0700,true);
foreach(glob(__DIR__.'/private/src/*.php') as $file){copy($file,$private.'/'.$release.'/src/'.basename($file));chmod($private.'/'.$release.'/src/'.basename($file),0600);}
symlink('../../config.php',$private.'/'.$release.'/config.php');
if(file_exists($private.'/src')&&!is_link($private.'/src'))fail('Existing src is not an installer-managed symlink. See migration guide; existing files were not replaced.');
symlink($release.'/src',$private.'/src.next');rename($private.'/src.next',$private.'/src');
// All files in the public tree are explicitly enumerated; no config/data/archive can leak here.
chmod($public,0755);
if(!is_dir($public.'/mini'))mkdir($public.'/mini',0755);
foreach(new DirectoryIterator(__DIR__.'/public/mini') as $file){if(!$file->isFile())continue;$dest=$public.'/mini/'.$file->getFilename();copy($file->getPathname(),$dest.'.next');chmod($dest.'.next',0644);rename($dest.'.next',$dest);}
$entry="<?php\ndeclare(strict_types=1);\nrequire ".var_export($private.'/src/http.php',true).";\n";
file_put_contents($public.'/index.php.next',$entry);chmod($public.'/index.php.next',0644);rename($public.'/index.php.next',$public.'/index.php');
file_put_contents($public.'/.htaccess',"Options -Indexes\n<IfModule mod_rewrite.c>\nRewriteEngine On\nRewriteRule .* - [E=HTTP_AUTHORIZATION:%{HTTP:Authorization}]\n</IfModule>\n");chmod($public.'/.htaccess',0644);
copy(__DIR__.'/admin.php',$private.'/admin.php');chmod($private.'/admin.php',0600);
copy(__DIR__.'/cron.py',$private.'/cron.py');chmod($private.'/cron.py',0700);
// Initialize database before adding cron; an inaccessible data directory fails here.
function config(): array {return $GLOBALS['config'];}
require $private.'/src/core.php';db();
echo "Installed. Existing config, database and epoch preserved.\n";
echo 'Worker: '.$private."/src/worker.php\n";
echo "Run the HTTPS smoke check, then configure Telegram and cron using the deployment guide.\n";
