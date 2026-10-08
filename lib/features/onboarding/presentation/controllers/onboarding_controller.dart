import 'package:dukaan_book/features/auth/data/auth_repository.dart';
import 'package:dukaan_book/features/onboarding/data/onboarding_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final onboardingControllerProvider =
    AsyncNotifierProvider<OnboardingController, void>(OnboardingController.new);

class OnboardingController extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  Future<void> completeShopSetup({
    required String shopName,
    String? ownerName,
    String? city,
    String? phone,
  }) async {
    final user = ref.read(authRepositoryProvider).currentUser;
    if (user == null) {
      state = AsyncError(const OnboardingAuthException(), StackTrace.current);
      return;
    }

    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => ref
          .read(onboardingRepositoryProvider)
          .completeShopSetup(
            user: user,
            shopName: shopName,
            ownerName: ownerName,
            city: city,
            phone: phone,
          ),
    );

    if (!state.hasError) {
      ref.invalidate(onboardingCompletedProvider);
    }
  }

  Future<void> joinExistingShop({
    required String shopId,
    String? ownerName,
    String? phone,
  }) async {
    final user = ref.read(authRepositoryProvider).currentUser;
    if (user == null) {
      state = AsyncError(const OnboardingAuthException(), StackTrace.current);
      return;
    }

    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => ref
          .read(onboardingRepositoryProvider)
          .joinExistingShop(
            user: user,
            shopId: shopId,
            ownerName: ownerName,
            phone: phone,
          ),
    );

    if (!state.hasError) {
      ref.invalidate(onboardingCompletedProvider);
    }
  }
}

class OnboardingAuthException implements Exception {
  const OnboardingAuthException();
}
