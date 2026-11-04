import pg from 'pg';
import { randomBytes, randomUUID, createHash } from 'node:crypto';
let singleton;
export function store() {
  if (!singleton) {
    if (!process.env.DATABASE_URL) throw Error('database_unconfigured');
    const connection = new URL(process.env.DATABASE_URL); connection.searchParams.set("sslmode", "verify-full");
    singleton = new AttestationStore(new pg.Pool({ connectionString: connection.href, max: 3, idleTimeoutMillis: 10000, connectionTimeoutMillis: 10000 }));
  }
  return singleton;
}
export class AttestationStore {
  constructor(pool, environment = 'production') { this.pool = pool; this.environment = environment; }
  async transaction(fn) {
    const c = await this.pool.connect();
    try { await c.query('BEGIN'); const result = await fn(c); await c.query('COMMIT'); return result; }
    catch(e) { await c.query('ROLLBACK'); throw e; } finally { c.release(); }
  }
  async limit(c, scope, max, bucket) {
    const r = await c.query(`INSERT INTO tyri_budgets(environment,scope,bucket,count) VALUES($1,$2,$3,1)
      ON CONFLICT(environment,scope,bucket) DO UPDATE SET count=tyri_budgets.count+1 WHERE tyri_budgets.count < $4 RETURNING count`, [this.environment,scope,bucket,max]);
    if (!r.rowCount) throw Error('rate_limited');
  }
  async challenge(keyID, purpose, ip) {
    const result = await this.transaction(async c => {
      const hour = new Date().toISOString().slice(0,13), day = hour.slice(0,10);
      const ipHash = createHash('sha256').update(`${day}:${ip}`).digest('hex');
      await this.limit(c, 'ingress:'+ipHash, 120, hour);
      await this.limit(c, 'challenge-global', 3000, day);
      if (purpose === 'create') {
        const found = await c.query('SELECT 1 FROM tyri_devices WHERE environment=$1 AND key_id=$2',[this.environment,keyID]);
        if (!found.rowCount) return { error: 'device_not_enrolled' };
      }
      // Bounded retention: no prompts or app selections are persisted here.
      await c.query("DELETE FROM tyri_challenges WHERE expires_at < NOW() - INTERVAL '1 hour'");
      await c.query("DELETE FROM tyri_budgets WHERE created_at < NOW() - INTERVAL '2 days'");
      const id=randomUUID(), challenge=randomBytes(32).toString('base64');
      await c.query("INSERT INTO tyri_challenges(id,environment,key_id,purpose,challenge,expires_at) VALUES($1,$2,$3,$4,$5,NOW()+INTERVAL '5 minutes')",[id,this.environment,keyID,purpose,challenge]);
      return {id,challenge};
    });
    if (result.error) throw Error(result.error);
    return result;
  }
  async pending(id,keyID,purpose) {
    const r=await this.pool.query('SELECT challenge FROM tyri_challenges WHERE id=$1 AND environment=$2 AND key_id=$3 AND purpose=$4 AND expires_at>NOW() AND consumed=false',[id,this.environment,keyID,purpose]);
    if (!r.rowCount) throw Error('invalid_challenge'); return r.rows[0].challenge;
  }
  async device(keyID) {
    const r=await this.pool.query('SELECT * FROM tyri_devices WHERE environment=$1 AND key_id=$2',[this.environment,keyID]);
    return r.rows[0];
  }
  async enroll({id,keyID,publicKey,receipt,proofHash}) {
    return this.transaction(async c=>{
      const r=await c.query("UPDATE tyri_challenges SET consumed=true WHERE id=$1 AND environment=$2 AND key_id=$3 AND purpose='enroll' AND consumed=false AND expires_at>NOW() RETURNING id",[id,this.environment,keyID]);
      if(!r.rowCount) throw Error('invalid_challenge');
      const inserted=await c.query('INSERT INTO tyri_devices(environment,key_id,public_key,receipt,proof_hash,counter) VALUES($1,$2,$3,$4,$5,0) ON CONFLICT DO NOTHING RETURNING key_id',[this.environment,keyID,publicKey,receipt,proofHash]);
      if(!inserted.rowCount) throw Error('already_enrolled');
    });
  }
  async consume({id,keyID,counter}) {
    return this.transaction(async c=>{
      const r=await c.query("UPDATE tyri_challenges SET consumed=true WHERE id=$1 AND environment=$2 AND key_id=$3 AND purpose='create' AND consumed=false AND expires_at>NOW() RETURNING id",[id,this.environment,keyID]);
      if(!r.rowCount) throw Error('invalid_challenge');
      const advanced=await c.query('UPDATE tyri_devices SET counter=$1 WHERE environment=$2 AND key_id=$3 AND counter<$1 RETURNING key_id',[counter,this.environment,keyID]);
      if(!advanced.rowCount) throw Error('replayed_counter');
      const day=new Date().toISOString().slice(0,10);
      await this.limit(c,'model-device:'+keyID,30,day);
      await this.limit(c,'model-global',500,day);
    });
  }
}
