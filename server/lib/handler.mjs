import { store } from './store.mjs';
import { base64, digest, verifyEnrollment, verifyRequest } from './attestation.mjs';
const json=(value,status=200)=>Response.json(value,{status,headers:{'Cache-Control':'no-store'}});
const uuid=/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
async function body(request) {
  if(!(request.headers.get('content-type')||'').startsWith('application/json')) throw Error('invalid_request');
  if(Number(request.headers.get('content-length')||0)>24576) throw Error('body_too_large');
  const reader=request.body?.getReader(); if(!reader) throw Error('invalid_request');
  const parts=[]; let size=0;
  try { while(true) {const {value,done}=await reader.read(); if(done)break; size+=value.length;if(size>24576)throw Error('body_too_large');parts.push(value);} }
  finally { await reader.cancel().catch(()=>{}); }
  const raw=Buffer.concat(parts); return {raw,value:JSON.parse(raw.toString('utf8'))};
}
function keys(value,allowed) { if(!value||Array.isArray(value)||typeof value!=='object'||Object.keys(value).some(k=>!allowed.includes(k)))throw Error('invalid_request'); }
export function createHandler({getStore=store,enrollVerifier=verifyEnrollment,assertionVerifier=verifyRequest,extractor=null}={}) {
  return async function handle(request,route) {
    if(request.method!=='POST')return json({error:'method_not_allowed'},405);
    try {
      const {raw,value}=await body(request); const db=getStore();
      const keyID=request.headers.get('x-tyri-key-id')||value.keyID;
      if(base64(keyID,44).length!==32)throw Error('invalid_request');
      if(route==='challenge') {
        keys(value,['keyID','purpose']);if(!['enroll','create'].includes(value.purpose))throw Error('invalid_request');
        return json(await db.challenge(keyID,value.purpose,request.headers.get('x-vercel-forwarded-for')||'local'));
      }
      if(!uuid.test(value.challengeID))throw Error('invalid_request');
      if(route==='enroll') {
        keys(value,['keyID','challengeID','attestation']);
        const proofHash=digest(raw).toString('hex');
        const existing=await db.device(keyID);
        // Lost enrollment responses are retryable only with the exact same proof; counter is never reset.
        if(existing) { if(existing.proof_hash===proofHash)return json({enrolled:true});throw Error('already_enrolled'); }
        const challenge=await db.pending(value.challengeID,keyID,'enroll');
        let verified; try { verified=enrollVerifier({attestation:value.attestation,challenge,keyID,environment:db.environment}); } catch { throw Error("invalid_attestation"); }
        await db.enroll({id:value.challengeID,keyID,...verified,proofHash}); return json({enrolled:true});
      }
      if(route==='create') {
        keys(value,['challengeID','challenge','request']);
        const device=await db.device(keyID);if(!device)throw Error('device_not_enrolled');
        const challenge=await db.pending(value.challengeID,keyID,'create');if(value.challenge!==challenge)throw Error('invalid_challenge');
        let counter; try { counter=assertionVerifier({assertion:request.headers.get('x-tyri-assertion'),payload:raw,publicKey:device.public_key,previousCounter:Number(device.counter),environment:db.environment}); } catch { throw Error('invalid_assertion'); }
        // Provider choice is deliberately not wired until the Jev/Luna evaluation decision.
        if(!extractor)return json({error:'provider_unconfigured'},503);
        validateRequest(value.request);
        await db.consume({id:value.challengeID,keyID,counter});
        return json(await extractor(value.request,request.signal));
      }
      return json({error:'not_found'},404);
    } catch(e) {
      const code=e.message;
      if(code==='rate_limited')return json({error:'rate_limited'},429);
      if(code==='body_too_large')return json({error:'body_too_large'},413);
      if(['invalid_request','invalid_base64'].includes(code)||e instanceof SyntaxError)return json({error:'invalid_request'},400);
      if(code==='database_unconfigured')return json({error:'service_unavailable'},503);
      // Never log raw proof, request text, list names, tokens, or provider errors.
      if(['invalid_challenge','already_enrolled','device_not_enrolled','wrong_app','replayed_counter','invalid_signature','invalid_attestation','invalid_assertion','expired_certificate','invalid_certificate_chain','invalid_auth_data','trailing_auth_data','invalid_extensions','invalid_validation_category','wrong_environment'].includes(code)) return json({error:code==='device_not_enrolled'?code:'device_verification_failed'},401);
      console.error('tyri_request_failed',e.name);return json({error:'service_unavailable'},503);
    }
  };
}
export function validateRequest(r) {
  keys(r,['text','lists','timeZone','locale']);
  if(typeof r.text!=='string'||!r.text.trim()||r.text.length>2000||!Array.isArray(r.lists)||r.lists.length>50||typeof r.timeZone!=='string'||r.timeZone.length>80||typeof r.locale!=='string'||r.locale.length>40)throw Error('invalid_request');
  const ids=new Set();
  for(const l of r.lists){keys(l,['id','name']);if(!uuid.test(l.id)||ids.has(l.id.toLowerCase())||typeof l.name!=='string'||!l.name.trim()||l.name.length>100)throw Error('invalid_request');ids.add(l.id.toLowerCase());}
}
