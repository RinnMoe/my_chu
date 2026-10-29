import '../privacy_agreement_service.dart';

/// Version 4 predates the Supabase disclosures; only an explicit v5+ receipt
/// authorizes these services. Agreement retrieval itself is a public exception.
class SupabasePrivacyGate {
  SupabasePrivacyGate._();

  static const int requiredAgreementVersion = 5;

  static Future<bool> isAccepted() async =>
      await PrivacyAgreementService.acceptedVersion() >=
          requiredAgreementVersion &&
      await PrivacyAgreementService.isAccepted();
}
