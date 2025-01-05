import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:app/models/model.dart';
import 'package:app/models/types.dart';
import 'package:bs58check/bs58check.dart' as bs58check;
import 'package:convert/convert.dart';
import 'package:flutter/foundation.dart';
import 'package:pinenacl/ed25519.dart' as pinenacl;
import 'package:pointycastle/export.dart';

class KeyPair {
  String privateKey;
  String publicKey;

  KeyPair({
    required this.privateKey,
    required this.publicKey,
  });
}

Future<String> decryptBundle(
  String credentialBundle,
  String embeddedKey,
) async {
  final isJson = credentialBundle.indexOf('{') == 0;
  late Uint8List encappedKeyBuf;
  late Uint8List ciphertextBuf;

  if (isJson) {
    final fields = jsonOf(jsonDecode(credentialBundle));
    final signedData = jsonOf(
      jsonDecode(
        utf8.decode(Uint8List.fromList(hex.decode(fields['data'] as String))),
      ),
    );

    encappedKeyBuf =
        Uint8List.fromList(hex.decode(signedData['encappedPublic'] as String));
    ciphertextBuf =
        Uint8List.fromList(hex.decode(signedData['ciphertext'] as String));
  } else {
    final bundleBytes = bs58check.decode(credentialBundle);
    encappedKeyBuf = _uncompressRawPublicKey(bundleBytes.sublist(0, 33));
    ciphertextBuf = bundleBytes.sublist(33);
  }

  final decryptedData = await _hpkeDecrypt(
    ciphertextBuf: ciphertextBuf,
    encappedKeyBuf: encappedKeyBuf,
    receiverPrivJwk: jsonOf(jsonDecode(embeddedKey)),
  );

  return isJson ? utf8.decode(decryptedData) : hex.encode(decryptedData);
}

Uint8List _uncompressRawPublicKey(Uint8List compressedKey) {
  final ecDomainParameters = ECDomainParameters('secp256r1');
  final point = ecDomainParameters.curve.decodePoint(compressedKey);

  if (point == null) {
    throw const FormatException('Invalid compressed public key');
  }

  return point.getEncoded(false);
}

Future<KeyPair> generateKeyPair() async {
  final privateKey = randomBytes(32);
  final privateKeyJwk = {
    'kty': 'EC',
    'crv': 'P-256',
    'd': hex.encode(privateKey),
    'x': '', // Placeholder, will be filled after public key is generated
    'y': '', // Placeholder, will be filled after public key is generated
  };

  final publicKeyBytes = await _p256JWKPrivateToPublic(privateKeyJwk);
  final x = publicKeyBytes.sublist(1, 33);
  final y = publicKeyBytes.sublist(33);

  privateKeyJwk['x'] = hex.encode(x);
  privateKeyJwk['y'] = hex.encode(y);

  return KeyPair(
    privateKey: jsonEncode(privateKeyJwk),
    publicKey: hex.encode(publicKeyBytes),
  );
}

Uint8List randomBytes(int length) {
  final rng = Random.secure();
  final bytes = Uint8List(length);
  for (var i = 0; i < length; i++) {
    bytes[i] = rng.nextInt(256);
  }
  return bytes;
}

Future<Uint8List> _hpkeDecrypt({
  required Uint8List ciphertextBuf,
  required Uint8List encappedKeyBuf,
  required Map<String, dynamic> receiverPrivJwk,
}) async {
  final kemContext = _DhkemP256HkdfSha256();
  final receiverPriv = await kemContext.importKey('jwk', receiverPrivJwk);

  final suite = _CipherSuite(
    kem: kemContext,
    kdf: _HkdfSha256(),
  );

  final receiverPubBuf = await _p256JWKPrivateToPublic(receiverPrivJwk);

  final recipientCtx = await suite.createRecipientContext(
    recipientKey: receiverPriv,
    enc: encappedKeyBuf,
    receiverPub: receiverPubBuf,
  );

  final aad = _additionalAssociatedData(encappedKeyBuf, receiverPubBuf);

  return await recipientCtx.open(ciphertextBuf, aad);
}

