import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/config/oauth_config.dart';
import '../../core/cache/cache_manager.dart';
import '../../core/theme.dart';
import '../../core/routes.dart';
import '../../core/network/api_exception.dart';
import '../../core/network/api_result.dart';
import '../../core/session/session_controller.dart';
import '../../services/app_services.dart';
import '../../widgets/widgets.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../config/app_config.dart';
import '../../data/models/models.dart';
import '../../data/models/university_option_model.dart';
import '../../widgets/university_selector_widgets.dart';
import '../../data/registration_options.dart';
import '../../core/localization/app_localizations.dart';

// ── Routing Logic ─────────────────────────────────────────────────────────────
Future<void> _navigateToCorrectHome(BuildContext context, String role,
    {String? email, String? name, bool isNew = false}) async {
  if (role == 'Admin') {
    Navigator.pushNamedAndRemoveUntil(context, R.adminHome, (_) => false);
    return;
  }

  bool hasData = false;
  String displayName = name ?? 'User';
  final services = context.read<AppServices>();
  final session = context.read<SessionController>();

  if (isNew) {
    try {
      final projects =
          await services.projects.listProjects(forceRefresh: true).unwrap();
      hasData = projects.isNotEmpty;
    } catch (_) {
      hasData = false;
    }
    displayName = session.currentUser?.displayName ??
        session.currentUser?.fullName ??
        displayName;
  } else if (email != null && email.trim().isNotEmpty ||
      name != null && name.trim().isNotEmpty) {
    try {
      final projects =
          await services.projects.listProjects(forceRefresh: true).unwrap();
      hasData = projects.isNotEmpty;
    } catch (_) {
      hasData = false;
    }
  }

  if (!context.mounted) return;
  final shouldShowEmptyHome = isNew && !hasData;

  debugPrint('--- AUTH NAVIGATION ---');
  debugPrint('Role: $role, isNew: $isNew, hasData: $hasData');

  if (shouldShowEmptyHome) {
    Navigator.pushNamedAndRemoveUntil(context, R.newUserHome, (_) => false,
        arguments: {'role': role, 'name': displayName});
  } else {
    Navigator.pushNamedAndRemoveUntil(context,
        role == 'Student' ? R.studentHome : R.freelancerHome, (_) => false);
  }
}

String _homeRouteForSession(SessionController session) {
  final user = session.currentUser;
  if (user == null) return R.roleSelection;
  if (user.isAdmin) {
    return R.adminHome;
  }
  if (user.isStudent) return R.studentHome;
  return R.freelancerHome;
}

void _navigateFromSession(BuildContext context, {bool isNew = false}) {
  final session = context.read<SessionController>();
  if (session.isPendingApproval) {
    Navigator.pushNamedAndRemoveUntil(context, R.newUserHome, (_) => false,
        arguments: {
          'role': session.currentUser?.displayRole ?? 'User',
          'name': session.currentUser?.displayName ?? 'User',
          'pendingApproval': true,
        });
    return;
  }

  // OAuth (Google/GitHub) and any incomplete freelancer must finish profile
  // completion before they can reach the app. Students keep their own form.
  final user = session.currentUser;
  final isGuest =
      (user?.systemRole ?? user?.role ?? '').toLowerCase() == 'guest';
  if (user != null && !user.isAdmin && !isGuest && user.needsProfileSetup) {
    _navigateToIncompleteProfile(context, user);
    return;
  }

  Navigator.pushNamedAndRemoveUntil(
      context, _homeRouteForSession(session), (_) => false);
}

void _showAuthError(BuildContext context, Object error) {
  final String message;
  if (error is ApiException) {
    message = error.message;
  } else if (error is String && error.trim().isNotEmpty) {
    message = error;
  } else if (error is Exception || error is Error) {
    message = error.toString().replaceFirst('Exception: ', '');
  } else {
    message = 'Something went wrong. Please try again.';
  }
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

void _navigateFromSessionAfterLogin(BuildContext context,
    {bool isNew = false}) {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!context.mounted) return;
    try {
      _navigateFromSession(context, isNew: isNew);
    } catch (error, stack) {
      debugPrint('Auth navigation failed: $error\n$stack');
    }
  });
}

void _navigateAfterOAuth(BuildContext context) {
  final session = context.read<SessionController>();
  final user = session.currentUser;
  if (user?.needsProfileSetup ?? false) {
    _navigateToIncompleteProfile(context, user);
    return;
  }
  _navigateFromSession(context);
}

/// Public wrapper used after freelancer profile completion is saved.
void navigateAfterAuth(BuildContext context, {bool isNew = false}) {
  _navigateFromSession(context, isNew: isNew);
}

void _navigateToIncompleteProfile(BuildContext context, ApiUser? user) {
  if (user?.isStudent == true) {
    Navigator.pushNamedAndRemoveUntil(
      context,
      R.signupStudent,
      (_) => false,
      arguments: const {'oauthSetup': true},
    );
    return;
  }
  Navigator.pushNamedAndRemoveUntil(
    context,
    R.completeFreelancerProfile,
    (_) => false,
  );
}

bool _isAuthenticatedSignup(BuildContext context) {
  final session = context.read<SessionController>();
  final user = session.currentUser;
  return user != null &&
      (session.isAuthenticated || session.isPendingApproval) &&
      !user.isAdmin;
}

Future<void> _startGoogleOAuth(BuildContext context, String role) async {
  try {
    final cache = context.read<CacheManager>();
    await cache.putMap('auth', 'google_oauth', {
      'selected_role': role,
      'redirect_uri': OAuthConfig.redirectUri(),
    });
  } catch (_) {}

  final nonce = DateTime.now().millisecondsSinceEpoch.toString();
  final url = OAuthConfig.googleAuthorizeUri(nonce: nonce);
  if (await canLaunchUrl(url)) {
    await launchUrl(url, webOnlyWindowName: '_self');
  }
}

Future<void> _startGithubOAuth(BuildContext context, String role) async {
  try {
    final cache = context.read<CacheManager>();
    final redirectUri = OAuthConfig.redirectUri();
    await cache.putMap('auth', 'github_oauth', {
      'selected_role': role,
      'redirect_uri': redirectUri,
    });
  } catch (_) {}

  final url = OAuthConfig.githubAuthorizeUri();
  if (await canLaunchUrl(url)) {
    await launchUrl(url, webOnlyWindowName: '_self');
  }
}

Widget _socialImageBtn(String assetPath, {VoidCallback? onTap}) {
  return GestureDetector(
    onTap: onTap,
    child: Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
          shape: BoxShape.circle, border: Border.all(color: AppColors.border)),
      child: Center(
          child: Padding(
        padding: const EdgeInsets.all(10.0),
        child: Image.asset(assetPath, fit: BoxFit.contain),
      )),
    ),
  );
}

Widget _signupSocialActions(BuildContext context, String role) {
  return Column(
    children: [
      const SizedBox(height: 24),
      const Row(children: [
        Expanded(child: Divider()),
        Padding(
            padding: EdgeInsets.symmetric(horizontal: 12),
            child: Text('Or',
                style: TextStyle(color: AppColors.textSecondary))),
        Expanded(child: Divider()),
      ]),
      const SizedBox(height: 16),
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        _socialImageBtn('assets/images/google_logo.png',
            onTap: () => _startGoogleOAuth(context, role)),
        const SizedBox(width: 16),
        _socialImageBtn('assets/images/github_logo.png',
            onTap: () => _startGithubOAuth(context, role)),
      ]),
    ],
  );
}

// ── Teamify Logo Widget ───────────────────────────────────────────────────────
class _TeamifyLogo extends StatelessWidget {
  final double size;
  const _TeamifyLogo({this.size = 80});

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/images/logo.png',
      width: size,
      height: size,
      fit: BoxFit.contain,
    );
  }
}

