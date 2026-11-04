import { readFile } from 'node:fs/promises';
import { store } from './lib/store.mjs';
const db=store(); await db.pool.query(await readFile(new URL('./schema.sql',import.meta.url),'utf8')); await db.pool.end(); console.log('Attestation schema ready.');