Future<Uint8List> _p256JWKPrivateToPublic(Map<String, dynamic> jwk) async {
  final ecDomainParameters = ECDomainParameters('prime256v1');
  final d = BigInt.parse(jwk['d'] as String, radix: 16);
  final privateKey = ECPrivateKey(d, ecDomainParameters);
  final Q = privateKey.parameters!.G * privateKey.d;

  return Uint8List.fromList(Q!.getEncoded(false));
}

Uint8List _additionalAssociatedData(
  Uint8List encappedKeyBuf,
  Uint8List receiverPubBuf,
) {
  final s = List<int>.from(encappedKeyBuf);
  final r = List<int>.from(receiverPubBuf);
  return Uint8List.fromList(s + r);
}

class _DhkemP256HkdfSha256 {
  Future<ECPrivateKey> importKey(
    String format,
    Map<String, dynamic> keyData,
  ) async {
    final ecDomainParameters = ECDomainParameters('prime256v1');
    final d = BigInt.parse(keyData['d'] as String, radix: 16);

    return ECPrivateKey(d, ecDomainParameters);
  }
}

class _CipherSuite {
  final _DhkemP256HkdfSha256 kem;
  final _HkdfSha256 kdf;

  _CipherSuite({
    required this.kem,
    required this.kdf,
  });

  Future<_RecipientContext> createRecipientContext({
    required ECPrivateKey recipientKey,
    required Uint8List enc,
    required Uint8List receiverPub,
  }) async {
    final ss = _deriveSharedSecret(recipientKey, enc);

    Uint8List ikm = buildLabeledIkm(labelEaePrk, ss, suiteId1);
    Uint8List info = buildLabeledInfo(
      labelSharedSecret,
      getKemContext(enc, receiverPub),
      suiteId1,
      32,
    );
    final sharedSecret = kdf.extractAndExpand(Uint8List(32), ikm, info, 32);

    ikm = buildLabeledIkm(labelSecret, Uint8List.fromList([]), suiteId2);
    info = aesKeyInfo;
    final key = kdf.extractAndExpand(sharedSecret, ikm, info, 32);

    info = ivInfo;
    final nonce = kdf.extractAndExpand(sharedSecret, ikm, info, 12);

    return _RecipientContext(key, nonce);
  }

  Uint8List getKemContext(Uint8List encappedKeyBuf, Uint8List publicKeyArray) {
    final kemContextLength = encappedKeyBuf.length + publicKeyArray.length;
    final kemContext = Uint8List(kemContextLength);

    kemContext.setAll(0, encappedKeyBuf);
    kemContext.setAll(encappedKeyBuf.length, publicKeyArray);

    return kemContext;
  }

  Uint8List buildLabeledIkm(Uint8List label, Uint8List ikm, Uint8List suiteId) {
    final combinedLength =
        hpkeVersion.length + suiteId.length + label.length + ikm.length;
    final ret = Uint8List(combinedLength);
    int offset = 0;

    ret.setAll(offset, hpkeVersion);
    offset += hpkeVersion.length;

    ret.setAll(offset, suiteId);
    offset += suiteId.length;

    ret.setAll(offset, label);
    offset += label.length;

    ret.setAll(offset, ikm);

    return ret;
  }

  Uint8List buildLabeledInfo(
    Uint8List label,
    Uint8List info,
    Uint8List suiteId,
    int len,
  ) {
    const suiteIdStartIndex = 9;
    final ret = Uint8List(
      suiteIdStartIndex + suiteId.length + label.length + info.length,
    );
    ret.setAll(
      0,
      Uint8List.fromList(
        [0, len],
      ),
    );
    ret.setAll(2, hpkeVersion);
    ret.setAll(suiteIdStartIndex, suiteId);
    ret.setAll(suiteIdStartIndex + suiteId.length, label);
    ret.setAll(suiteIdStartIndex + suiteId.length + label.length, info);
    return ret;
  }

  Uint8List _deriveSharedSecret(ECPrivateKey privateKey, Uint8List enc) {
    final ecDomainParameters = ECDomainParameters('prime256v1');
    final Q = ecDomainParameters.curve.decodePoint(enc)!;
    final sharedSecretPoint = Q * privateKey.d;
    return sharedSecretPoint!.getEncoded(false).sublist(1, 33);
  }
}

class _RecipientContext {
  final Uint8List key;
  final Uint8List nonce;

  _RecipientContext(this.key, this.nonce);

