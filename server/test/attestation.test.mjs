import test from 'node:test';
import assert from 'node:assert/strict';
import {generateKeyPairSync,createSign} from 'node:crypto';
import cbor from 'cbor';
import {verifyRequest,verifyEnrollment,digest,base64,appIdentity} from '../lib/attestation.mjs';
const {privateKey,publicKey}=generateKeyPairSync('ec',{namedCurve:'prime256v1'});
const payload=Buffer.from('{"challenge":"example","request":{"text":"Block Games"}}');
function proof({flags=0x40,counter=1,app=`${appIdentity.teamIdentifier}.${appIdentity.bundleIdentifier}`,extensions,body=payload}={}) {
 const a=Buffer.alloc(37);digest(app).copy(a);a[32]=flags;a.writeUInt32BE(counter,33);
 const auth=extensions?Buffer.concat([a,cbor.encode(extensions)]):a;
 const signer=createSign('SHA256');signer.update(digest(Buffer.concat([auth,digest(body)])));
 return cbor.encode({authenticatorData:auth,signature:signer.sign(privateKey)}).toString('base64');
}
const verify=assertion=>verifyRequest({assertion,payload,publicKey,previousCounter:0});
test('accepts generated-key short assertion with AT flag; exact signed bytes',()=>assert.equal(verify(proof()),1));
test('accepts legacy short assertion without AT',()=>assert.equal(verify(proof({flags:0})),1));
test('rejects changed body',()=>assert.throws(()=>verify(proof({body:Buffer.from('different')}))));
test('rejects different app',()=>assert.throws(()=>verify(proof({app:'wrong.app'}))));
test('rejects stale counter',()=>assert.throws(()=>verifyRequest({assertion:proof(),payload,publicKey,previousCounter:1})));
test('rejects appended CBOR',()=>assert.throws(()=>verify(Buffer.concat([Buffer.from(proof(),'base64'),Buffer.from([0])]).toString('base64'))));
for(const category of [2,4])test(`accepts authenticated production category ${category}`,()=>{
 const b=Buffer.alloc(4);b.writeUInt32LE(category);
 assert.equal(verify(proof({flags:0xc0,extensions:{apple_validation_category_01:b,apple_bundle_version_01:'3'}})),1);
});
test('rejects development extension in production',()=>{
 const b=Buffer.alloc(4);b.writeUInt32LE(3);assert.throws(()=>verify(proof({flags:0xc0,extensions:{apple_validation_category_01:b,apple_bundle_version_01:'3'}})));
});
test('rejects trailing auth data without extension flag',()=>assert.throws(()=>verify(proof({extensions:{a:1}}))));
test('rejects malformed enrollment',()=>assert.throws(()=>verifyEnrollment({attestation:cbor.encode({}).toString('base64'),challenge:Buffer.alloc(32).toString('base64'),keyID:Buffer.alloc(32).toString('base64')})));
test('base64 is strict',()=>{assert.throws(()=>base64('!!!'));assert.throws(()=>base64('YWJj\n'));assert.equal(base64('YWJj').toString(),'abc')});