// ── Splash ────────────────────────────────────────────────────────────────────
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  String? _statusMessage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _boot());
  }

  Future<void> _boot() async {
    final cache = context.read<CacheManager>();

    // OAuth params captured from the browser URL in main() before routing.
    final pending = await cache.getMap(
      'auth',
      'pending_oauth',
      maxAge: const Duration(minutes: 10),
    );
    if (pending != null) {
      await cache.invalidate('auth', 'pending_oauth');
      final provider = pending['provider']?.toString() ?? '';
      if (provider == 'google') {
        final oauthError = pending['error']?.toString();
        if (oauthError != null && oauthError.isNotEmpty) {
          if (!mounted) return;
          _showAuthError(
            context,
            pending['error_description']?.toString().isNotEmpty == true
                ? pending['error_description'].toString()
                : 'Google sign-in was cancelled.',
          );
          Navigator.pushReplacementNamed(context, R.login);
          return;
        }
        final idToken = pending['id_token']?.toString();
        if (idToken != null && idToken.isNotEmpty) {
          await _handleGoogleOAuthReturn(idToken);
          return;
        }
      }
      if (provider == 'github') {
        final code = pending['code']?.toString();
        if (code != null && code.isNotEmpty) {
          await _handleGithubOAuthReturn(code);
          return;
        }
      }
    }

    // Fallback: read OAuth params directly from URL (non-web / legacy).
    final fragment = Uri.base.fragment;
    if (fragment.isNotEmpty) {
      final params = Uri.splitQueryString(fragment);
      final idToken = params['id_token'];
      if (idToken != null && idToken.isNotEmpty) {
        await _handleGoogleOAuthReturn(idToken);
        return;
      }
    }

    // Detect GitHub OAuth redirect (code arrives as a query param).
    final code = Uri.base.queryParameters['code'];
    if (code != null && code.isNotEmpty) {
      await _handleGithubOAuthReturn(code);
      return;
    }

    Future.delayed(const Duration(seconds: 2), _routeAfterSessionRestore);
  }

  Future<void> _handleGoogleOAuthReturn(String idToken) async {
    if (!mounted) return;
    setState(() => _statusMessage = 'Signing in with Google…');
    final services = context.read<AppServices>();
    try {
      final cache = context.read<CacheManager>();
      final saved = await cache.getMap('auth', 'google_oauth',
          maxAge: const Duration(hours: 1));
      final legacyRole = await cache.getMap('auth', 'google_role',
          maxAge: const Duration(hours: 1));
      final role = saved?['selected_role']?.toString() ??
          legacyRole?['selected_role']?.toString() ??
          'Freelancer';

      final res = await services.auth
          .loginWithGoogle(idToken, userType: role.toLowerCase());
      if (!mounted) return;
      res.when(
        success: (user) {
          if (user == null) {
            _showAuthError(
              context,
              'Sign-in succeeded but your session could not start. Please try again.',
            );
            Navigator.pushReplacementNamed(context, R.login);
            return;
          }
          _navigateAfterOAuth(context);
        },
        failure: (e) {
          _showAuthError(context, e);
          Navigator.pushReplacementNamed(context, R.login);
        },
      );
    } catch (e) {
      if (!mounted) return;
      _showAuthError(context, 'Google sign-in failed: $e');
      Navigator.pushReplacementNamed(context, R.login);
    }
  }

  Future<void> _handleGithubOAuthReturn(String code) async {
    if (!mounted) return;
    setState(() => _statusMessage = 'Signing in with GitHub…');
    final services = context.read<AppServices>();
    try {
      final cache = context.read<CacheManager>();
      final saved = await cache.getMap('auth', 'github_oauth',
          maxAge: const Duration(hours: 1));
      final legacyRole = await cache.getMap('auth', 'github_role',
          maxAge: const Duration(hours: 1));
      final role = saved?['selected_role']?.toString() ??
          legacyRole?['selected_role']?.toString() ??
          'Freelancer';
      final redirectUri =
          saved?['redirect_uri']?.toString() ?? OAuthConfig.redirectUri();

      final res = await services.auth.loginWithGithub(
        code,
        userType: role.toLowerCase(),
        redirectUri: redirectUri,
      );
      if (!mounted) return;
      res.when(
        success: (user) {
          if (user == null) {
            _showAuthError(
              context,
              'Sign-in succeeded but your session could not start. Please try again.',
            );
            Navigator.pushReplacementNamed(context, R.login);
            return;
          }
          _navigateAfterOAuth(context);
        },
        failure: (e) {
          _showAuthError(context, e);
          Navigator.pushReplacementNamed(context, R.login);
        },
      );
    } catch (e) {
      if (!mounted) return;
      _showAuthError(context, 'GitHub sign-in failed: $e');
      Navigator.pushReplacementNamed(context, R.login);
    }
  }

  void _routeAfterSessionRestore() {
    if (!mounted) return;
    final session = context.read<SessionController>();
    if (session.status == SessionStatus.unknown) {
      Future.delayed(
          const Duration(milliseconds: 300), _routeAfterSessionRestore);
      return;
    }
    if (session.isAuthenticated || session.isPendingApproval) {
      _navigateFromSession(context);
    } else {
      Navigator.pushReplacementNamed(context, R.onboarding);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          const _TeamifyLogo(size: 150),
          const SizedBox(height: 16),
          const Text(
            'Teamify',
            style: TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1A3A6B),
              letterSpacing: 1.0,
            ),
          ),
          if (_statusMessage != null) ...[
            const SizedBox(height: 24),
            Text(
              _statusMessage!,
              style:
                  const TextStyle(color: AppColors.textSecondary, fontSize: 14),
            ),
            const SizedBox(height: 12),
            const CircularProgressIndicator(strokeWidth: 2),
          ],
        ]),
      ),
    );
  }
}

// ── Onboarding ────────────────────────────────────────────────────────────────
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});
  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _controller = PageController();
  int _page = 0;

  final _pages = [
    _OnboardData(
      emoji: '💼',
      illustration: _IllustrationWork(),
      text: '"Work smarter together with\nAI-powered task allocation."',
      isLast: false,
    ),
    _OnboardData(
      emoji: '🔔',
      illustration: _IllustrationAlert(),
      text: '"Stay ahead — AI alerts you\nwhen tasks are at risk of\ndelay."',
      isLast: false,
    ),
    _OnboardData(
      emoji: '🔒',
      illustration: _IllustrationSecure(),
      text:
          '"Communicate safely with\nend-to-end encryption and\nsecure data protection."',
      isLast: true,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(children: [
          Align(
            alignment: Alignment.topRight,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: GestureDetector(
                onTap: () =>
                    Navigator.pushReplacementNamed(context, R.roleSelection),
                child: const Text('Skip',
                    style: TextStyle(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w600,
                        fontSize: 16)),
              ),
            ),
          ),
          Expanded(
            child: PageView.builder(
              controller: _controller,
              onPageChanged: (i) => setState(() => _page = i),
              itemCount: _pages.length,
              itemBuilder: (_, i) => _buildPage(_pages[i]),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(24),
            child: Column(children: [
              if (_pages[_page].isLast)
                TButton(
                  label: 'Get Started',
                  onTap: () =>
                      Navigator.pushReplacementNamed(context, R.roleSelection),
                )
              else
                const SizedBox.shrink(),
              const SizedBox(height: 16),
              Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(
                      _pages.length,
                      (i) => Container(
                            width: i == _page ? 20 : 8,
                            height: 8,
                            margin: const EdgeInsets.only(right: 6),
                            decoration: BoxDecoration(
                                color: i == _page
                                    ? AppColors.primary
                                    : AppColors.border,
                                borderRadius: BorderRadius.circular(4)),
                          ))),
              const SizedBox(height: 8),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _buildPage(_OnboardData d) {
    return Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      SizedBox(height: 240, child: d.illustration),
      const SizedBox(height: 32),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Text(d.text,
            textAlign: TextAlign.center,
            style: const TextStyle(
                fontSize: 18,
                color: AppColors.textPrimary,
                height: 1.5,
                fontStyle: FontStyle.italic)),
      ),
    ]);
  }
}

class _OnboardData {
  final String emoji, text;
  final Widget illustration;
  final bool isLast;
  const _OnboardData(
      {required this.emoji,
      required this.illustration,
      required this.text,
      required this.isLast});
}

class _IllustrationWork extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/images/onboarding1.png',
      width: 300,
      height: 220,
      fit: BoxFit.contain,
    );
  }
}

class _IllustrationAlert extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/images/onboarding2.png',
      width: 300,
      height: 220,
      fit: BoxFit.contain,
    );
  }
}

class _IllustrationSecure extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/images/onboarding3.png',
      width: 300,
      height: 220,
      fit: BoxFit.contain,
    );
  }
}

// ── Role Selection ────────────────────────────────────────────────────────────
class RoleSelectionScreen extends StatefulWidget {
  const RoleSelectionScreen({super.key});
  @override
  State<RoleSelectionScreen> createState() => _RoleSelectionScreenState();
}

class _RoleSelectionScreenState extends State<RoleSelectionScreen> {
  String _selected = 'Freelancer';

  final _roles = [
    {
      'id': 'Freelancer',
      'icon': Icons.laptop_outlined,
      'title': 'Freelancer',
      'sub': 'Tell us more about your professional background.'
    },
    {
      'id': 'Student',
      'icon': Icons.school_outlined,
      'title': 'Student',
      'sub': 'Help us connect you with the right team.'
    },
    {
      'id': 'Admin',
      'icon': Icons.admin_panel_settings_outlined,
      'title': 'Admin',
      'sub': 'Manage Teamify with full platform access.'
    },
  ];

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    String roleTitle(String id) {
      if (id == 'Freelancer') {
        return loc?.translate('role_freelancer') ?? 'Freelancer';
      }
      if (id == 'Student') {
        return loc?.translate('role_student') ?? 'Student';
      }
      return loc?.translate('role_admin') ?? 'Admin';
    }

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Column(children: [
            const SizedBox(height: 20),
            const _TeamifyLogo(size: 120),
            const SizedBox(height: 28),
            Text(loc?.translate('choose_role') ?? 'Choose Your Role:',
                style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primaryDark)),
            const SizedBox(height: 8),
            const Text('This helps us personalize your experience',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 14)),
            const SizedBox(height: 32),
            ...(_roles.map((r) {
              final sel = _selected == r['id'];
              final title = roleTitle(r['id'] as String);
              return GestureDetector(
                onTap: () => setState(() => _selected = r['id'] as String),
                child: Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: sel ? AppColors.primary : AppColors.border,
                        width: sel ? 2 : 1),
                  ),
                  child: Row(children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(8)),
                      child: Icon(r['icon'] as IconData,
                          color: AppColors.primary, size: 22),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                          Text(title,
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.textPrimary,
                                  fontSize: 15)),
                          Text(r['sub'] as String,
                              style: const TextStyle(
                                  fontSize: 12,
                                  color: AppColors.textSecondary)),
                        ])),
                  ]),
                ),
              );
            })),
            const Spacer(),
            TButton(
              label: loc?.translate('continue') ?? 'Continue',
              onTap: () {
                if (AppConfig.isDemoMode) {
                  if (_selected == 'Admin') {
                    Navigator.pushNamed(context, R.signupAdmin);
                  } else if (_selected == 'Student') {
                    Navigator.pushNamed(context, R.signupStudent);
                  } else {
                    Navigator.pushNamed(context, R.signupFreelancer);
                  }
                  return;
                }
                if (_selected == 'Admin') {
                  Navigator.pushNamed(context, R.login, arguments: 'Admin');
                } else if (_selected == 'Student') {
                  Navigator.pushNamed(context, R.login, arguments: 'Student');
                } else {
                  Navigator.pushNamed(context, R.login,
                      arguments: 'Freelancer');
                }
              },
            ),
            const SizedBox(height: 8),
          ]),
        ),
      ),
    );
  }
}

