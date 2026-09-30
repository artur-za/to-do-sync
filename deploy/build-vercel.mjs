import {mkdir,copyFile,writeFile} from 'node:fs/promises';
const username=process.env.BOT_USERNAME;
if(!/^[A-Za-z0-9_]{5,32}$/.test(username||''))throw Error('Set BOT_USERNAME in Vercel build environment');
await mkdir('public/mini',{recursive:true});
for(const file of ['index.html','app.mjs','model.mjs','icons.mjs','gestures.mjs','style.css'])await copyFile('mini-app/'+file,'public/mini/'+file);
await writeFile('public/mini/config.mjs',`export const BOT_USERNAME=${JSON.stringify(username)};\nexport const API_URL='/api/index.php?route=mini-sync';\n`);
