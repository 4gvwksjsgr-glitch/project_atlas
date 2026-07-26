/// Percorsi centralizzati per [GoRouter].
abstract final class RoutePaths {
  static const login = '/login';
  static const signup = '/signup';
  static const forgotPassword = '/forgot-password';
  static const updatePassword = '/auth/update-password';
  static const checkEmail = '/signup/check-email';
  static const onboardingCompany = '/onboarding/company';
  static const selectCompany = '/onboarding/company/select';
  static const dashboard = '/dashboard';
  static const clients = '/clients';
  static const customerNew = '/clients/new';
  static const customersImport = '/clients/import';
  static const transactions = '/transactions';
  static const transactionNew = '/transactions/new';
  static const documents = '/documents';
  static const settingsCompany = '/settings/company';
  static const settingsCategories = '/settings/company/categories';

  static String customerEdit(String customerId) => '/clients/$customerId/edit';

  static String transactionEdit(String transactionId) =>
      '/transactions/$transactionId/edit';
}
