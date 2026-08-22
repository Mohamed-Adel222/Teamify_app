import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/routes.dart';
import '../../core/session/session_controller.dart';

/// Legacy route kept so old bookmarks still land on the regular signup form.
/// Email and GitHub/Google sign-up share `/signup-freelancer` or
/// `/signup-student`. The freelancer page only asks for name, username,
/// and email; password is collected on new email sign-up only.
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
      final route =
          user?.isStudent == true ? R.signupStudent : R.signupFreelancer;
      Navigator.pushNamedAndRemoveUntil(
        context,
        route,
        (_) => false,
        arguments: const {'oauthSetup': true},
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
