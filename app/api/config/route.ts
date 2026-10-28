import {route} from '../../lib/server';
export const dynamic='force-dynamic';
export const GET=(req:Request)=>route(req,'config');
