import {env} from 'cloudflare:workers';
import {handle,type Config} from '../../server/store';
export const route=(req:Request,path:string)=>handle(req,env as unknown as Config,path);
