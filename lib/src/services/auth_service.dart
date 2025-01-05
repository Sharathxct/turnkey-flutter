import '../api/turnkey_api_client.dart';

class AuthService {
  final TurnkeyApiClient _apiClient;

  AuthService({
    required String apiPublicKey,
    required String apiPrivateKey,
    required String organizationId,
  }) : _apiClient = TurnkeyApiClient(
          apiPublicKey: apiPublicKey,
          apiPrivateKey: apiPrivateKey,
          organizationId: organizationId,
        );

  /// Initiates email authentication flow
  Future<void> startEmailAuth(String email) async {
    try {
      final response = await _apiClient.initEmailAuth(email: email);
      // Store any necessary data from response if needed
      print('Email auth initiated: $response');
    } catch (e) {
      print('Failed to initiate email auth: $e');
      rethrow;
    }
  }

  /// Completes email authentication and creates sub-organization
  Future<Map<String, dynamic>> completeEmailAuthAndCreateSubOrg({
    required String email,
    required String code,
    required String userName,
  }) async {
    try {
      // First perform email authentication
      final authResponse = await _apiClient.performEmailAuth(
        email: email,
        code: code,
      );
      print('Email auth completed: $authResponse');

      // Then create sub-organization
      final subOrgResponse = await _apiClient.createSubOrganization(
        subOrgName: '${userName}\'s Organization',
        userName: userName,
        userEmail: email,
      );
      print('Sub-organization created: $subOrgResponse');

      return {
        'auth': authResponse,
        'subOrg': subOrgResponse,
      };
    } catch (e) {
      print('Failed to complete auth and create sub-org: $e');
      rethrow;
    }
  }

  void dispose() {
    _apiClient.dispose();
  }
}
