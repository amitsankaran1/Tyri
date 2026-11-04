import test from 'node:test';
import assert from 'node:assert/strict';
import {createHandler,validateRequest} from '../lib/handler.mjs';
const keyID=Buffer.alloc(32,1).toString('base64'), challengeID='00000000-0000-4000-8000-000000000001';
const request={text:'Block Games weekdays 9am–5pm',lists:[{id:challengeID,name:'Games'}],timeZone:'America/New_York',locale:'en_US'};
const body={challengeID,challenge:'challenge',request};
function req(value=body,headers={}){return new Request('https://example.com/api/create',{method:'POST',headers:{'content-type':'application/json','x-tyri-key-id':keyID,...headers},body:JSON.stringify(value)});}
function harness(overrides={}){
 let consumed=0,calls=0;
 const db={environment:'production',device:async()=>({public_key:'fixture',counter:0}),pending:async()=> 'challenge',consume:async()=>{consumed++},...overrides};
 return {db,handle:createHandler({getStore:()=>db,assertionVerifier:()=>1,extractor:async()=>{calls++;return {fixture:true}}}),counts:()=>({consumed,calls})};
}
test('test doubles: consumes proof before extraction',async()=>{const h=harness();assert.equal((await h.handle(req(),'create')).status,200);assert.deepEqual(h.counts(),{consumed:1,calls:1})});
test('no model call for challenge mismatch',async()=>{const h=harness();assert.equal((await h.handle(req({...body,challenge:'wrong'}),'create')).status,401);assert.equal(h.counts().calls,0)});
test('no model call for unknown device',async()=>{const h=harness({device:async()=>null});assert.equal((await h.handle(req(),'create')).status,401);assert.equal(h.counts().calls,0)});
test('no model call if replay transaction fails',async()=>{const h=harness({consume:async()=>{throw Error('replayed_counter')}});assert.equal((await h.handle(req(),'create')).status,401);assert.equal(h.counts().calls,0)});
test('provider remains explicitly unconfigured',async()=>{const h=harness();const handle=createHandler({getStore:()=>h.db,assertionVerifier:()=>1});const r=await handle(req(),'create');assert.equal(r.status,503);assert.equal((await r.json()).error,'provider_unconfigured')});
test('rejects oversized body before verification',async()=>{const h=harness();assert.equal((await h.handle(req({...body,extra:'x'.repeat(25000)}),'create')).status,413)});
test('rejects invalid list IDs and extra token data',()=>{assert.throws(()=>validateRequest({...request,lists:[{id:'bad',name:'Games'}]}));assert.throws(()=>validateRequest({...request,tokens:[]}))});
test('rejects blank descriptions and duplicate list IDs',()=>{assert.throws(()=>validateRequest({...request,text:' '}));assert.throws(()=>validateRequest({...request,lists:[request.lists[0],request.lists[0]]}))});
test('rate limit prevents extraction',async()=>{const h=harness({consume:async()=>{throw Error('rate_limited')}});assert.equal((await h.handle(req(),'create')).status,429);assert.equal(h.counts().calls,0)});
