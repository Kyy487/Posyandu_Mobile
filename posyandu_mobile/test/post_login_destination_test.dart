import 'package:flutter_test/flutter_test.dart';
import 'package:posyandu_mobile/utils/post_login_destination.dart';

void main() {
  test('ibu pending diarahkan melengkapi pendaftaran', () {
    expect(
      resolvePostLoginDestination({
        'role': 'ibu',
        'status': 'pending',
        'next_action': 'complete_registration',
      }),
      PostLoginDestination.completeRegistration,
    );
  });

  test('ibu ditolak diarahkan memperbaiki pendaftaran', () {
    expect(
      resolvePostLoginDestination({
        'role': 'ibu',
        'status': 'rejected',
        'next_action': 'fix_registration',
      }),
      PostLoginDestination.rejectedRegistration,
    );
  });

  test('ibu approved tanpa anak diarahkan ke onboarding anak', () {
    expect(
      resolvePostLoginDestination({
        'role': 'ibu',
        'status': 'active',
        'verification_status': 'approved',
        'onboarding_status': 'need_child_data',
        'next_action': 'add_child',
      }),
      PostLoginDestination.childOnboarding,
    );
  });

  test('ibu approved dengan data anak diarahkan ke dashboard', () {
    expect(
      resolvePostLoginDestination({
        'role': 'ibu',
        'status': 'active',
        'onboarding_status': 'completed',
        'next_action': null,
      }),
      PostLoginDestination.dashboard,
    );
  });

  test('kader diarahkan ke dashboard', () {
    expect(
      resolvePostLoginDestination({
        'role': 'kader',
        'status': 'active',
        'onboarding_status': 'completed',
        'next_action': null,
      }),
      PostLoginDestination.dashboard,
    );
  });

  test('fallback status lama tetap bekerja tanpa next_action', () {
    expect(
      resolvePostLoginDestination({
        'role': 'ibu',
        'status': 'active',
        'onboarding_status': 'need_child_data',
      }),
      PostLoginDestination.childOnboarding,
    );
  });
}