// ── Sign In ───────────────────────────────────────────────────────────────────
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _obscure = true;
  bool _rememberMe = false;
  bool _loading = false;
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkGithubCode();
      _checkGoogleToken();
    });
  }

  // SplashScreen now handles the OAuth redirect at startup.
  // These checks are kept as a fallback only for cases where LoginScreen
  // is visited directly while an OAuth token is already in the URL.
  void _checkGoogleToken() async {
    final fragment = Uri.base.fragment;
    if (fragment.isEmpty) return;
    final params = Uri.splitQueryString(fragment);
    final idToken = params['id_token'];
    if (idToken == null || idToken.isEmpty) return;
    // Already handled by SplashScreen — do nothing.
  }

  void _checkGithubCode() async {
    final code = Uri.base.queryParameters['code'];
    if (code == null || code.isEmpty) return;
    // Already handled by SplashScreen — do nothing.
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _submitLogin() async {
    if (_loading) return;
    setState(() => _loading = true);
    final session = context.read<SessionController>();

    if (AppConfig.isDemoMode) {
      await Future.delayed(const Duration(milliseconds: 300));
      if (!mounted) return;
      final role =
          ModalRoute.of(context)?.settings.arguments as String? ?? 'Freelancer';
      final email = _emailCtrl.text.trim();
      final username = email.isNotEmpty && email.contains('@')
          ? email.split('@').first
          : (email.isNotEmpty ? email : 'demo_user');
      final mockUser = ApiUser(
        id: 'demo_user_${DateTime.now().millisecondsSinceEpoch}',
        displayName: username,
        fullName: username,
        email: email.isNotEmpty ? email : 'demo@example.com',
        role: role.toLowerCase() == 'admin' ? 'admin' : 'member',
        systemRole: role.toLowerCase() == 'admin' ? 'admin' : '',
        userType: role.toLowerCase(),
      );
      session.setCurrentUser(mockUser);
      _navigateFromSessionAfterLogin(context);
      if (mounted) setState(() => _loading = false);
      return;
    }

    final auth = context.read<AppServices>().auth;
    final result = await auth.login(
      email: _emailCtrl.text.trim(),
      password: _passwordCtrl.text,
    );
    if (!mounted) return;

    if (result.isSuccess) {
      if (session.isAuthenticated || session.isPendingApproval) {
        _navigateFromSessionAfterLogin(context);
      } else {
        _showAuthError(context, 'Login failed. Please check your credentials.');
      }
      setState(() => _loading = false);
      return;
    }

    // Session may still be valid if tokens were saved before a follow-up error.
    if (session.isAuthenticated || session.isPendingApproval) {
      setState(() => _loading = false);
      _navigateFromSessionAfterLogin(context);
      return;
    }

    setState(() => _loading = false);
    final err = result.error?.trim();
    _showAuthError(
      context,
      (err != null && err.isNotEmpty)
          ? err
          : 'Login failed. Please check your credentials.',
    );
  }

  Future<void> _handleGoogleLogin(String role) =>
      _startGoogleOAuth(context, role);

  Future<void> _handleGithubLogin(String role) =>
      _startGithubOAuth(context, role);

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final role =
        ModalRoute.of(context)?.settings.arguments as String? ?? 'Freelancer';
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const SizedBox(height: 16),
            const Center(child: _TeamifyLogo(size: 120)),
            const SizedBox(height: 32),
            Text(loc?.translate('email') ?? 'Email Address',
                style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                    fontSize: 15)),
            const SizedBox(height: 8),
            _field(
                hint: 'example562@gmail.com',
                prefix: Icons.email_outlined,
                controller: _emailCtrl),
            const SizedBox(height: 16),
            Text(loc?.translate('password') ?? 'Password',
                style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                    fontSize: 15)),
            const SizedBox(height: 8),
            TextField(
              controller: _passwordCtrl,
              obscureText: _obscure,
              decoration: InputDecoration(
                hintText: '••••••••••••••••••••',
                hintStyle: const TextStyle(color: AppColors.textHint),
                suffixIcon: IconButton(
                    icon: Icon(
                        _obscure
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                        color: AppColors.textSecondary),
                    onPressed: () => setState(() => _obscure = !_obscure)),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: AppColors.border)),
                enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: AppColors.border)),
                focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: AppColors.primary)),
              ),
            ),
            const SizedBox(height: 12),
            Row(children: [
              GestureDetector(
                onTap: () => setState(() => _rememberMe = !_rememberMe),
                child: Row(children: [
                  Container(
                      width: 18,
                      height: 18,
                      decoration: BoxDecoration(
                          border: Border.all(color: AppColors.border),
                          borderRadius: BorderRadius.circular(3)),
                      child: _rememberMe
                          ? const Icon(Icons.check,
                              size: 12, color: AppColors.primary)
                          : null),
                  const SizedBox(width: 8),
                  const Text('Remember me',
                      style: TextStyle(
                          fontSize: 13, color: AppColors.textSecondary)),
                ]),
              ),
              const Spacer(),
              GestureDetector(
                onTap: () => Navigator.pushNamed(context, R.forgotPassword),
                child: Text(
                    loc?.translate('forgot_password') ?? 'Forgot Password?',
                    style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.primary,
                        fontWeight: FontWeight.w600)),
              ),
            ]),
            const SizedBox(height: 24),
            TButton(
              label: _loading
                  ? (loc?.translate('saving') ?? 'Signing in...')
                  : (loc?.translate('sign_in') ?? 'Sign In'),
              onTap: _loading ? null : _submitLogin,
            ),
            const SizedBox(height: 24),
            const Row(children: [
              Expanded(child: Divider()),
              Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12),
                  child: Text('Or',
                      style: TextStyle(color: AppColors.textSecondary))),
              Expanded(child: Divider()),
            ]),
            const SizedBox(height: 16),
            const SizedBox(height: 16),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              _socialImageBtn('assets/images/google_logo.png',
                  onTap: () => _handleGoogleLogin(role)),
              const SizedBox(width: 16),
              _socialImageBtn('assets/images/github_logo.png',
                  onTap: () => _handleGithubLogin(role)),
            ]),
            const SizedBox(height: 20),
            Center(
                child: GestureDetector(
              onTap: () {
                if (role == 'Admin') {
                  Navigator.pushNamed(context, R.signupAdmin);
                } else if (role == 'Student') {
                  Navigator.pushNamed(context, R.signupStudent);
                } else {
                  Navigator.pushNamed(context, R.signupFreelancer);
                }
              },
              child: RichText(
                  text: const TextSpan(
                text: "Don't have an account? ",
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
                children: [
                  TextSpan(
                    text: 'Sign up',
                    style: TextStyle(
                        color: AppColors.primary, fontWeight: FontWeight.bold),
                  ),
                ],
              )),
            )),
          ]),
        ),
      ),
    );
  }
}

Widget _field(
    {required String hint,
    IconData? prefix,
    bool obscure = false,
    bool readOnly = false,
    TextEditingController? controller}) {
  return TextField(
    controller: controller,
    obscureText: obscure,
    readOnly: readOnly,
    decoration: InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: AppColors.textHint),
      prefixIcon: prefix != null
          ? Icon(prefix, color: AppColors.textSecondary, size: 20)
          : null,
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.border)),
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.border)),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.primary)),
    ),
  );
}

// ── Admin Signup ──────────────────────────────────────────────────────────────
class AdminSignupScreen extends StatefulWidget {
  const AdminSignupScreen({super.key});
  @override
  State<AdminSignupScreen> createState() => _AdminSignupScreenState();
}

class _AdminSignupScreenState extends State<AdminSignupScreen> {
  bool _alerts = false;
  bool _twoFA = false;
  bool _loading = false;
  String? _usernameError;
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _usernameCtrl = TextEditingController();

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _usernameCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_loading) return;
    // Validate username first
    final username = _usernameCtrl.text.trim();
    final usernameErr = RegistrationOptions.validateUsername(username);
    if (usernameErr != null) {
      setState(() => _usernameError = usernameErr);
      return;
    }
    if (AppConfig.isDemoMode &&
        RegistrationOptions.isDemoUsernameTaken(username)) {
      setState(() => _usernameError = 'Username is already taken.');
      return;
    }
    setState(() {
      _loading = true;
      _usernameError = null;
    });
    try {
      if (AppConfig.isDemoMode) {
        await Future.delayed(const Duration(milliseconds: 300));
        if (!mounted) return;
        final mockUser = ApiUser(
          id: 'demo_admin_${DateTime.now().millisecondsSinceEpoch}',
          displayName: username,
          fullName: _nameCtrl.text.trim().isNotEmpty
              ? _nameCtrl.text.trim()
              : username,
          email: _emailCtrl.text.trim(),
          role: 'admin',
          systemRole: 'admin',
          userType: 'admin',
        );
        context.read<SessionController>().setCurrentUser(mockUser);
        Navigator.pushNamedAndRemoveUntil(context, R.adminHome, (_) => false);
        return;
      }
      await context.read<SessionController>().register(
        fullName: _nameCtrl.text.trim(),
        email: _emailCtrl.text.trim(),
        password: _passwordCtrl.text,
        role: 'member',
        userType: 'admin',
        extra: {'username': username},
      );
      if (!mounted) return;
      _navigateFromSession(context, isNew: true);
    } catch (error) {
      if (mounted) _showAuthError(context, error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Center(child: _TeamifyLogo(size: 120)),
            const SizedBox(height: 16),
            const Center(
                child: Text('Set Up Your Admin Workspace',
                    style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: AppColors.primaryDark))),
            const Center(
                child: Text('Manage your team, security, and system settings',
                    style:
                        TextStyle(color: AppColors.textSecondary, fontSize: 13),
                    textAlign: TextAlign.center)),
            const SizedBox(height: 28),
            const Text('Full Name',
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                    fontSize: 15)),
            const SizedBox(height: 8),
            _field(hint: 'example', controller: _nameCtrl),
            const SizedBox(height: 16),
            const Text('Username',
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                    fontSize: 15)),
            const SizedBox(height: 8),
            _field(
                hint: 'e.g. admin_john',
                prefix: Icons.alternate_email,
                controller: _usernameCtrl),
            if (_usernameError != null) ...[
              const SizedBox(height: 4),
              Text(_usernameError!,
                  style: const TextStyle(color: AppColors.error, fontSize: 12)),
            ],
            const SizedBox(height: 16),
            const Text('Email',
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                    fontSize: 15)),
            const SizedBox(height: 8),
            _field(
                hint: 'example562@gmail.com',
                prefix: Icons.email_outlined,
                controller: _emailCtrl),
            const SizedBox(height: 16),
            const Text('Password',
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                    fontSize: 15)),
            const SizedBox(height: 8),
            _field(
                hint: 'Password123',
                prefix: Icons.lock_outline,
                obscure: true,
                controller: _passwordCtrl),
            const SizedBox(height: 20),
            const Text('Security Settings',
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                    fontSize: 16)),
            const SizedBox(height: 12),
            _checkRow('Enable Security Alerts', _alerts,
                (v) => setState(() => _alerts = v)),
            const SizedBox(height: 8),
            _checkRow('Two-Factor Authentication (2FA)', _twoFA,
                (v) => setState(() => _twoFA = v)),
            const SizedBox(height: 40),
            TButton(
                label: _loading ? 'Creating...' : 'Continue',
                onTap: _loading ? null : _submit),
          ]),
        ),
      ),
    );
  }

  Widget _checkRow(String label, bool val, ValueChanged<bool> onChange) {
    return GestureDetector(
      onTap: () => onChange(!val),
      child: Row(children: [
        Container(
            width: 18,
            height: 18,
            decoration: BoxDecoration(
                border: Border.all(color: AppColors.border),
                borderRadius: BorderRadius.circular(3)),
            child: val
                ? const Icon(Icons.check, size: 12, color: AppColors.primary)
                : null),
        const SizedBox(width: 10),
        Text(label,
            style: const TextStyle(fontSize: 13, color: AppColors.textPrimary)),
      ]),
    );
  }
}

