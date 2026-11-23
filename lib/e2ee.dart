import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// End-to-end encryption for shared photos.
///
/// - Each person has an X25519 key pair. The private key never leaves the phone
///   unlocked; a copy locked with the person's passcode is kept on the server.
/// - Each encrypted share has a random 256-bit photo key. Photos (and their
///   thumbnails) are encrypted with AES-256-GCM before upload.
/// - The photo key is wrapped for every person who may open it, using a one-time
///   X25519 key, HKDF-SHA256 and AES-256-GCM.
///
/// The same steps are implemented by the website (WebCrypto), so both can open
/// the same photos.
class E2ee {
  E2ee._();

  static final X25519 _x = X25519();
  static final List<int> _salt = utf8.encode('evora-e2ee-v1');
  static final List<int> _info = utf8.encode('share-key');
  static const int _pbkdf2Iterations = 200000;

  /// Big photos are encrypted in a background isolate so the screen stays smooth.
  static const int _isolateThreshold = 150 * 1024;

  static List<int> randomBytes(int n) => SecretKeyData.random(length: n).bytes;

  static String b64(List<int> b) => base64.encode(b);
  static Uint8List unb64(String s) => Uint8List.fromList(base64.decode(s));

  // ---- key pair ---------------------------------------------------------

  static Future<({List<int> priv, List<int> pub})> newKeyPair() async {
    final kp = await _x.newKeyPair();
    final priv = await kp.extractPrivateKeyBytes();
    final pub = (await kp.extractPublicKey()).bytes;
    return (priv: priv, pub: pub);
  }

  static Future<List<int>> publicFromPrivate(List<int> priv) async {
    final kp = await _x.newKeyPairFromSeed(priv);
    return (await kp.extractPublicKey()).bytes;
  }

  // ---- passcode backup of the private key -------------------------------

  static Future<List<int>> _pbkdf2(String passcode, List<int> salt) {
    final pass = utf8.encode(passcode);
    return Isolate.run(() async {
      final key = await Pbkdf2(
        macAlgorithm: Hmac.sha256(),
        iterations: _pbkdf2Iterations,
        bits: 256,
      ).deriveKey(secretKey: SecretKey(pass), nonce: salt);
      return await key.extractBytes();
    });
  }

  static Future<({String salt, String wrapped})> wrapPrivate(
      List<int> priv, String passcode) async {
    final salt = randomBytes(16);
    final k = await _pbkdf2(passcode, salt);
    final box = await AesGcm.with256bits().encrypt(priv, secretKey: SecretKey(k));
    return (salt: b64(salt), wrapped: b64(box.concatenation()));
  }

  /// Returns the private key, or throws if the passcode is wrong.
  static Future<List<int>> unwrapPrivate(
      String passcode, String saltB64, String wrappedB64) async {
    final k = await _pbkdf2(passcode, unb64(saltB64));
    final box = SecretBox.fromConcatenation(unb64(wrappedB64),
        nonceLength: 12, macLength: 16);
    return AesGcm.with256bits().decrypt(box, secretKey: SecretKey(k));
  }

  // ---- wrapping the photo key for a person ------------------------------

  static Future<SecretKey> _wrapKey(SecretKey shared) {
    return Hkdf(hmac: Hmac.sha256(), outputLength: 32)
        .deriveKey(secretKey: shared, nonce: _salt, info: _info);
  }

  static Future<({String eph, String wrapped})> wrapFor(
      List<int> photoKey, List<int> recipientPub) async {
    final eph = await _x.newKeyPair();
    final shared = await _x.sharedSecretKey(
      keyPair: eph,
      remotePublicKey: SimplePublicKey(recipientPub, type: KeyPairType.x25519),
    );
    final wk = await _wrapKey(shared);
    final box = await AesGcm.with256bits().encrypt(photoKey, secretKey: wk);
    final ephPub = (await eph.extractPublicKey()).bytes;
    return (eph: b64(ephPub), wrapped: b64(box.concatenation()));
  }

  static Future<List<int>> unwrapFor({
    required List<int> myPriv,
    required List<int> myPub,
    required String eph,
    required String wrapped,
  }) async {
    final kp = SimpleKeyPairData(
      myPriv,
      publicKey: SimplePublicKey(myPub, type: KeyPairType.x25519),
      type: KeyPairType.x25519,
    );
    final shared = await _x.sharedSecretKey(
      keyPair: kp,
      remotePublicKey: SimplePublicKey(unb64(eph), type: KeyPairType.x25519),
    );
    final wk = await _wrapKey(shared);
    final box =
        SecretBox.fromConcatenation(unb64(wrapped), nonceLength: 12, macLength: 16);
    return AesGcm.with256bits().decrypt(box, secretKey: wk);
  }

  // ---- photos -------------------------------------------------------------

  static Future<Uint8List> _seal(Uint8List plain, List<int> key) async {
    final box =
        await AesGcm.with256bits().encrypt(plain, secretKey: SecretKey(key));
    return Uint8List.fromList(box.concatenation());
  }

  static Future<Uint8List> _open(Uint8List data, List<int> key) async {
    final box = SecretBox.fromConcatenation(data, nonceLength: 12, macLength: 16);
    final plain = await AesGcm.with256bits().decrypt(box, secretKey: SecretKey(key));
    return Uint8List.fromList(plain);
  }

  /// nonce (12) + ciphertext + tag (16)
  static Future<Uint8List> encryptPhoto(Uint8List plain, List<int> key) {
    if (plain.length < _isolateThreshold) return _seal(plain, key);
    return Isolate.run(() => _seal(plain, key));
  }

  static Future<Uint8List> decryptPhoto(Uint8List data, List<int> key) {
    if (data.length < _isolateThreshold) return _open(data, key);
    return Isolate.run(() => _open(data, key));
  }
}
