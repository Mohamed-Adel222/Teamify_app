import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/routes.dart';
import '../../core/session/session_controller.dart';

/// Legacy route kept so old bookmarks still land on the right completion page.
/// Google/GitHub freelancers go to `/complete-freelancer-profile`.
/// Students still use `/signup-student`.
class OAuthProfileSetupScreen extends StatefulWidget {
  const OAuthProfileSetupScreen({super.key});

  @override
  State<OAuthProfileSetupScreen> createState() =>
      _OAuthProfileSetupScreenState();
}

class _OAuthProfileSetupScreenState extends State<OAuthProfileSetupScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final user = context.read<SessionController>().currentUser;
      final route = user?.isStudent == true
          ? R.signupStudent
          : R.completeFreelancerProfile;
      Navigator.pushNamedAndRemoveUntil(
        context,
        route,
        (_) => false,
        arguments: user?.isStudent == true
            ? const {'oauthSetup': true}
            : null,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Colors.white,
      body: Center(child: CircularProgressIndicator()),
    );
  }
}
