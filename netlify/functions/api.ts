import {handle} from '../../server/store';
export default (request:Request)=>handle(request,process.env,new URL(request.url).pathname.replace(/^\/(?:\.netlify\/functions\/)?api\//,''));
export const config={path:'/api/*'};
