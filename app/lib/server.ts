import {env} from 'cloudflare:workers';
import {getChatGPTUser} from '../chatgpt-auth';
import {defaultSettings,sampleProducts,type Settings,type Product} from './catalog';
export const runtime=()=>env as unknown as Record<string,any>;
export function db():D1Database{if(!env.DB)throw new Error('Store database is unavailable. Please try again.');return env.DB;}
export async function identity(){return getChatGPTUser();}
export async function isAdmin(){const u=await identity();return !!u&&String(runtime().STORE_ADMIN_EMAILS||'').toLowerCase().split(',').map(s=>s.trim()).includes(u.email.toLowerCase());}
export async function admin(){if(!await isAdmin())fail('Sign in with the authorised store owner account.',403);}
export function fail(message:string,status=400):never{throw Object.assign(new Error(message),{status});}
export const json=(value:unknown,status=200)=>Response.json(value,{status,headers:{'Cache-Control':'no-store','X-Content-Type-Options':'nosniff'}});
export function error(e:unknown){const x=e as Error&{status?:number};console.error('Store request:',x.message);const stock=x.message?.includes('Stock or price changed');return json({error:stock?'Stock or price changed. Please refresh your bag.':x.status?x.message:'We could not complete that request. Please refresh and try again.'},stock?409:x.status||500);}
export function origin(req:Request){const o=req.headers.get('origin');if(!o||o!==new URL(req.url).origin)fail('Please submit from this store.',403);}
export async function body(req:Request){if(Number(req.headers.get('content-length')||0)>50000)fail('Request too large.',413);const t=await req.text();if(t.length>50000)fail('Request too large.',413);try{return JSON.parse(t);}catch{fail('Invalid request.');}}
export async function initialize(){const d=db();if(await d.prepare("SELECT value FROM settings WHERE key='initialized'").first())return;const q=sampleProducts.map(p=>d.prepare(`INSERT OR IGNORE INTO products(id,name,category,scent,notes,description,price,original_price,stock,size,burn,image,image_position,visible,sample,badge,created_at) SELECT ?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,? WHERE NOT EXISTS(SELECT 1 FROM settings WHERE key='initialized')`).bind(p.id,p.name,p.category,p.scent,p.notes,p.description,p.price,p.originalPrice,p.stock,p.size,p.burn,p.image,p.imagePosition,1,1,p.badge,p.createdAt));q.push(d.prepare("INSERT OR IGNORE INTO settings(key,value) VALUES('store',?)").bind(JSON.stringify(defaultSettings)));q.push(d.prepare("INSERT OR IGNORE INTO settings(key,value) VALUES('initialized','1')"));await d.batch(q);}
export async function settings():Promise<Settings>{const r=await db().prepare("SELECT value FROM settings WHERE key='store'").first<{value:string}>();return{...defaultSettings,...(r?JSON.parse(r.value):{})};}
export const product=(r:any):Product=>({...r,originalPrice:r.original_price,imagePosition:r.image_position,createdAt:r.created_at});
export const order=(r:any)=>({...r,access_token:undefined,request_id:undefined,items:JSON.parse(r.items)});
export const clean=(v:unknown,max=500)=>String(v??'').trim().slice(0,max);
export async function hash(secret:string,value:string){const k=await crypto.subtle.importKey('raw',new TextEncoder().encode(secret),{name:'HMAC',hash:'SHA-256'},false,['sign']);const raw=await crypto.subtle.sign('HMAC',k,new TextEncoder().encode(value));return Array.from(new Uint8Array(raw)).map(b=>b.toString(16).padStart(2,'0')).join('');}
export function equal(a:string,b:string){if(a.length!==b.length)return false;let n=0;for(let i=0;i<a.length;i++)n|=a.charCodeAt(i)^b.charCodeAt(i);return n===0;}
export async function razor(path:string,o:RequestInit={}){const e=runtime();const res=await fetch('https://api.razorpay.com/v1/'+path,{...o,signal:AbortSignal.timeout(15000),headers:{Authorization:'Basic '+btoa(e.RAZORPAY_KEY_ID+':'+e.RAZORPAY_KEY_SECRET),'Content-Type':'application/json',...o.headers}});const data=await res.json() as any;if(!res.ok)fail('The payment provider is unavailable. Please try again.',502);return data;}
