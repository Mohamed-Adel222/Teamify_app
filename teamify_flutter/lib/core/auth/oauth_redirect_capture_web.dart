import 'package:web/web.dart' as web;

import '../cache/cache_manager.dart';

/// Read Google/GitHub OAuth params from the browser URL before Flutter routing
/// can drop the hash fragment, then stash them in cache for SplashScreen.
Future<void> stashOAuthRedirectIfPresent(CacheManager cache) async {
  final hash = web.window.location.hash;
  if (hash.isNotEmpty && hash != '#') {
    final fragment = hash.startsWith('#') ? hash.substring(1) : hash;
    final params = Uri.splitQueryString(fragment);

    final oauthError = params['error'];
    if (oauthError != null && oauthError.isNotEmpty) {
      await cache.putMap('auth', 'pending_oauth', {
        'provider': 'google',
        'error': oauthError,
        'error_description': params['error_description'] ?? '',
      });
      _cleanBrowserUrl();
      return;
    }

    final idToken = params['id_token'];
    if (idToken != null && idToken.isNotEmpty) {
      await cache.putMap('auth', 'pending_oauth', {
        'provider': 'google',
        'id_token': idToken,
      });
      _cleanBrowserUrl();
      return;
    }
  }

  final code = Uri.base.queryParameters['code'];
  if (code != null && code.isNotEmpty) {
    await cache.putMap('auth', 'pending_oauth', {
      'provider': 'github',
      'code': code,
    });
    _cleanBrowserUrl();
  }
}

void _cleanBrowserUrl() {
  // Drop hash + query so a one-time GitHub code cannot be replayed on reload.
  final path = web.window.location.pathname;
  web.window.history.replaceState(null, '', path);
}