  Future<Uint8List> open(Uint8List ciphertext, Uint8List aad) async {
    final gcm = GCMBlockCipher(AESEngine())
      ..init(false, AEADParameters(KeyParameter(key), 128, nonce, aad));

    final decryptedData = Uint8List(ciphertext.length + gcm.macSize ~/ 8);

    var len =
        gcm.processBytes(ciphertext, 0, ciphertext.length, decryptedData, 0);
    len += gcm.doFinal(decryptedData, len);

    return decryptedData.sublist(0, len);
  }
}

class _HkdfSha256 {
  final hkdf = HKDFKeyDerivator(SHA256Digest());

  Uint8List extractAndExpand(
    Uint8List salt,
    Uint8List ikm,
    Uint8List info,
    int length,
  ) {
    final params = HkdfParameters(ikm, length, salt, info);
    hkdf.init(params);
    final output = Uint8List(length);
    hkdf.deriveKey(null, 0, output, 0);
    return output;
  }
}

bool isOnCurve(String chain, String publicKey) {
  switch (chain) {
    case Chain.solana:
      // Regular expression to match a base58 encoded string of 32 bytes length
      final regex = RegExp(r'^[1-9A-HJ-NP-Za-km-z]{32,44}$');

      if (!regex.hasMatch(publicKey)) {
        return false;
      }

      try {
        // Decode the base58 string to bytes
        final decoded = bs58check.base58.decode(publicKey);

        if (decoded.length != 32) {
          return false;
        }

        // Check if the public key is on the ed25519 curve
        pinenacl.PublicKey(decoded);

        return true;
      } catch (e) {
        return false;
      }
  }

  return false;
}

final suiteId1 = Uint8List.fromList([75, 69, 77, 0, 16]); //KEM suite ID
final suiteId2 =
    Uint8List.fromList([72, 80, 75, 69, 0, 16, 0, 1, 0, 2]); //HPKE suite ID
final hpkeVersion = Uint8List.fromList([72, 80, 75, 69, 45, 118, 49]); //HPKE-v1
final labelSecret = Uint8List.fromList([115, 101, 99, 114, 101, 116]); //secret
final labelEaePrk =
    Uint8List.fromList([101, 97, 101, 95, 112, 114, 107]); //eae_prk
final labelSharedSecret = Uint8List.fromList(
  [115, 104, 97, 114, 101, 100, 95, 115, 101, 99, 114, 101, 116],
); //shared_secret
final aesKeyInfo = Uint8List.fromList([
  0,
  32,
  72,
  80,
  75,
  69,
  45,
  118,
  49,
  72,
  80,
  75,
  69,
  0,
  16,
  0,
  1,
  0,
  2,
  107,
  101,
  121,
  0,
  143,
  195,
  174,
  184,
  50,
  73,
  10,
  75,
  90,
  179,
  228,
  32,
  35,
  40,
  125,
  178,
  154,
  31,
  75,
  199,
  194,
  34,
  192,
  223,
  34,
  135,
  39,
  183,
  10,
  64,
  33,
  18,
  47,
  63,
  4,
  233,
  32,
  108,
  209,
  36,
  19,
  80,
  53,
  41,
  180,
  122,
  198,
  166,
  48,
  185,
  46,
  196,
  207,
  125,
  35,
  69,
  8,
  208,
  175,
  151,
  113,
  201,
  158,
  80,
]); //key
final ivInfo = Uint8List.fromList([
  0,
  12,
  72,
  80,
  75,
  69,
  45,
  118,
  49,
  72,
  80,
  75,
  69,
  0,
  16,
  0,
  1,
  0,
  2,
  98,
  97,
  115,
  101,
  95,
  110,
  111,
  110,
  99,
  101,
  0,
  143,
  195,
  174,
  184,
  50,
  73,
  10,
  75,
  90,
  179,
  228,
  32,
  35,
  40,
  125,
  178,
  154,
  31,
  75,
  199,
  194,
  34,
  192,
  223,
  34,
  135,
  39,
  183,
  10,
  64,
  33,
  18,
  47,
  63,
  4,
  233,
  32,
  108,
  209,
  36,
  19,
  80,
  53,
  41,
  180,
  122,
  198,
  166,
  48,
  185,
  46,
  196,
  207,
  125,
  35,
  69,
  8,
  208,
  175,
  151,
  113,
  201,
  158,
  80,
]); //base_nonce
