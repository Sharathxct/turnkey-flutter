import 'dart:convert';
import 'package:http/http.dart' as http;
import '../stamper/api_stamper.dart';

class TurnkeyApiClient {
  static const String _baseUrl = 'https://api.turnkey.com';
  final TurnkeyApiStamper _stamper;
  final http.Client _httpClient;

  TurnkeyApiClient({
    required String apiPublicKey,
    required String apiPrivateKey,
    required String organizationId,
    http.Client? httpClient,
  })  : _stamper = TurnkeyApiStamper(
          apiPublicKey: apiPublicKey,
          apiPrivateKey: apiPrivateKey,
          organizationId: organizationId,
        ),
        _httpClient = httpClient ?? http.Client();

  Future<Map<String, dynamic>> initEmailAuth({
    required String email,
  }) async {
    const path = '/public/v1/submit/init_email_recovery';
    final timestamp = DateTime.now().millisecondsSinceEpoch.toString();

    final body = jsonEncode({
      'type': 'ACTIVITY_TYPE_INIT_EMAIL_RECOVERY_V2',
      'timestampMs': timestamp,
      'organizationId': _stamper.organizationId,
      'parameters': {
        'email': email,
      },
    });

    return _post(path, body);
  }

  Future<Map<String, dynamic>> performEmailAuth({
    required String email,
    required String code,
  }) async {
    const path = '/public/v1/submit/perform_email_auth';
    final timestamp = DateTime.now().millisecondsSinceEpoch.toString();

    final body = jsonEncode({
      'type': 'ACTIVITY_TYPE_PERFORM_EMAIL_AUTH_V2',
      'timestampMs': timestamp,
      'organizationId': _stamper.organizationId,
      'parameters': {
        'email': email,
        'code': code,
      },
    });

    return _post(path, body);
  }

  Future<Map<String, dynamic>> createSubOrganization({
    required String subOrgName,
    required String userName,
    required String userEmail,
  }) async {
    const path = '/public/v1/submit/create_sub_organization';
    final timestamp = DateTime.now().millisecondsSinceEpoch.toString();

    final body = jsonEncode({
      'type': 'ACTIVITY_TYPE_CREATE_SUB_ORGANIZATION_V7',
      'timestampMs': timestamp,
      'organizationId': _stamper.organizationId,
      'parameters': {
        'subOrganizationName': subOrgName,
        'rootUsers': [
          {
            'userName': userName,
            'userEmail': userEmail,
          }
        ],
        'rootQuorumThreshold': 1,
      },
    });

    return _post(path, body);
  }

  Future<Map<String, dynamic>> _post(String path, String body) async {
    final headers = {
      'Content-Type': 'application/json',
      ..._stamper.stampRequest(body: body),
    };

    final response = await _httpClient.post(
      Uri.parse('$_baseUrl$path'),
      headers: headers,
      body: body,
    );

    if (response.statusCode != 200) {
      throw TurnkeyApiException(
        'API request failed with status ${response.statusCode}',
        response.statusCode,
        response.body,
      );
    }

    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  void dispose() {
    _httpClient.close();
  }
}

class TurnkeyApiException implements Exception {
  final String message;
  final int statusCode;
  final String responseBody;

  TurnkeyApiException(this.message, this.statusCode, this.responseBody);

  @override
  String toString() => 'TurnkeyApiException: $message';
}