// ── Freelancer Signup ─────────────────────────────────────────────────────────
class FreelancerSignupScreen extends StatefulWidget {
  const FreelancerSignupScreen({super.key});
  @override
  State<FreelancerSignupScreen> createState() => _FreelancerSignupScreenState();
}

class _FreelancerSignupScreenState extends State<FreelancerSignupScreen> {
  String _field2 = 'Frontend Development';
  String _customField = '';
  String _level = 'Beginner';
  String _avail = '';
  final List<String> _selectedSkills = [];
  bool _loading = false;
  bool _prefilled = false;
  String? _usernameError;
  String? _fieldError;
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _usernameCtrl = TextEditingController();

  final List<String> _levelOptions = [
    'Beginner',
    'Junior',
    'Mid-Level',
    'Senior',
    'Expert'
  ];

  bool get _sessionSignup => _isAuthenticatedSignup(context);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _prefillFromSession());
  }

  void _prefillFromSession() {
    if (!mounted || _prefilled) return;
    final session = context.read<SessionController>();
    final user = session.currentUser;
    if (user == null ||
        !(session.isAuthenticated || session.isPendingApproval)) {
      return;
    }
    if (!user.needsProfileSetup && !user.isAdmin) {
      _navigateFromSession(context);
      return;
    }
    if (!user.isStudent && !user.isAdmin) {
      Navigator.pushNamedAndRemoveUntil(
        context,
        R.completeFreelancerProfile,
        (_) => false,
      );
      return;
    }
    _prefilled = true;
    if (_nameCtrl.text.isEmpty && user.fullName.isNotEmpty) {
      _nameCtrl.text = user.fullName;
    }
    if (_usernameCtrl.text.isEmpty && user.displayName.isNotEmpty) {
      _usernameCtrl.text = user.displayName;
    }
    if (_emailCtrl.text.isEmpty && user.email.isNotEmpty) {
      _emailCtrl.text = user.email;
    }
    if (user.professionalField.isNotEmpty) {
      if (RegistrationOptions.professionalFields
          .contains(user.professionalField)) {
        _field2 = user.professionalField;
      } else {
        _field2 = 'Other';
        _customField = user.professionalField;
      }
    }
    if (user.experienceLevel.isNotEmpty) {
      _level = user.experienceLevel;
    }
    if (user.availability.isNotEmpty) {
      _avail = user.availability;
    }
    if (user.skills.isNotEmpty && _selectedSkills.isEmpty) {
      _selectedSkills.addAll(user.skills);
    }
    setState(() {});
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _usernameCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_loading) return;
    final username = _usernameCtrl.text.trim();
    final usernameErr = RegistrationOptions.validateUsername(username);
    if (usernameErr != null) {
      setState(() => _usernameError = usernameErr);
      return;
    }
    if (AppConfig.isDemoMode &&
        RegistrationOptions.isDemoUsernameTaken(username)) {
      setState(() => _usernameError = 'Username is already taken.');
      return;
    }
    final fieldToSend = _field2 == 'Other'
        ? (_customField.trim().isNotEmpty ? _customField.trim() : 'Other')
        : _field2;
    if (_field2.isEmpty || fieldToSend.isEmpty) {
      setState(() => _fieldError = 'Professional Field is required.');
      return;
    }
    if (_avail.isEmpty || _selectedSkills.isEmpty) {
      _showAuthError(
        context,
        'Please complete availability and skills.',
      );
      return;
    }
    setState(() {
      _loading = true;
      _usernameError = null;
      _fieldError = null;
    });
    try {
      if (AppConfig.isDemoMode) {
        await Future.delayed(const Duration(milliseconds: 300));
        if (!mounted) return;
        final mockUser = ApiUser(
          id: 'demo_freelancer_${DateTime.now().millisecondsSinceEpoch}',
          displayName: username,
          fullName: _nameCtrl.text.trim().isNotEmpty
              ? _nameCtrl.text.trim()
              : username,
          email: _emailCtrl.text.trim(),
          role: 'member',
          userType: 'freelancer',
          professionalField: fieldToSend,
          experienceLevel: _level,
          availability: _avail,
          skills: List.from(_selectedSkills),
        );
        context.read<SessionController>().setCurrentUser(mockUser);
        Navigator.pushNamedAndRemoveUntil(
            context, R.freelancerHome, (_) => false);
        return;
      }
      if (_sessionSignup) {
        await _submitAuthenticatedProfile(
          username: username,
          fieldToSend: fieldToSend,
        );
        return;
      }
      await context.read<SessionController>().register(
        fullName: _nameCtrl.text.trim(),
        email: _emailCtrl.text.trim(),
        password: _passwordCtrl.text,
        role: 'member',
        userType: 'freelancer',
        extra: {
          'username': username,
          'professional_field': fieldToSend,
          'experience_level': _level,
          'availability': _avail,
          'skills': _selectedSkills.join(','),
        },
      );
      if (!mounted) return;
      _navigateFromSession(context, isNew: true);
    } catch (error) {
      if (mounted) _showAuthError(context, error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _submitAuthenticatedProfile({
    required String username,
    required String fieldToSend,
  }) async {
    final session = context.read<SessionController>();
    final res = await context.read<AppServices>().users.updateProfile({
      'full_name': _nameCtrl.text.trim(),
      'display_name': username,
      'email': _emailCtrl.text.trim(),
      'user_type': 'freelancer',
      'professional_field': fieldToSend,
      'experience_level': _level,
      'availability': _avail,
      'skills': _selectedSkills,
    });
    if (!mounted) return;
    res.when(
      success: (updated) {
        if (updated != null) {
          session.setCurrentUser(updated);
        }
        _navigateFromSession(context, isNew: true);
      },
      failure: (e) => _showAuthError(context, e),
    );
  }

  void _showSingleSelect(String title, List<String> options, String current,
      Function(String) onSelect) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary)),
            const SizedBox(height: 20),
            ...options.map((opt) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(opt,
                      style: TextStyle(
                        color: opt == current
                            ? AppColors.primary
                            : AppColors.textPrimary,
                        fontWeight: opt == current
                            ? FontWeight.bold
                            : FontWeight.normal,
                      )),
                  trailing: opt == current
                      ? const Icon(Icons.check_circle, color: AppColors.primary)
                      : null,
                  onTap: () {
                    onSelect(opt);
                    Navigator.pop(context);
                  },
                )),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  void _showMultiSelect() {
    final searchCtrl = TextEditingController();
    final customCtrl = TextEditingController();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          final query = searchCtrl.text.toLowerCase();
          final allSkills = [
            ...RegistrationOptions.skills
                .where((s) => s.toLowerCase() != 'other'),
            ..._selectedSkills
                .where((s) => !RegistrationOptions.skills.contains(s)),
          ];
          final filtered = allSkills
              .where((s) => query.isEmpty || s.toLowerCase().contains(query))
              .toList();
          return Container(
            constraints: BoxConstraints(
                maxHeight: MediaQuery.of(ctx).size.height * 0.85),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Primary Skills',
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary)),
                const SizedBox(height: 12),
                TextField(
                  controller: searchCtrl,
                  decoration: InputDecoration(
                    hintText: 'Search skills…',
                    prefixIcon: const Icon(Icons.search, size: 20),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: AppColors.border)),
                    enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: AppColors.border)),
                  ),
                  onChanged: (_) => setModalState(() {}),
                ),
                const SizedBox(height: 12),
                Flexible(
                  child: SingleChildScrollView(
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: filtered.map((skill) {
                        final isSelected = _selectedSkills.contains(skill);
                        return FilterChip(
                          label: Text(skill),
                          selected: isSelected,
                          onSelected: (val) {
                            setModalState(() {
                              if (val) {
                                if (!_selectedSkills.contains(skill)) {
                                  _selectedSkills.add(skill);
                                }
                              } else {
                                _selectedSkills.remove(skill);
                              }
                            });
                            setState(() {});
                          },
                          selectedColor:
                              AppColors.primary.withValues(alpha: 0.1),
                          checkmarkColor: AppColors.primary,
                          labelStyle: TextStyle(
                            color: isSelected
                                ? AppColors.primary
                                : AppColors.textPrimary,
                            fontWeight: isSelected
                                ? FontWeight.bold
                                : FontWeight.normal,
                          ),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                              side: BorderSide(
                                  color: isSelected
                                      ? AppColors.primary
                                      : AppColors.border)),
                        );
                      }).toList(),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(
                    child: TextField(
                      controller: customCtrl,
                      decoration: InputDecoration(
                        hintText: 'Add custom skill…',
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide:
                                const BorderSide(color: AppColors.border)),
                        enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide:
                                const BorderSide(color: AppColors.border)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: () {
                      final custom = customCtrl.text.trim();
                      if (custom.isNotEmpty) {
                        final exists = _selectedSkills.any(
                            (s) => s.toLowerCase() == custom.toLowerCase());
                        if (!exists) {
                          setModalState(() => _selectedSkills.add(custom));
                          setState(() {});
                        }
                        customCtrl.clear();
                      }
                    },
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Add'),
                    style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12)),
                  ),
                ]),
                const SizedBox(height: 16),
                TButton(label: 'Done', onTap: () => Navigator.pop(ctx)),
                const SizedBox(height: 20),
              ],
            ),
          );
        },
      ),
    );
  }

  void _showProfessionalFieldSelect() {
    final searchCtrl = TextEditingController();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          final query = searchCtrl.text.toLowerCase();
          final filtered = RegistrationOptions.professionalFields
              .where((f) => query.isEmpty || f.toLowerCase().contains(query))
              .toList();
          return Container(
            constraints: BoxConstraints(
                maxHeight: MediaQuery.of(ctx).size.height * 0.85),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Select Professional Field',
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary)),
                const SizedBox(height: 12),
                TextField(
                  controller: searchCtrl,
                  decoration: InputDecoration(
                    hintText: 'Search professional fields…',
                    prefixIcon: const Icon(Icons.search, size: 20),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: AppColors.border)),
                    enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: AppColors.border)),
                  ),
                  onChanged: (_) => setModalState(() {}),
                ),
                const SizedBox(height: 8),
                Flexible(
                  child: filtered.isEmpty
                      ? const Padding(
                          padding: EdgeInsets.symmetric(vertical: 32),
                          child: Center(
                            child: Text(
                              'No professional field found',
                              style: TextStyle(
                                  color: AppColors.textSecondary, fontSize: 14),
                            ),
                          ),
                        )
                      : ListView.builder(
                          shrinkWrap: true,
                          itemCount: filtered.length,
                          itemBuilder: (_, i) {
                            final opt = filtered[i];
                            final isSelected = opt == _field2;
                            return ListTile(
                              contentPadding: EdgeInsets.zero,
                              title: Text(opt,
                                  style: TextStyle(
                                    color: isSelected
                                        ? AppColors.primary
                                        : AppColors.textPrimary,
                                    fontWeight: isSelected
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                  )),
                              trailing: isSelected
                                  ? const Icon(Icons.check_circle,
                                      color: AppColors.primary)
                                  : null,
                              onTap: () {
                                setState(() {
                                  _field2 = opt;
                                  _fieldError = null;
                                });
                                Navigator.pop(ctx);
                              },
                            );
                          },
                        ),
                ),
                const SizedBox(height: 16),
              ],
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Full Name',
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                    fontSize: 15)),
            const SizedBox(height: 8),
            _field(hint: 'example', controller: _nameCtrl),
            const SizedBox(height: 16),
            const Text('Username',
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                    fontSize: 15)),
            const SizedBox(height: 8),
            _field(
                hint: 'e.g. john_dev',
                prefix: Icons.alternate_email,
                controller: _usernameCtrl),
            if (_usernameError != null) ...[
              const SizedBox(height: 4),
              Text(_usernameError!,
                  style: const TextStyle(color: AppColors.error, fontSize: 12)),
            ],
            const SizedBox(height: 16),
            const Text('Email',
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                    fontSize: 15)),
            const SizedBox(height: 8),
            _field(
                hint: 'example562@gmail.com',
                prefix: Icons.email_outlined,
                controller: _emailCtrl),
            if (!_sessionSignup) ...[
              const SizedBox(height: 16),
              const Text('Password',
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                      fontSize: 15)),
              const SizedBox(height: 8),
              _field(
                  hint: 'Password123',
                  prefix: Icons.lock_outline,
                  obscure: true,
                  controller: _passwordCtrl),
            ],
            const SizedBox(height: 16),
            const Text('Professional Field',
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                    fontSize: 15)),
            const SizedBox(height: 8),
            GestureDetector(
              onTap: _showProfessionalFieldSelect,
              child: _selectionField(
                  _field2.isEmpty ? 'Select professional field' : _field2),
            ),
            if (_field2 == 'Other') ...[
              const SizedBox(height: 8),
              TextField(
                decoration: InputDecoration(
                  hintText: 'Enter your professional field',
                  hintStyle:
                      const TextStyle(color: AppColors.textHint, fontSize: 14),
                  filled: true,
                  fillColor: Colors.white,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: AppColors.border)),
                  enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: AppColors.border)),
                  focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: AppColors.primary)),
                ),
                onChanged: (v) => _customField = v,
              ),
            ],
            if (_fieldError != null) ...[
              const SizedBox(height: 4),
              Text(_fieldError!,
                  style: const TextStyle(color: AppColors.error, fontSize: 12)),
            ],
            const SizedBox(height: 16),
            const Text('Experience Level',
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                    fontSize: 15)),
            const SizedBox(height: 8),
            GestureDetector(
              onTap: () => _showSingleSelect('Experience Level', _levelOptions,
                  _level, (v) => setState(() => _level = v)),
              child: _selectionField(_level),
            ),
            const SizedBox(height: 16),
            const Text('Availability',
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                    fontSize: 15)),
            const SizedBox(height: 8),
            ...['Full Time', 'Part Time', 'Freelancer'].map(
                (a) => _radioRow(a, _avail, (v) => setState(() => _avail = v))),
            const SizedBox(height: 16),
            const Text('Primary Skills',
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                    fontSize: 15)),
            const SizedBox(height: 8),
            GestureDetector(
              onTap: _showMultiSelect,
              child: _selectionFieldMulti(_selectedSkills),
            ),
            const SizedBox(height: 24),
            TButton(
                label: _loading
                    ? (_sessionSignup ? 'Saving...' : 'Creating...')
                    : 'Continue',
                onTap: _loading ? null : _submit),
            if (!_sessionSignup) _signupSocialActions(context, 'Freelancer'),
          ]),
        ),
      ),
    );
  }

  Widget _selectionField(String value) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(value,
              style:
                  const TextStyle(color: AppColors.textPrimary, fontSize: 14)),
          const Icon(Icons.keyboard_arrow_down,
              color: AppColors.textSecondary, size: 20),
        ],
      ),
    );
  }

  Widget _selectionFieldMulti(List<String> values) {
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 52),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: values.isEmpty
                ? const Text('Select skills',
                    style: TextStyle(color: AppColors.textHint, fontSize: 14))
                : Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: values
                        .map((v) => Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: AppColors.primary.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                    color: AppColors.primary
                                        .withValues(alpha: 0.3)),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(v,
                                      style: const TextStyle(
                                          color: AppColors.primary,
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold)),
                                  const SizedBox(width: 4),
                                  GestureDetector(
                                    onTap: () =>
                                        setState(() => values.remove(v)),
                                    child: const Icon(Icons.close,
                                        size: 14, color: AppColors.primary),
                                  ),
                                ],
                              ),
                            ))
                        .toList(),
                  ),
          ),
          const Icon(Icons.keyboard_arrow_down,
              color: AppColors.textSecondary, size: 20),
        ],
      ),
    );
  }

  Widget _radioRow(
      String label, String selected, ValueChanged<String> onSelect) {
    return GestureDetector(
      onTap: () => onSelect(label),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(children: [
          Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.primary, width: 2)),
              child: selected == label
                  ? Center(
                      child: Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                              color: AppColors.primary,
                              shape: BoxShape.circle)))
                  : null),
          const SizedBox(width: 10),
          Text(label,
              style:
                  const TextStyle(fontSize: 14, color: AppColors.textPrimary)),
        ]),
      ),
    );
  }
}

