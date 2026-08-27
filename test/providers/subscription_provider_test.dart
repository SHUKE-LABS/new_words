import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:new_words/dependency_injection.dart';
import 'package:new_words/entities/purchase_result.dart';
import 'package:new_words/entities/subscription_tier.dart';
import 'package:new_words/providers/subscription_provider.dart';
import 'package:new_words/services/subscription_service.dart';

@GenerateMocks([SubscriptionService])
import 'subscription_provider_test.mocks.dart';

void main() {
  group('SubscriptionProvider', () {
    late MockSubscriptionService mockService;
    late StreamController<PurchaseResult> resultStream;

    setUp(() {
      mockService = MockSubscriptionService();
      resultStream = StreamController<PurchaseResult>.broadcast();

      when(mockService.purchaseStream).thenAnswer((_) => resultStream.stream);
      when(mockService.initialize()).thenAnswer((_) async {});
      when(mockService.getAvailableProducts()).thenAnswer((_) async => []);
      when(mockService.getPastPurchases()).thenAnswer((_) async => []);
      when(mockService.dispose()).thenReturn(null);

      if (locator.isRegistered<SubscriptionService>()) {
        locator.unregister<SubscriptionService>();
      }
      locator.registerSingleton<SubscriptionService>(mockService);
    });

    tearDown(() async {
      await resultStream.close();
      if (locator.isRegistered<SubscriptionService>()) {
        locator.unregister<SubscriptionService>();
      }
    });

    /// Drains the event queue so the async purchase-stream handler, and the
    /// completePurchase future it awaits, both run to completion.
    Future<void> settle() => pumpEventQueue();

    group('isPurchasing lifecycle', () {
      test('stays true after purchaseSubscription returns', () async {
        when(mockService.purchaseSubscription(any)).thenAnswer((_) async {});
        final provider = SubscriptionProvider();
        await provider.initialize();

        await provider.purchaseSubscription(SubscriptionTier.monthly);

        // The service call only launches the platform sheet. Re-enabling the
        // buy button here would allow a duplicate purchase.
        expect(provider.isPurchasing, isTrue);
      });

      test('clears only once a result arrives on the stream', () async {
        when(mockService.purchaseSubscription(any)).thenAnswer((_) async {});
        final provider = SubscriptionProvider();
        await provider.initialize();

        await provider.purchaseSubscription(SubscriptionTier.monthly);
        expect(provider.isPurchasing, isTrue);

        resultStream.add(PurchaseResult.cancelled());
        await settle();

        expect(provider.isPurchasing, isFalse);
      });

      test('clears when an initiation failure arrives on the stream', () async {
        // The service emits a failure result on every throw path before
        // rethrowing, so the flag cannot latch on an initiation error.
        when(mockService.purchaseSubscription(any))
            .thenAnswer((_) async => throw Exception('cannot initiate'));
        final provider = SubscriptionProvider();
        await provider.initialize();

        await provider.purchaseSubscription(SubscriptionTier.monthly);
        expect(provider.isPurchasing, isTrue);

        resultStream.add(PurchaseResult.failure(errorMessage: 'cannot initiate'));
        await settle();

        expect(provider.isPurchasing, isFalse);
        expect(provider.errorMessage, isNotNull);
      });

      test('a second attempt is rejected while a purchase is in flight',
          () async {
        when(mockService.purchaseSubscription(any)).thenAnswer((_) async {});
        final provider = SubscriptionProvider();
        await provider.initialize();

        await provider.purchaseSubscription(SubscriptionTier.monthly);
        await provider.purchaseSubscription(SubscriptionTier.monthly);

        verify(mockService.purchaseSubscription(SubscriptionTier.monthly))
            .called(1);
      });

      test('clearAllData still resets the flag for session teardown', () async {
        when(mockService.purchaseSubscription(any)).thenAnswer((_) async {});
        final provider = SubscriptionProvider();
        await provider.initialize();

        await provider.purchaseSubscription(SubscriptionTier.monthly);
        expect(provider.isPurchasing, isTrue);

        provider.clearAllData();

        expect(provider.isPurchasing, isFalse);
      });
    });

    group('dispose', () {
      test('does not throw before initialize has run', () {
        final provider = SubscriptionProvider();

        expect(provider.dispose, returnsNormally);
      });

      test('does not throw after initialize failed', () async {
        when(mockService.initialize())
            .thenAnswer((_) async => throw Exception('IAP unavailable'));
        final provider = SubscriptionProvider();

        await provider.initialize();

        expect(provider.dispose, returnsNormally);
      });
    });
  });
}
