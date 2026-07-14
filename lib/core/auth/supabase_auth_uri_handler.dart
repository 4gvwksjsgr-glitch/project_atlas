import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'auth_recovery_bootstrap.dart';
import 'clear_auth_uri_params.dart';

/// Gestisce il callback PKCE Supabase all'avvio su Flutter Web.
abstract final class SupabaseAuthUriHandler {
  static const _recoveryRedirectTypes = {'recovery', 'passwordRecovery'};

  static Map<String, String> _fragmentParameters(Uri uri) {
    if (uri.fragment.isEmpty) {
      return const {};
    }
    return Uri.splitQueryString(uri.fragment);
  }

  static bool _hasParam(Uri uri, String key) {
    return uri.queryParameters.containsKey(key) ||
        _fragmentParameters(uri).containsKey(key);
  }

  static bool hasAuthCallbackParams(Uri uri) {
    return _hasParam(uri, 'code') ||
        _hasParam(uri, 'access_token') ||
        _hasParam(uri, 'error') ||
        _hasParam(uri, 'error_description');
  }

  static String mapAuthLinkError(AuthException error) {
    final message = error.message.toLowerCase();

    if (message.contains('code verifier could not be found') ||
        message.contains('code verifier')) {
      return 'Link non valido in questo browser. Richiedi un nuovo link di reset.';
    }

    if (message.contains('expired') ||
        message.contains('invalid') ||
        message.contains('already been used')) {
      return 'Link scaduto o già utilizzato. Richiedi un nuovo link di reset.';
    }

    return 'Link di recupero non valido. Richiedi un nuovo link di reset.';
  }

  static bool isPasswordRecoverySession({
    AuthSessionUrlResponse? response,
    AuthChangeEvent? event,
    Uri? launchUri,
  }) {
    if (event == AuthChangeEvent.passwordRecovery) {
      return true;
    }

    final redirectType = response?.redirectType;
    if (redirectType != null && _recoveryRedirectTypes.contains(redirectType)) {
      return true;
    }

    if (launchUri != null) {
      final type =
          launchUri.queryParameters['type'] ??
          _fragmentParameters(launchUri)['type'];
      if (type == 'recovery') {
        return true;
      }
    }

    return false;
  }

  static void _activateRecoveryIfNeeded({
    AuthSessionUrlResponse? response,
    AuthChangeEvent? event,
    required Uri launchUri,
  }) {
    if (isPasswordRecoverySession(
      response: response,
      event: event,
      launchUri: launchUri,
    )) {
      AuthRecoveryBootstrap.activateRecovery();
    }
  }

  /// Completa lo scambio PKCE dall'URL di lancio prima del routing.
  ///
  /// [launchUri] è uno snapshot catturato all'inizio di [bootstrap], prima di
  /// qualsiasi modifica all'URL del browser.
  static Future<void> completeSessionFromLaunchUri(
    SupabaseClient client, {
    required Uri launchUri,
    required bool hadAuthCallbackAtLaunch,
  }) async {
    if (!kIsWeb) {
      return;
    }

    final hasCallbackParams = hasAuthCallbackParams(launchUri);

    if (!hasCallbackParams && !hadAuthCallbackAtLaunch) {
      return;
    }

    if (_hasParam(launchUri, 'error') ||
        _hasParam(launchUri, 'error_description')) {
      AuthRecoveryBootstrap.setLinkError(
        'Link di recupero non valido. Richiedi un nuovo link di reset.',
      );
      clearAuthUriParams();
      return;
    }

    final code = launchUri.queryParameters['code'];
    final hasCode = code != null && code.isNotEmpty;

    if (!hasCode && !_hasParam(launchUri, 'access_token')) {
      clearAuthUriParams();
      return;
    }

    if (hasCode && client.auth.currentSession != null) {
      _activateRecoveryIfNeeded(
        event: AuthChangeEvent.signedIn,
        launchUri: launchUri,
      );
      clearAuthUriParams();
      return;
    }

    AuthChangeEvent? capturedEvent;
    final subscription = client.auth.onAuthStateChange.listen((data) {
      capturedEvent = data.event;
    });

    try {
      final response = await client.auth.getSessionFromUrl(launchUri);
      _activateRecoveryIfNeeded(
        response: response,
        event: capturedEvent,
        launchUri: launchUri,
      );
      clearAuthUriParams();
    } on AuthException catch (error) {
      if (client.auth.currentSession != null && hadAuthCallbackAtLaunch) {
        _activateRecoveryIfNeeded(event: capturedEvent, launchUri: launchUri);
        clearAuthUriParams();
        return;
      }

      AuthRecoveryBootstrap.setLinkError(mapAuthLinkError(error));
      clearAuthUriParams();
    } finally {
      await subscription.cancel();
    }
  }
}
