import 'package:flutter/material.dart';
import '../screens/onboarding/landing_screen.dart';
import '../screens/onboarding/email_input_screen.dart';
import '../screens/onboarding/verification_screen.dart';

class Routes {
  static const String landing = '/';
  static const String emailInput = '/email';
  static const String verification = '/verification';

  static Route<dynamic> generateRoute(RouteSettings settings) {
    try {
      switch (settings.name) {
        case landing:
          return MaterialPageRoute(
            builder: (_) => const LandingScreen(),
            settings: settings,
          );

        case emailInput:
          final args = settings.arguments as EmailInputScreenArgs;
          return MaterialPageRoute(
            builder: (_) => EmailInputScreen(
              isSignUp: args.isSignUp,
            ),
            settings: settings,
          );

        case verification:
          final args = settings.arguments as VerificationScreenArgs;
          return MaterialPageRoute(
            builder: (_) => VerificationScreen(
              email: args.email,
              isSignUp: args.isSignUp,
            ),
            settings: settings,
          );

        default:
          return MaterialPageRoute(
            builder: (_) => Scaffold(
              body: Center(
                child: Text('No route defined for ${settings.name}'),
              ),
            ),
          );
      }
    } catch (e) {
      debugPrint('Error in route generation: $e');
      return MaterialPageRoute(
        builder: (_) => Scaffold(
          body: Center(
            child: Text('Error in navigation: $e'),
          ),
        ),
      );
    }
  }
}

// Route Arguments
class EmailInputScreenArgs {
  final bool isSignUp;

  EmailInputScreenArgs({required this.isSignUp});
}

class VerificationScreenArgs {
  final String email;
  final bool isSignUp;

  VerificationScreenArgs({
    required this.email,
    required this.isSignUp,
  });
}
