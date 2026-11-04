// Explicit integration probe: disposable namespace, real dedicated Neon database.
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {store,AttestationStore} from '../lib/store.mjs';
const pool=store().pool, environment='test-'+randomUUID(), db=new AttestationStore(pool,environment);
const keyID=Buffer.alloc(32,9).toString('base64');
try {
 const enrollment=await db.challenge(keyID,'enroll','fixture');
 await db.enroll({id:enrollment.id,keyID,publicKey:'test-public-key',receipt:'test-receipt',proofHash:'fixture'});
 const challenge=await db.challenge(keyID,'create','fixture');
 const results=await Promise.allSettled(Array.from({length:10},()=>db.consume({id:challenge.id,keyID,counter:1})));
 assert.equal(results.filter(x=>x.status==='fulfilled').length,1);
 assert.equal(Number((await db.device(keyID)).counter),1);
 const stale=await db.challenge(keyID,'create','fixture');
 await assert.rejects(()=>db.consume({id:stale.id,keyID,counter:1}));
 const reenroll=await db.challenge(keyID,'enroll','fixture');
 await assert.rejects(()=>db.enroll({id:reenroll.id,keyID,publicKey:'new',receipt:'new',proofHash:'new'}));
 assert.equal(Number((await db.device(keyID)).counter),1);
 const expired=await db.challenge(keyID,'create','fixture');
 await pool.query("UPDATE tyri_challenges SET expires_at=NOW()-INTERVAL '1 second' WHERE id=$1",[expired.id]);
 await assert.rejects(()=>db.consume({id:expired.id,keyID,counter:2}));
 const other=new AttestationStore(pool,environment+'-other'); assert.equal(await other.device(keyID),undefined);
 console.log('PASS: real database single-use concurrency (1/10), stale counters, re-enrollment, expiry, environment isolation.');
} finally {
 await pool.query('DELETE FROM tyri_challenges WHERE environment=$1',[environment]);
 await pool.query('DELETE FROM tyri_devices WHERE environment=$1',[environment]);
 await pool.query('DELETE FROM tyri_budgets WHERE environment=$1',[environment]);
 await pool.end(); console.log('Disposable integration records cleaned up.');
}