// ── Student Signup ────────────────────────────────────────────────────────────
class StudentSignupScreen extends StatefulWidget {
  const StudentSignupScreen({super.key});
  @override
  State<StudentSignupScreen> createState() => _StudentSignupScreenState();
}

class _StudentSignupScreenState extends State<StudentSignupScreen> {
  String _team = '';
  String _selectedLevel = 'Beginner';
  String _selectedMajor = 'Computer Science';
  String _customMajor = '';
  UniversityOption? _selectedUniversity;
  final _customUniCtrl = TextEditingController();
  String? _universityError;
  final List<String> _selectedSkills = [];
  bool _loading = false;
  bool _prefilled = false;
  String? _usernameError;
  String? _emailError;
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _usernameCtrl = TextEditingController();

  final List<String> _levelOptions = [
    'Beginner',
    'Junior',
    'Mid-Level',
    'Senior',
    'Expert'
  ];

  bool get _sessionSignup => _isAuthenticatedSignup(context);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _prefillFromSession());
  }

  void _prefillFromSession() {
    if (!mounted || _prefilled) return;
    final session = context.read<SessionController>();
    final user = session.currentUser;
    if (user == null ||
        !(session.isAuthenticated || session.isPendingApproval)) {
      return;
    }
    if (!user.needsProfileSetup && !user.isAdmin) {
      _navigateFromSession(context);
      return;
    }
    _prefilled = true;
    if (_nameCtrl.text.isEmpty && user.fullName.isNotEmpty) {
      _nameCtrl.text = user.fullName;
    }
    if (_usernameCtrl.text.isEmpty && user.displayName.isNotEmpty) {
      _usernameCtrl.text = user.displayName;
    }
    if (_emailCtrl.text.isEmpty && user.email.isNotEmpty) {
      _emailCtrl.text = user.email;
    }
    if (user.currentLevel.isNotEmpty) {
      _selectedLevel = user.currentLevel;
    }
    if (user.major.isNotEmpty) {
      if (RegistrationOptions.majors.contains(user.major)) {
        _selectedMajor = user.major;
      } else {
        _selectedMajor = 'Other';
        _customMajor = user.major;
      }
    }
    if (user.lookingForTeam != null) {
      _team = user.lookingForTeam! ? 'Yes' : 'NO';
    }
    if (user.skills.isNotEmpty && _selectedSkills.isEmpty) {
      _selectedSkills.addAll(user.skills);
    }
    if (user.universityId.isNotEmpty || user.universityName.isNotEmpty) {
      _selectedUniversity = UniversityOption.create(
        id: user.universityId.isNotEmpty ? user.universityId : 'uni_other',
        name: user.universityName,
        isCustom: user.isCustomUniversity,
      );
      if (user.isCustomUniversity && user.universityName.isNotEmpty) {
        _customUniCtrl.text = user.universityName;
      }
    }
    setState(() {});
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _usernameCtrl.dispose();
    _customUniCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_loading) return;
    final username = _usernameCtrl.text.trim();
    final email = _emailCtrl.text.trim();

    String? emailErr;
    if (email.isEmpty) {
      emailErr = 'Email address is required.';
    } else {
      final emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
      if (!emailRegex.hasMatch(email)) {
        emailErr = 'Please enter a valid email address.';
      }
    }
    if (emailErr != null) {
      setState(() => _emailError = emailErr);
      return;
    }

    final usernameErr = RegistrationOptions.validateUsername(username);
    if (usernameErr != null) {
      setState(() => _usernameError = usernameErr);
      return;
    }
    if (AppConfig.isDemoMode &&
        RegistrationOptions.isDemoUsernameTaken(username)) {
      setState(() => _usernameError = 'Username is already taken.');
      return;
    }

    if (_selectedSkills.isEmpty) {
      _showAuthError(context, 'Please select at least one skill.');
      return;
    }

    if (_selectedUniversity == null) {
      setState(() => _universityError = 'University selection is required.');
      return;
    }

    UniversityOption uniToSend = _selectedUniversity!;
    if (_selectedUniversity?.id == 'uni_other') {
      final customErr =
          UniversityOption.validateCustomUniversityName(_customUniCtrl.text);
      if (customErr != null) {
        setState(() => _universityError = customErr);
        return;
      }
      uniToSend = UniversityOption.custom(_customUniCtrl.text);
    }

    final majorToSend =
        _selectedMajor == 'Other' ? _customMajor.trim() : _selectedMajor;
    setState(() {
      _loading = true;
      _emailError = null;
      _usernameError = null;
      _universityError = null;
    });
    try {
      if (AppConfig.isDemoMode) {
        await Future.delayed(const Duration(milliseconds: 300));
        if (!mounted) return;
        final majorToSend = _selectedMajor == 'Other'
            ? (_customMajor.trim().isNotEmpty ? _customMajor.trim() : 'Other')
            : _selectedMajor;
        final mockUser = ApiUser(
          id: 'demo_student_${DateTime.now().millisecondsSinceEpoch}',
          displayName: username,
          fullName: _nameCtrl.text.trim().isNotEmpty
              ? _nameCtrl.text.trim()
              : username,
          email: email,
          role: 'member',
          userType: 'student',
          currentLevel: _selectedLevel,
          major: majorToSend,
          skills: List.from(_selectedSkills),
          lookingForTeam: _team.toLowerCase() == 'yes',
          universityId: uniToSend.id,
          universityName: uniToSend.name,
          isCustomUniversity: uniToSend.isCustom,
        );
        context.read<SessionController>().setCurrentUser(mockUser);
        Navigator.pushNamedAndRemoveUntil(context, R.studentHome, (_) => false);
        return;
      }
      if (_sessionSignup) {
        await _submitAuthenticatedProfile(
          username: username,
          majorToSend: majorToSend,
          uniToSend: uniToSend,
        );
        return;
      }
      await context.read<SessionController>().register(
        fullName: _nameCtrl.text.trim(),
        email: _emailCtrl.text.trim(),
        password: _passwordCtrl.text,
        role: 'member',
        userType: 'student',
        extra: {
          'username': username,
          'current_level': _selectedLevel,
          'major': majorToSend,
          'skills': _selectedSkills.join(','),
          'looking_for_team': _team.toLowerCase() == 'yes',
          'university_id': uniToSend.id,
          'university_name': uniToSend.name,
          'is_custom_university': uniToSend.isCustom,
        },
      );
      if (!mounted) return;
      _navigateFromSession(context, isNew: true);
    } catch (error) {
      if (mounted) _showAuthError(context, error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _submitAuthenticatedProfile({
    required String username,
    required String majorToSend,
    required UniversityOption uniToSend,
  }) async {
    final session = context.read<SessionController>();
    final res = await context.read<AppServices>().users.updateProfile({
      'full_name': _nameCtrl.text.trim(),
      'display_name': username,
      'email': _emailCtrl.text.trim(),
      'user_type': 'student',
      'current_level': _selectedLevel,
      'major': majorToSend,
      'skills': _selectedSkills,
      'looking_for_team': _team.toLowerCase() == 'yes',
      'university_id': uniToSend.id,
      'university_name': uniToSend.name,
      'is_custom_university': uniToSend.isCustom,
    });
    if (!mounted) return;
    res.when(
      success: (updated) {
        if (updated != null) {
          session.setCurrentUser(updated);
        }
        _navigateFromSession(context, isNew: true);
      },
      failure: (e) => _showAuthError(context, e),
    );
  }

  void _showMajorSelect() {
    final searchCtrl = TextEditingController();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          final query = searchCtrl.text.toLowerCase();
          final filtered = RegistrationOptions.majors
              .where((m) => query.isEmpty || m.toLowerCase().contains(query))
              .toList();
          return Container(
            constraints: BoxConstraints(
                maxHeight: MediaQuery.of(ctx).size.height * 0.85),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Select Major',
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary)),
                const SizedBox(height: 12),
                TextField(
                  controller: searchCtrl,
                  decoration: InputDecoration(
                    hintText: 'Search majors…',
                    prefixIcon: const Icon(Icons.search, size: 20),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: AppColors.border)),
                    enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: AppColors.border)),
                  ),
                  onChanged: (_) => setModalState(() {}),
                ),
                const SizedBox(height: 8),
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: filtered.length,
                    itemBuilder: (_, i) {
                      final opt = filtered[i];
                      final isSelected = opt == _selectedMajor;
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(opt,
                            style: TextStyle(
                              color: isSelected
                                  ? AppColors.primary
                                  : AppColors.textPrimary,
                              fontWeight: isSelected
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                            )),
                        trailing: isSelected
                            ? const Icon(Icons.check_circle,
                                color: AppColors.primary)
                            : null,
                        onTap: () {
                          setState(() => _selectedMajor = opt);
                          Navigator.pop(ctx);
                        },
                      );
                    },
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
          );
        },
      ),
    );
  }

  void _showSkillsSelect() {
    final searchCtrl = TextEditingController();
    final customCtrl = TextEditingController();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          final query = searchCtrl.text.toLowerCase();
          final allSkills = [
            ...RegistrationOptions.skills
                .where((s) => s.toLowerCase() != 'other'),
            ..._selectedSkills
                .where((s) => !RegistrationOptions.skills.contains(s)),
          ];
          final filtered = allSkills
              .where((s) => query.isEmpty || s.toLowerCase().contains(query))
              .toList();
          return Container(
            constraints: BoxConstraints(
                maxHeight: MediaQuery.of(ctx).size.height * 0.85),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Primary Skills',
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary)),
                const SizedBox(height: 12),
                TextField(
                  controller: searchCtrl,
                  decoration: InputDecoration(
                    hintText: 'Search skills…',
                    prefixIcon: const Icon(Icons.search, size: 20),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: AppColors.border)),
                    enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: AppColors.border)),
                  ),
                  onChanged: (_) => setModalState(() {}),
                ),
                const SizedBox(height: 12),
                Flexible(
                  child: SingleChildScrollView(
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: filtered.map((skill) {
                        final isSelected = _selectedSkills.contains(skill);
                        return FilterChip(
                          label: Text(skill),
                          selected: isSelected,
                          onSelected: (val) {
                            setModalState(() {
                              if (val) {
                                if (!_selectedSkills.contains(skill)) {
                                  _selectedSkills.add(skill);
                                }
                              } else {
                                _selectedSkills.remove(skill);
                              }
                            });
                            setState(() {});
                          },
                          selectedColor:
                              AppColors.primary.withValues(alpha: 0.1),
                          checkmarkColor: AppColors.primary,
                          labelStyle: TextStyle(
                            color: isSelected
                                ? AppColors.primary
                                : AppColors.textPrimary,
                            fontWeight: isSelected
                                ? FontWeight.bold
                                : FontWeight.normal,
                          ),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                              side: BorderSide(
                                  color: isSelected
                                      ? AppColors.primary
                                      : AppColors.border)),
                        );
                      }).toList(),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(
                    child: TextField(
                      controller: customCtrl,
                      decoration: InputDecoration(
                        hintText: 'Add custom skill…',
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide:
                                const BorderSide(color: AppColors.border)),
                        enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide:
                                const BorderSide(color: AppColors.border)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: () {
                      final custom = customCtrl.text.trim();
                      if (custom.isNotEmpty) {
                        final exists = _selectedSkills.any(
                            (s) => s.toLowerCase() == custom.toLowerCase());
                        if (!exists) {
                          setModalState(() => _selectedSkills.add(custom));
                          setState(() {});
                        }
                        customCtrl.clear();
                      }
                    },
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Add'),
                    style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12)),
                  ),
                ]),
                const SizedBox(height: 16),
                TButton(label: 'Done', onTap: () => Navigator.pop(ctx)),
                const SizedBox(height: 20),
              ],
            ),
          );
        },
      ),
    );
  }

  void _showSingleSelect(String title, List<String> options, String current,
      Function(String) onSelect) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary)),
            const SizedBox(height: 20),
            ...options.map((opt) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(opt,
                      style: TextStyle(
                        color: opt == current
                            ? AppColors.primary
                            : AppColors.textPrimary,
                        fontWeight: opt == current
                            ? FontWeight.bold
                            : FontWeight.normal,
                      )),
                  trailing: opt == current
                      ? const Icon(Icons.check_circle, color: AppColors.primary)
                      : null,
                  onTap: () {
                    onSelect(opt);
                    Navigator.pop(context);
                  },
                )),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Full Name',
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                    fontSize: 15)),
            const SizedBox(height: 8),
            _field(hint: 'example', controller: _nameCtrl),
            const SizedBox(height: 16),
            const Text('Username',
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                    fontSize: 15)),
            const SizedBox(height: 8),
            _field(
                hint: 'e.g. jane_doe',
                prefix: Icons.alternate_email,
                controller: _usernameCtrl),
            if (_usernameError != null) ...[
              const SizedBox(height: 4),
              Text(_usernameError!,
                  style: const TextStyle(color: AppColors.error, fontSize: 12)),
            ],
            const SizedBox(height: 16),
            const Text('Email',
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                    fontSize: 15)),
            const SizedBox(height: 8),
            _field(
                hint: 'example562@gmail.com',
                prefix: Icons.email_outlined,
                controller: _emailCtrl),
            if (_emailError != null) ...[
              const SizedBox(height: 4),
              Text(_emailError!,
                  style: const TextStyle(color: AppColors.error, fontSize: 12)),
            ],
            if (!_sessionSignup) ...[
              const SizedBox(height: 16),
              const Text('Password',
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                      fontSize: 15)),
              const SizedBox(height: 8),
              _field(
                  hint: 'Password123',
                  prefix: Icons.lock_outline,
                  obscure: true,
                  controller: _passwordCtrl),
            ],
            const SizedBox(height: 16),
            UniversitySelectorField(
              selectedOption: _selectedUniversity,
              onSelected: (opt) {
                setState(() {
                  _selectedUniversity = opt;
                  _universityError = null;
                });
              },
            ),
            if (_universityError != null) ...[
              const SizedBox(height: 4),
              Text(
                _universityError!,
                style: const TextStyle(color: AppColors.error, fontSize: 12),
              ),
            ],
            if (_selectedUniversity?.id == 'uni_other') ...[
              const SizedBox(height: 12),
              CustomUniversityField(
                controller: _customUniCtrl,
              ),
            ],
            const SizedBox(height: 16),
            const Text('Current Level',
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                    fontSize: 15)),
            const SizedBox(height: 8),
            GestureDetector(
              onTap: () => _showSingleSelect('Current Level', _levelOptions,
                  _selectedLevel, (v) => setState(() => _selectedLevel = v)),
              child: _selectionField(_selectedLevel),
            ),
            const SizedBox(height: 16),
            const Text('Major',
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                    fontSize: 15)),
            const SizedBox(height: 8),
            GestureDetector(
              onTap: _showMajorSelect,
              child: _selectionField(_selectedMajor),
            ),
            if (_selectedMajor == 'Other') ...[
              const SizedBox(height: 8),
              TextField(
                decoration: InputDecoration(
                  hintText: 'Enter your major',
                  hintStyle:
                      const TextStyle(color: AppColors.textHint, fontSize: 14),
                  filled: true,
                  fillColor: Colors.white,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: AppColors.border)),
                  enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: AppColors.border)),
                  focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: AppColors.primary)),
                ),
                onChanged: (v) => _customMajor = v,
              ),
            ],
            const SizedBox(height: 16),
            const Text('Primary Skills',
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                    fontSize: 15)),
            const SizedBox(height: 8),
            GestureDetector(
              onTap: _showSkillsSelect,
              child: _selectionFieldMulti(_selectedSkills),
            ),
            const SizedBox(height: 16),
            const Text('Looking for a team?',
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                    fontSize: 15)),
            const SizedBox(height: 8),
            _radioRowSimple('Yes', _team, (v) => setState(() => _team = v)),
            _radioRowSimple('NO', _team, (v) => setState(() => _team = v)),
            const SizedBox(height: 24),
            TButton(
                label: _loading
                    ? (_sessionSignup ? 'Saving...' : 'Creating...')
                    : 'Continue',
                onTap: _loading ? null : _submit),
            if (!_sessionSignup) _signupSocialActions(context, 'Student'),
          ]),
        ),
      ),
    );
  }

  Widget _selectionField(String value) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(value,
              style:
                  const TextStyle(color: AppColors.textPrimary, fontSize: 14)),
          const Icon(Icons.keyboard_arrow_down,
              color: AppColors.textSecondary, size: 20),
        ],
      ),
    );
  }

  Widget _selectionFieldMulti(List<String> values) {
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 52),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: values.isEmpty
                ? const Text('Select skills',
                    style: TextStyle(color: AppColors.textHint, fontSize: 14))
                : Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: values
                        .map((v) => Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: AppColors.primary.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                    color: AppColors.primary
                                        .withValues(alpha: 0.3)),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(v,
                                      style: const TextStyle(
                                          color: AppColors.primary,
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold)),
                                  const SizedBox(width: 4),
                                  GestureDetector(
                                    onTap: () =>
                                        setState(() => values.remove(v)),
                                    child: const Icon(Icons.close,
                                        size: 14, color: AppColors.primary),
                                  ),
                                ],
                              ),
                            ))
                        .toList(),
                  ),
          ),
          const Icon(Icons.keyboard_arrow_down,
              color: AppColors.textSecondary, size: 20),
        ],
      ),
    );
  }

  Widget _radioRowSimple(
      String label, String selected, ValueChanged<String> onSelect) {
    return GestureDetector(
      onTap: () => onSelect(label),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(children: [
          Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.primary, width: 2)),
              child: selected == label
                  ? Center(
                      child: Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                              color: AppColors.primary,
                              shape: BoxShape.circle)))
                  : null),
          const SizedBox(width: 10),
          Text(label,
              style:
                  const TextStyle(fontSize: 14, color: AppColors.textPrimary)),
        ]),
      ),
    );
  }
}

