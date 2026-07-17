import 'package:flutter_test/flutter_test.dart';
import 'package:project_atlas/core/router/route_guards.dart';
import 'package:project_atlas/core/router/route_paths.dart';
import 'package:project_atlas/core/router/user_companies_route_state.dart';

void main() {
  group('resolveAuthRedirect', () {
    test('recovery attiva ha priorità e reindirizza a update password', () {
      expect(
        resolveAuthRedirect(
          location: RoutePaths.onboardingCompany,
          isAuthenticated: true,
          isPasswordRecoveryActive: true,
          companiesState: const UserCompaniesEmpty(),
        ),
        RoutePaths.updatePassword,
      );
    });

    test('recovery attiva non reindirizza se già su update password', () {
      expect(
        resolveAuthRedirect(
          location: RoutePaths.updatePassword,
          isAuthenticated: true,
          isPasswordRecoveryActive: true,
          companiesState: const UserCompaniesEmpty(),
        ),
        isNull,
      );
    });

    test('recovery attiva blocca redirect verso onboarding da login', () {
      expect(
        resolveAuthRedirect(
          location: RoutePaths.login,
          isAuthenticated: true,
          isPasswordRecoveryActive: true,
          companiesState: const UserCompaniesEmpty(),
        ),
        RoutePaths.updatePassword,
      );
    });

    test('update password senza recovery reindirizza al login', () {
      expect(
        resolveAuthRedirect(
          location: RoutePaths.updatePassword,
          isAuthenticated: false,
          isPasswordRecoveryActive: false,
          companiesState: const UserCompaniesEmpty(),
        ),
        RoutePaths.login,
      );
    });

    test('login riuscito con loading non reindirizza temporaneamente', () {
      expect(
        resolveAuthRedirect(
          location: RoutePaths.login,
          isAuthenticated: true,
          isPasswordRecoveryActive: false,
          companiesState: const UserCompaniesLoading(),
        ),
        isNull,
      );
    });

    test('login riuscito con zero aziende reindirizza a onboarding', () {
      expect(
        resolveAuthRedirect(
          location: RoutePaths.login,
          isAuthenticated: true,
          isPasswordRecoveryActive: false,
          companiesState: const UserCompaniesEmpty(),
        ),
        RoutePaths.onboardingCompany,
      );
    });

    test('login riuscito con azienda attiva reindirizza a dashboard', () {
      expect(
        resolveAuthRedirect(
          location: RoutePaths.login,
          isAuthenticated: true,
          isPasswordRecoveryActive: false,
          companiesState: const UserCompaniesReady(),
        ),
        RoutePaths.dashboard,
      );
    });

    test('membership multiple senza scelta reindirizza al selector', () {
      expect(
        resolveAuthRedirect(
          location: RoutePaths.login,
          isAuthenticated: true,
          isPasswordRecoveryActive: false,
          companiesState: const UserCompaniesNeedsSelection(),
        ),
        RoutePaths.selectCompany,
      );
    });

    test('selector resta visibile finché manca azienda attiva', () {
      expect(
        resolveAuthRedirect(
          location: RoutePaths.selectCompany,
          isAuthenticated: true,
          isPasswordRecoveryActive: false,
          companiesState: const UserCompaniesNeedsSelection(),
        ),
        isNull,
      );
    });

    test('errore caricamento aziende reindirizza a onboarding da login', () {
      expect(
        resolveAuthRedirect(
          location: RoutePaths.login,
          isAuthenticated: true,
          isPasswordRecoveryActive: false,
          companiesState: const UserCompaniesError('Errore di rete'),
        ),
        RoutePaths.onboardingCompany,
      );
    });

    test('errore caricamento aziende non resta bloccato su login', () {
      expect(
        resolveAuthRedirect(
          location: RoutePaths.login,
          isAuthenticated: true,
          isPasswordRecoveryActive: false,
          companiesState: const UserCompaniesError('Errore di rete'),
        ),
        isNot(RoutePaths.login),
      );
    });

    test('utente autenticato senza azienda su dashboard va a onboarding', () {
      expect(
        resolveAuthRedirect(
          location: RoutePaths.dashboard,
          isAuthenticated: true,
          isPasswordRecoveryActive: false,
          companiesState: const UserCompaniesEmpty(),
        ),
        RoutePaths.onboardingCompany,
      );
    });

    test('utente autenticato senza azienda su settings va a onboarding', () {
      expect(
        resolveAuthRedirect(
          location: RoutePaths.settingsCompany,
          isAuthenticated: true,
          isPasswordRecoveryActive: false,
          companiesState: const UserCompaniesEmpty(),
        ),
        RoutePaths.onboardingCompany,
      );
    });

    test(
      'membership multiple senza scelta da settings reindirizza al selector',
      () {
        expect(
          resolveAuthRedirect(
            location: RoutePaths.settingsCompany,
            isAuthenticated: true,
            isPasswordRecoveryActive: false,
            companiesState: const UserCompaniesNeedsSelection(),
          ),
          RoutePaths.selectCompany,
        );
      },
    );

    test('UserCompaniesReady lascia accessibile settings company', () {
      expect(
        resolveAuthRedirect(
          location: RoutePaths.settingsCompany,
          isAuthenticated: true,
          isPasswordRecoveryActive: false,
          companiesState: const UserCompaniesReady(),
        ),
        isNull,
      );
    });

    test('route Clienti protetta senza auth va al login', () {
      expect(
        resolveAuthRedirect(
          location: RoutePaths.clients,
          isAuthenticated: false,
          isPasswordRecoveryActive: false,
          companiesState: const UserCompaniesEmpty(),
        ),
        RoutePaths.login,
      );
    });

    test('route Clienti senza azienda attiva va a onboarding', () {
      expect(
        resolveAuthRedirect(
          location: RoutePaths.clients,
          isAuthenticated: true,
          isPasswordRecoveryActive: false,
          companiesState: const UserCompaniesEmpty(),
        ),
        RoutePaths.onboardingCompany,
      );
    });

    test('sottorotta nuovo cliente richiede selezione se manca active', () {
      expect(
        resolveAuthRedirect(
          location: RoutePaths.customerNew,
          isAuthenticated: true,
          isPasswordRecoveryActive: false,
          companiesState: const UserCompaniesNeedsSelection(),
        ),
        RoutePaths.selectCompany,
      );
    });

    test('UserCompaniesReady lascia accessibile Clienti', () {
      expect(
        resolveAuthRedirect(
          location: RoutePaths.clients,
          isAuthenticated: true,
          isPasswordRecoveryActive: false,
          companiesState: const UserCompaniesReady(),
        ),
        isNull,
      );
    });

    test(
      'utente autenticato con azienda attiva su onboarding va a dashboard',
      () {
        expect(
          resolveAuthRedirect(
            location: RoutePaths.onboardingCompany,
            isAuthenticated: true,
            isPasswordRecoveryActive: false,
            companiesState: const UserCompaniesReady(),
          ),
          RoutePaths.dashboard,
        );
      },
    );

    test('UserCompaniesReady consente apertura volontaria del selector', () {
      expect(
        resolveAuthRedirect(
          location: RoutePaths.selectCompany,
          isAuthenticated: true,
          isPasswordRecoveryActive: false,
          companiesState: const UserCompaniesReady(),
        ),
        isNull,
      );
    });

    test(
      'dopo conferma signup autenticato va a onboarding non update password',
      () {
        expect(
          resolveAuthRedirect(
            location: RoutePaths.login,
            isAuthenticated: true,
            isPasswordRecoveryActive: false,
            companiesState: const UserCompaniesEmpty(),
          ),
          RoutePaths.onboardingCompany,
        );
        expect(
          resolveAuthRedirect(
            location: RoutePaths.login,
            isAuthenticated: true,
            isPasswordRecoveryActive: true,
            companiesState: const UserCompaniesEmpty(),
          ),
          RoutePaths.updatePassword,
        );
      },
    );

    test('utente non autenticato su dashboard va al login', () {
      expect(
        resolveAuthRedirect(
          location: RoutePaths.dashboard,
          isAuthenticated: false,
          isPasswordRecoveryActive: false,
          companiesState: const UserCompaniesEmpty(),
        ),
        RoutePaths.login,
      );
    });
  });
}
