import {route} from '../../lib/server';
export const dynamic='force-dynamic';
export const GET=(req:Request)=>route(req,'admin');
export const POST=(req:Request)=>route(req,'admin');
