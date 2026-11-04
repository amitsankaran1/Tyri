import { createHandler } from '../lib/handler.mjs';
const handle=createHandler();
export default { fetch(request) { return handle(request, 'create'); } };
