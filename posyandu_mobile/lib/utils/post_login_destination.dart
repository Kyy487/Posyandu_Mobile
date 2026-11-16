enum PostLoginDestination {
  dashboard,
  completeRegistration,
  rejectedRegistration,
  childOnboarding,
}

PostLoginDestination resolvePostLoginDestination(Map<String, dynamic>? user) {
  final role = user?['role']?.toString().trim().toLowerCase();
  final nextAction = user?['next_action']?.toString().trim().toLowerCase();
  final status = user?['status']?.toString().trim().toLowerCase();
  final onboardingStatus = user?['onboarding_status']
      ?.toString()
      .trim()
      .toLowerCase();

  if (role == 'ibu') {
    switch (nextAction) {
      case 'complete_registration':
        return PostLoginDestination.completeRegistration;
      case 'fix_registration':
        return PostLoginDestination.rejectedRegistration;
      case 'add_child':
        return PostLoginDestination.childOnboarding;
    }

    if (status == 'pending') {
      return PostLoginDestination.completeRegistration;
    }

    if (status == 'rejected') {
      return PostLoginDestination.rejectedRegistration;
    }

    if (status == 'active' && onboardingStatus == 'need_child_data') {
      return PostLoginDestination.childOnboarding;
    }
  }

  return PostLoginDestination.dashboard;
}
