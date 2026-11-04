import { createHash, X509Certificate, createVerify } from 'node:crypto';
import cbor from 'cbor';
import { verifyAttestation } from 'node-app-attest';

export const appIdentity = { teamIdentifier: 'DAG83US2FV', bundleIdentifier: 'name.amitsankaran.Block' };
export const digest = bytes => createHash('sha256').update(bytes).digest();
export function base64(text, max = 16000) {
  if (typeof text !== 'string' || text.length > max || !/^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$/.test(text)) throw Error('invalid_base64');
  const value = Buffer.from(text, 'base64');
  if (!value.length || value.toString('base64') !== text) throw Error('invalid_base64');
  return value;
}
function decode(bytes) { return cbor.decodeFirstSync(bytes, { required: true, max_depth: 16, preventDuplicateKeys: true }); }
function extensions(auth, offset, environment) {
  const hasExtensions = (auth[32] & 0x80) !== 0;
  if (!hasExtensions) { if (auth.length !== offset) throw Error('trailing_auth_data'); return; }
  const value = decode(auth.subarray(offset));
  if (!value || typeof value !== 'object' || Buffer.isBuffer(value) || Array.isArray(value)) throw Error('invalid_extensions');
  const category = value.apple_validation_category_01;
  const version = value.apple_bundle_version_01;
  // Older OS versions omit extensions. When present, both authenticated properties must be valid.
  if (!Buffer.isBuffer(category) || category.length !== 4 || typeof version !== 'string' || !/^\d+(?:\.\d+){0,2}$/.test(version)) throw Error('invalid_extensions');
  const permitted = environment === 'production' ? [2, 4] : [3];
  if (!permitted.includes(category.readUInt32LE(0))) throw Error('invalid_validation_category');
}
export function verifyEnrollment({ attestation, challenge, keyID, environment = 'production', now = new Date() }) {
  const bytes = base64(attestation);
  const decoded = decode(bytes);
  if (decoded?.fmt !== 'apple-appattest' || decoded?.attStmt?.x5c?.length !== 2) throw Error('invalid_attestation');
  const [leaf, issuer] = decoded.attStmt.x5c.map(x => new X509Certificate(x));
  for (const cert of [leaf, issuer]) {
    if (now < new Date(cert.validFrom) || now > new Date(cert.validTo)) throw Error('expired_certificate');
  }
  if (leaf.ca || !issuer.ca || !leaf.checkIssued(issuer)) throw Error('invalid_certificate_chain');
  const auth = decoded.authData;
  if (!Buffer.isBuffer(auth) || auth.length < 87 || !(auth[32] & 0x40) || auth.readUInt16BE(53) !== 32) throw Error('invalid_auth_data');
  const cose = cbor.decodeFirstSync(auth.subarray(87), { extendedResults: true, max_depth: 8, required: true, preventDuplicateKeys: true });
  extensions(auth, 87 + cose.length, environment);
  const verified = verifyAttestation({ attestation: bytes, challenge: base64(challenge, 44), keyId: keyID,
    ...appIdentity, allowDevelopmentEnvironment: environment === 'development' });
  if (verified.environment !== environment) throw Error('wrong_environment');
  return { publicKey: verified.publicKey, receipt: verified.receipt.toString('base64') };
}
export function verifyRequest({ assertion, payload, publicKey, previousCounter, environment = 'production' }) {
  const value = decode(base64(assertion, 12000));
  const auth = value?.authenticatorData, signature = value?.signature;
  if (!Buffer.isBuffer(auth) || auth.length < 37 || !Buffer.isBuffer(signature)) throw Error('invalid_assertion');
  // App Attest assertions may set AT while retaining the short 37-byte header.
  // Never strip or rewrite flags: signature verification covers the original bytes.
  extensions(auth, 37, environment);
  if (!auth.subarray(0,32).equals(digest(`${appIdentity.teamIdentifier}.${appIdentity.bundleIdentifier}`))) throw Error('wrong_app');
  const counter = auth.readUInt32BE(33);
  if (counter <= previousCounter) throw Error('replayed_counter');
  const nonce = digest(Buffer.concat([auth, digest(payload)]));
  const verifier = createVerify('SHA256'); verifier.update(nonce);
  if (!verifier.verify(publicKey, signature)) throw Error('invalid_signature');
  return counter;
}
