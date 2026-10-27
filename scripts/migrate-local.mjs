import {readdirSync,existsSync} from 'node:fs';
import {spawnSync} from 'node:child_process';
const config='dist/server/wrangler.json';
if(!existsSync(config))throw new Error('Run pnpm build first.');
for(const migration of readdirSync('drizzle').filter(n=>n.endsWith('.sql')).sort()){
 const result=spawnSync(process.execPath,['--import','./scripts/sites-env.mjs','./node_modules/wrangler/bin/wrangler.js','d1','execute','DB','--local','--config',config,'--persist-to','.wrangler/state','--file','drizzle/'+migration],{stdio:'inherit'});
 if(result.status)process.exit(result.status||1);
}
console.log('Local schema applied. Run only once per new local database; do not replay applied migrations.');