// ── Verify Email ──────────────────────────────────────────────────────────────
class VerifyEmailScreen extends StatefulWidget {
  const VerifyEmailScreen({super.key});
  @override
  State<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends State<VerifyEmailScreen> {
  @override
  Widget build(BuildContext context) {
    final args =
        ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
    final email = args?['email']?.toString() ?? '';

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(children: [
            const Spacer(),
            Image.asset(
              'assets/images/verify_email.png',
              width: 240,
              height: 180,
              fit: BoxFit.contain,
            ),
            const SizedBox(height: 28),
            const Text('Email verification',
                style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary)),
            const SizedBox(height: 8),
            Text(
              email.isNotEmpty
                  ? 'If you signed up with $email, check your inbox for a verification link or continue with the OTP step during signup.'
                  : 'Teamify verifies your email during signup using a one-time code. '
                      'If you already completed signup, you can log in directly.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 14, height: 1.4),
            ),
            const Spacer(),
            TButton(
                label: 'Continue to Login',
                onTap: () => Navigator.pushNamedAndRemoveUntil(
                      context,
                      R.login,
                      (_) => false,
                    )),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Back'),
            ),
          ]),
        ),
      ),
    );
  }
}

// ── Forgot Password ───────────────────────────────────────────────────────────
class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});
  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _emailCtrl = TextEditingController();
  bool _loading = false;

  @override
  void dispose() {
    _emailCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _emailCtrl.text.trim();
    if (email.isEmpty) return;
    if (_loading) return;
    setState(() => _loading = true);

    final res = await context.read<AppServices>().auth.forgotPassword(email);
    if (!mounted) return;
    setState(() => _loading = false);

    res.when(
      success: (_) {
        Navigator.pushNamed(context, R.otpVerification,
            arguments: {'flow': 'forgotPassword', 'email': email});
      },
      failure: (err) => _showAuthError(context, err),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios,
                size: 18, color: AppColors.textPrimary),
            onPressed: () => Navigator.pop(context)),
        title: const Text('Forgot Password',
            style: TextStyle(
                fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
        actions: [
          Row(children: [
            Container(
                width: 10,
                height: 10,
                decoration: const BoxDecoration(
                    color: AppColors.primary, shape: BoxShape.circle)),
            const SizedBox(width: 4),
            Container(
                width: 10,
                height: 10,
                decoration: const BoxDecoration(
                    color: AppColors.border, shape: BoxShape.circle)),
            const SizedBox(width: 4),
            Container(
                width: 10,
                height: 10,
                decoration: const BoxDecoration(
                    color: AppColors.border, shape: BoxShape.circle)),
            const SizedBox(width: 16),
          ])
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Center(
              child: Image.asset('assets/images/forgot_password.png',
                  height: 180, fit: BoxFit.contain)),
          const Center(
              child: Text('Forgot Password?',
                  style:
                      TextStyle(fontSize: 16, color: AppColors.textSecondary))),
          const SizedBox(height: 32),
          const Text('Your Email',
              style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                  fontSize: 15)),
          const SizedBox(height: 8),
          _field(
              hint: 'example562@gmail.com',
              prefix: Icons.email_outlined,
              controller: _emailCtrl),
          const Spacer(),
          TButton(
              label: _loading ? 'Sending...' : 'Got OTP',
              onTap: _loading ? null : _submit),
        ]),
      ),
    );
  }
}

