/* Evora end-to-end encryption helpers (WebCrypto).
 * Same steps as the Evora Android app:
 *  - X25519 key pair per person; private key locked with a passcode (PBKDF2-SHA256, AES-GCM)
 *  - random photo key per share; photos encrypted with AES-256-GCM (nonce + ciphertext + tag)
 *  - photo key wrapped per person with one-time X25519 + HKDF-SHA256 + AES-256-GCM
 */
(function (root) {
  'use strict';
  const enc = new TextEncoder();
  const SALT = enc.encode('evora-e2ee-v1');
  const INFO = enc.encode('share-key');
  const ITERATIONS = 200000;
  const PKCS8_X25519 = new Uint8Array([0x30, 0x2e, 0x02, 0x01, 0x00, 0x30, 0x05, 0x06, 0x03, 0x2b, 0x65, 0x6e, 0x04, 0x22, 0x04, 0x20]);

  const b64e = (u8) => {
    let s = '';
    for (let i = 0; i < u8.length; i += 0x8000) s += String.fromCharCode.apply(null, u8.subarray(i, i + 0x8000));
    return btoa(s);
  };
  const b64d = (s) => Uint8Array.from(atob(s), (c) => c.charCodeAt(0));
  const rand = (n) => crypto.getRandomValues(new Uint8Array(n));
  const aesKey = (bytes, usages) => crypto.subtle.importKey('raw', bytes, 'AES-GCM', false, usages);

  async function seal(key, data) {
    const iv = rand(12);
    const ct = new Uint8Array(await crypto.subtle.encrypt({ name: 'AES-GCM', iv }, key, data));
    const out = new Uint8Array(12 + ct.length);
    out.set(iv); out.set(ct, 12);
    return out;
  }
  async function open(key, data) {
    return new Uint8Array(await crypto.subtle.decrypt({ name: 'AES-GCM', iv: data.slice(0, 12) }, key, data.slice(12)));
  }
  async function passKey(pass, salt, usages) {
    const base = await crypto.subtle.importKey('raw', enc.encode(pass), 'PBKDF2', false, ['deriveBits']);
    const bits = await crypto.subtle.deriveBits({ name: 'PBKDF2', hash: 'SHA-256', salt, iterations: ITERATIONS }, base, 256);
    return aesKey(bits, usages);
  }
  async function wrapKeyFrom(bits, usages) {
    const hk = await crypto.subtle.importKey('raw', bits, 'HKDF', false, ['deriveKey']);
    return crypto.subtle.deriveKey({ name: 'HKDF', hash: 'SHA-256', salt: SALT, info: INFO }, hk, { name: 'AES-GCM', length: 256 }, false, usages);
  }

  /** New key pair as raw bytes (private 32, public 32). */
  async function newKeyPair() {
    const kp = await crypto.subtle.generateKey({ name: 'X25519' }, true, ['deriveBits']);
    const p8 = new Uint8Array(await crypto.subtle.exportKey('pkcs8', kp.privateKey));
    const pub = new Uint8Array(await crypto.subtle.exportKey('raw', kp.publicKey));
    return { priv: p8.slice(p8.length - 32), pub };
  }
  async function importPrivate(priv) {
    const buf = new Uint8Array(48);
    buf.set(PKCS8_X25519); buf.set(priv, 16);
    return crypto.subtle.importKey('pkcs8', buf, { name: 'X25519' }, false, ['deriveBits']);
  }

  async function wrapPrivate(priv, pass) {
    const salt = rand(16);
    const k = await passKey(pass, salt, ['encrypt']);
    return { salt: b64e(salt), wrapped: b64e(await seal(k, priv)) };
  }
  async function unwrapPrivate(pass, saltB64, wrappedB64) {
    const k = await passKey(pass, b64d(saltB64), ['decrypt']);
    return open(k, b64d(wrappedB64));
  }

  /** Lock a photo key for one person (their public key, base64). */
  async function wrapFor(photoKeyBytes, recipientPubB64) {
    const eph = await crypto.subtle.generateKey({ name: 'X25519' }, true, ['deriveBits']);
    const rp = await crypto.subtle.importKey('raw', b64d(recipientPubB64), { name: 'X25519' }, false, []);
    const bits = await crypto.subtle.deriveBits({ name: 'X25519', public: rp }, eph.privateKey, 256);
    const wk = await wrapKeyFrom(bits, ['encrypt']);
    const ephPub = new Uint8Array(await crypto.subtle.exportKey('raw', eph.publicKey));
    return { eph: b64e(ephPub), wrapped: b64e(await seal(wk, photoKeyBytes)) };
  }
  /** Open a locked photo key with my private key. Returns an AES key for decrypting photos. */
  async function unwrapShareKey(privKey, ephB64, wrappedB64) {
    const eph = await crypto.subtle.importKey('raw', b64d(ephB64), { name: 'X25519' }, false, []);
    const bits = await crypto.subtle.deriveBits({ name: 'X25519', public: eph }, privKey, 256);
    const wk = await wrapKeyFrom(bits, ['decrypt']);
    return aesKey(await open(wk, b64d(wrappedB64)), ['decrypt']);
  }

  root.EvoraCrypto = {
    b64e, b64d, rand, seal, open, newKeyPair, importPrivate, wrapPrivate, unwrapPrivate,
    wrapFor, unwrapShareKey,
    photoEncryptKey: (bytes) => aesKey(bytes, ['encrypt']),
  };
})(typeof window !== 'undefined' ? window : globalThis);
