import {route} from '../../../lib/server';
export const dynamic='force-dynamic';
export const POST=(req:Request)=>route(req,'payments/verify');