// ── OTP Verification ──────────────────────────────────────────────────────────
class OTPVerificationScreen extends StatefulWidget {
  const OTPVerificationScreen({super.key});
  @override
  State<OTPVerificationScreen> createState() => _OTPVerificationScreenState();
}

class _OTPVerificationScreenState extends State<OTPVerificationScreen> {
  int _countdown = 0;
  bool _loading = false;
  final List<TextEditingController> _controllers =
      List.generate(6, (_) => TextEditingController());

  @override
  void dispose() {
    for (var c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  void _resendCode(String email) async {
    if (_countdown > 0) return;
    setState(() => _countdown = 60);

    await context.read<AppServices>().auth.forgotPassword(email);

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('OTP resent successfully!'),
      backgroundColor: AppColors.primary,
    ));
    Future.doWhile(() async {
      await Future.delayed(const Duration(seconds: 1));
      if (!mounted) return false;
      setState(() => _countdown--);
      return _countdown > 0;
    });
  }

  Future<void> _verify(String email, String flow, String role) async {
    final otp = _controllers.map((c) => c.text).join();
    if (otp.length < 6) return;

    if (flow == 'forgotPassword') {
      if (_loading) return;
      setState(() => _loading = true);

      final res = await context.read<AppServices>().auth.verifyOtp(email, otp);
      if (!mounted) return;
      setState(() => _loading = false);

      res.when(
        success: (token) {
          Navigator.pushNamed(context, R.createNewPassword,
              arguments: {'token': token});
        },
        failure: (err) => _showAuthError(context, err),
      );
    } else {
      if (role == 'Admin') {
        Navigator.pushNamed(context, R.confirmationAdmin);
      } else if (role == 'Student') {
        Navigator.pushNamed(context, R.confirmationStudent);
      } else {
        Navigator.pushNamed(context, R.confirmationFreelancer);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final args =
        ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
    final flow = args?['flow'] ?? 'signup';
    final role = args?['role'] ?? 'Freelancer';
    final email = args?['email'] ?? 'example@gmail.com';

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios,
                size: 18, color: AppColors.textPrimary),
            onPressed: () => Navigator.pop(context)),
        title: const Text('OTP Verification',
            style: TextStyle(
                fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
        actions: [
          Row(children: [
            Container(
                width: 10,
                height: 10,
                decoration: const BoxDecoration(
                    color: AppColors.border, shape: BoxShape.circle)),
            const SizedBox(width: 4),
            Container(
                width: 10,
                height: 10,
                decoration: const BoxDecoration(
                    color: AppColors.primary, shape: BoxShape.circle)),
            const SizedBox(width: 4),
            Container(
                width: 10,
                height: 10,
                decoration: const BoxDecoration(
                    color: AppColors.border, shape: BoxShape.circle)),
            const SizedBox(width: 16),
          ])
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(children: [
          Image.asset('assets/images/otp_verification.png',
              height: 180, fit: BoxFit.contain),
          const SizedBox(height: 16),
          const Text('Enter OTP',
              style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary)),
          const SizedBox(height: 16),
          Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                6,
                (index) => Container(
                  width: 44,
                  height: 56,
                  margin: const EdgeInsets.only(right: 8),
                  decoration: BoxDecoration(
                      border: Border.all(color: AppColors.border),
                      borderRadius: BorderRadius.circular(10)),
                  child: TextField(
                    controller: _controllers[index],
                    autofocus: index == 0,
                    onChanged: (v) {
                      if (v.length == 1 && index < 5) {
                        FocusScope.of(context).nextFocus();
                      }
                    },
                    textAlign: TextAlign.center,
                    keyboardType: TextInputType.number,
                    maxLength: 1,
                    style: const TextStyle(
                        fontSize: 22, fontWeight: FontWeight.bold),
                    decoration: const InputDecoration(
                        border: InputBorder.none, counterText: ''),
                  ),
                ),
              )),
          const SizedBox(height: 16),
          Text('Please enter the 6-digit code sent to:\n$email',
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 13)),
          const SizedBox(height: 12),
          GestureDetector(
            onTap: _countdown == 0 ? () => _resendCode(email) : null,
            child: RichText(
                text: TextSpan(
              text: "Didn't receive the code? ",
              style:
                  const TextStyle(color: AppColors.textSecondary, fontSize: 14),
              children: [
                TextSpan(
                  text: _countdown > 0 ? 'Resend in ${_countdown}s' : 'Resend',
                  style: TextStyle(
                    color:
                        _countdown > 0 ? AppColors.textHint : AppColors.primary,
                    fontWeight: FontWeight.bold,
                  ),
                )
              ],
            )),
          ),
          const Spacer(),
          TButton(
              label: _loading ? 'Verifying...' : 'Verify',
              onTap: _loading ? null : () => _verify(email, flow, role)),
        ]),
      ),
    );
  }
}

