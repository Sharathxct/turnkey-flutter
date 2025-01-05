import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:convert/convert.dart';
import 'package:pointycastle/export.dart';

class TurnkeyApiStamper {
  final String apiPublicKey;
  final String apiPrivateKey;
  final String organizationId;

  TurnkeyApiStamper({
    required this.apiPublicKey,
    required this.apiPrivateKey,
    required this.organizationId,
  });

  Map<String, String> stampRequest({
    required String body,
    String? timestamp,
  }) {
    final requestTimestamp = timestamp ?? _generateTimestamp();
    final bodyHash = _hashBody(body);
    final signature = _signRequest(bodyHash, requestTimestamp);

    return {
      'X-Turnkey-API-Public-Key': apiPublicKey,
      'X-Turnkey-Timestamp': requestTimestamp,
      'X-Turnkey-Organization': organizationId,
      'X-Turnkey-Signature': signature,
    };
  }

  String _generateTimestamp() {
    return DateTime.now().toUtc().toIso8601String();
  }

  String _hashBody(String body) {
    final bytes = utf8.encode(body);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  String _signRequest(String bodyHash, String timestamp) {
    final signatureInput = '$timestamp$bodyHash';
    final signatureBytes = utf8.encode(signatureInput);

    // Create signing key from private key
    final privateKeyBytes = base64.decode(apiPrivateKey);
    final privateKey = ECPrivateKey(
      BigInt.parse(hex.encode(privateKeyBytes), radix: 16),
      ECDomainParameters('secp256k1'),
    );

    // Sign the message
    final signer = ECDSASigner(SHA256Digest())
      ..init(true, PrivateKeyParameter<ECPrivateKey>(privateKey));

    final signature = signer
        .generateSignature(Uint8List.fromList(signatureBytes)) as ECSignature;
    final r = signature.r.toRadixString(16).padLeft(64, '0');
    final s = signature.s.toRadixString(16).padLeft(64, '0');

    return '$r$s';
  }
}