// ── Create New Password ───────────────────────────────────────────────────────
class CreateNewPasswordScreen extends StatefulWidget {
  const CreateNewPasswordScreen({super.key});
  @override
  State<CreateNewPasswordScreen> createState() =>
      _CreateNewPasswordScreenState();
}

class _CreateNewPasswordScreenState extends State<CreateNewPasswordScreen> {
  bool _obscureNew = true;
  bool _obscureConfirm = true;
  bool _loading = false;
  final _newCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();

  @override
  void dispose() {
    _newCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit(String token) async {
    final pass = _newCtrl.text;
    final confirm = _confirmCtrl.text;
    if (pass.isEmpty || pass != confirm) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Passwords do not match or are empty.')));
      return;
    }
    if (token.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Reset session expired. Please request a new OTP.')));
      return;
    }

    if (_loading) return;
    setState(() => _loading = true);

    final res =
        await context.read<AppServices>().auth.resetPassword(token, pass);
    if (!mounted) return;
    setState(() => _loading = false);

    res.when(
      success: (_) {
        Navigator.pushNamedAndRemoveUntil(context, R.login, (_) => false);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Password reset successfully! Please sign in.'),
          backgroundColor: AppColors.primary,
        ));
      },
      failure: (err) => _showAuthError(context, err),
    );
  }

  @override
  Widget build(BuildContext context) {
    final args =
        ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
    final token = args?['token'] as String? ?? '';

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios,
                size: 18, color: AppColors.textPrimary),
            onPressed: () => Navigator.pop(context)),
        title: const Text('Create New Password',
            style: TextStyle(
                fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
        actions: [
          Row(children: [
            Container(
                width: 10,
                height: 10,
                decoration: const BoxDecoration(
                    color: AppColors.border, shape: BoxShape.circle)),
            const SizedBox(width: 4),
            Container(
                width: 10,
                height: 10,
                decoration: const BoxDecoration(
                    color: AppColors.border, shape: BoxShape.circle)),
            const SizedBox(width: 4),
            Container(
                width: 10,
                height: 10,
                decoration: const BoxDecoration(
                    color: AppColors.primary, shape: BoxShape.circle)),
            const SizedBox(width: 16),
          ])
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Center(
              child: Image.asset('assets/images/create_new_password.png',
                  height: 180, fit: BoxFit.contain)),
          const SizedBox(height: 24),
          const Text('New Password',
              style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                  fontSize: 15)),
          const SizedBox(height: 8),
          TextField(
            controller: _newCtrl,
            obscureText: _obscureNew,
            decoration: InputDecoration(
              hintText: '••••••••••••••••••••',
              hintStyle: const TextStyle(color: AppColors.textHint),
              suffixIcon: IconButton(
                icon: Icon(
                    _obscureNew
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                    color: AppColors.textSecondary,
                    size: 20),
                onPressed: () => setState(() => _obscureNew = !_obscureNew),
              ),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: AppColors.border)),
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: AppColors.border)),
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: AppColors.primary)),
            ),
          ),
          const SizedBox(height: 16),
          const Text('Confirm Password',
              style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                  fontSize: 15)),
          const SizedBox(height: 8),
          TextField(
            controller: _confirmCtrl,
            obscureText: _obscureConfirm,
            decoration: InputDecoration(
              hintText: '••••••••••••••••••••',
              hintStyle: const TextStyle(color: AppColors.textHint),
              suffixIcon: IconButton(
                icon: Icon(
                    _obscureConfirm
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                    color: AppColors.textSecondary,
                    size: 20),
                onPressed: () =>
                    setState(() => _obscureConfirm = !_obscureConfirm),
              ),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: AppColors.border)),
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: AppColors.border)),
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: AppColors.primary)),
            ),
          ),
          const Spacer(),
          TButton(
            label: _loading ? 'Resetting...' : 'Reset Password',
            onTap: _loading ? null : () => _submit(token),
          ),
        ]),
      ),
    );
  }
}

// ── Confirmation Admin ────────────────────────────────────────────────────────
class ConfirmationAdminScreen extends StatelessWidget {
  const ConfirmationAdminScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return _ConfirmationScreen(
      emoji: '💻🖥️',
      text: '"You now have full admin access."',
      onTap: () async => _navigateToCorrectHome(context, 'Admin', isNew: true),
    );
  }
}

// ── Confirmation Freelancer ───────────────────────────────────────────────────
class ConfirmationFreelancerScreen extends StatelessWidget {
  const ConfirmationFreelancerScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return _ConfirmationScreen(
      emoji: '✅📄',
      text: '" Teams can now find you based\non yourself "',
      onTap: () => _navigateToCorrectHome(context, 'Freelancer', isNew: true),
    );
  }
}

// ── Confirmation Student ──────────────────────────────────────────────────────
class ConfirmationStudentScreen extends StatelessWidget {
  const ConfirmationStudentScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return _ConfirmationScreen(
      emoji: '👫✅',
      text: '" we will help you to find the the\nright project team"',
      onTap: () => _navigateToCorrectHome(context, 'Student', isNew: true),
    );
  }
}

class _ConfirmationScreen extends StatelessWidget {
  final String emoji, text;
  final VoidCallback onTap;
  const _ConfirmationScreen(
      {required this.emoji, required this.text, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(children: [
            const Spacer(),
            Container(
              width: 220,
              height: 220,
              decoration: BoxDecoration(
                  color: const Color(0xFFF5F5FA),
                  borderRadius: BorderRadius.circular(20)),
              child: Center(
                  child: Text(emoji, style: const TextStyle(fontSize: 70))),
            ),
            const SizedBox(height: 32),
            Text(text,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 18,
                    color: AppColors.primaryDark,
                    height: 1.5,
                    fontStyle: FontStyle.italic,
                    fontWeight: FontWeight.w500)),
            const Spacer(),
            TButton(label: 'Go to Home', onTap: onTap),
            const SizedBox(height: 16),
          ]),
        ),
      ),
    );
  }
}
