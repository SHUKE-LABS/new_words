import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:new_words/entities/purchase_result.dart';
import 'package:new_words/entities/subscription_tier.dart';
import 'package:new_words/services/subscription_service.dart';

import '../mocks/mock_app_logger.dart';

@GenerateMocks([InAppPurchase])
import 'subscription_service_test.mocks.dart';

ProductDetails _product(String id) => ProductDetails(
      id: id,
      title: id,
      description: id,
      price: '\$1.99',
      rawPrice: 1.99,
      currencyCode: 'USD',
    );

PurchaseDetails _purchase({
  required PurchaseStatus status,
  required bool pendingCompletePurchase,
  String productID = 'premium_monthly',
  IAPError? error,
}) {
  final details = PurchaseDetails(
    purchaseID: 'purchase-1',
    productID: productID,
    verificationData: PurchaseVerificationData(
      localVerificationData: 'local',
      serverVerificationData: 'server',
      source: 'test',
    ),
    transactionDate: '1704067200000',
    status: status,
  );
  details.pendingCompletePurchase = pendingCompletePurchase;
  details.error = error;
  return details;
}

void main() {
  group('SubscriptionService', () {
    late MockInAppPurchase mockIap;
    late MockAppLogger mockLogger;
    late StreamController<List<PurchaseDetails>> platformStream;
    late SubscriptionService service;

    setUp(() {
      mockIap = MockInAppPurchase();
      mockLogger = MockAppLogger();
      platformStream = StreamController<List<PurchaseDetails>>.broadcast();

      when(mockIap.isAvailable()).thenAnswer((_) async => true);
      when(mockIap.purchaseStream).thenAnswer((_) => platformStream.stream);
      when(mockIap.completePurchase(any)).thenAnswer((_) async {});

      service = SubscriptionService(
        inAppPurchase: mockIap,
        logger: mockLogger,
      );
    });

    tearDown(() async {
      await platformStream.close();
    });

    /// Drains the event queue so the async purchase-stream handler, and the
    /// completePurchase future it awaits, both run to completion.
    Future<void> settle() => pumpEventQueue();

    group('purchaseSubscription', () {
      // Subscriptions and one-time products deliberately share one code path:
      // in_app_purchase treats subscriptions as non-consumable products.
      for (final tier in [
        SubscriptionTier.monthly,
        SubscriptionTier.yearly,
        SubscriptionTier.lifetime,
      ]) {
        test('${tier.name} initiates via buyNonConsumable exactly once',
            () async {
          when(mockIap.queryProductDetails(any)).thenAnswer(
            (_) async => ProductDetailsResponse(
              productDetails: [_product(tier.productId)],
              notFoundIDs: const [],
            ),
          );
          when(mockIap.buyNonConsumable(
                  purchaseParam: anyNamed('purchaseParam')))
              .thenAnswer((_) async => true);

          await service.purchaseSubscription(tier);

          final captured = verify(mockIap.buyNonConsumable(
                  purchaseParam: captureAnyNamed('purchaseParam')))
              .captured;
          expect(captured, hasLength(1));
          expect((captured.single as PurchaseParam).productDetails.id,
              tier.productId);
          verifyNever(mockIap.buyConsumable(
              purchaseParam: anyNamed('purchaseParam')));
        });
      }

      test('a false result from buyNonConsumable surfaces as a failure result',
          () async {
        when(mockIap.queryProductDetails(any)).thenAnswer(
          (_) async => ProductDetailsResponse(
            productDetails: [_product('premium_monthly')],
            notFoundIDs: const [],
          ),
        );
        when(mockIap.buyNonConsumable(purchaseParam: anyNamed('purchaseParam')))
            .thenAnswer((_) async => false);

        final results = <PurchaseResult>[];
        service.purchaseStream.listen(results.add);

        await expectLater(
          service.purchaseSubscription(SubscriptionTier.monthly),
          throwsA(isA<Exception>()),
        );
        await settle();

        expect(results, hasLength(1));
        expect(results.single.success, isFalse);
      });

      test('the free tier never reaches the store', () async {
        await expectLater(
          service.purchaseSubscription(SubscriptionTier.free),
          throwsA(isA<Exception>()),
        );

        verifyNever(mockIap.queryProductDetails(any));
        verifyNever(mockIap.buyNonConsumable(
            purchaseParam: anyNamed('purchaseParam')));
      });
    });

    group('purchase acknowledgement', () {
      // Unacknowledged Play purchases are auto-refunded after 3 days, and
      // unfinished StoreKit transactions replay on every launch -- so every
      // flagged update must be completed, not just the successful ones.
      for (final status in [
        PurchaseStatus.purchased,
        PurchaseStatus.restored,
        PurchaseStatus.error,
        PurchaseStatus.canceled,
      ]) {
        test('${status.name} is completed when the platform flags it',
            () async {
          await service.initialize();
          final details = _purchase(
            status: status,
            pendingCompletePurchase: true,
            error: status == PurchaseStatus.error
                ? IAPError(source: 'test', code: 'e', message: 'boom')
                : null,
          );

          platformStream.add([details]);
          await settle();

          verify(mockIap.completePurchase(details)).called(1);
        });

        test('${status.name} is not completed when the platform does not flag it',
            () async {
          await service.initialize();
          final details = _purchase(
            status: status,
            pendingCompletePurchase: false,
            error: status == PurchaseStatus.error
                ? IAPError(source: 'test', code: 'e', message: 'boom')
                : null,
          );

          platformStream.add([details]);
          await settle();

          verifyNever(mockIap.completePurchase(any));
        });
      }

      test('a pending update is never completed', () async {
        await service.initialize();

        platformStream.add([
          _purchase(
            status: PurchaseStatus.pending,
            pendingCompletePurchase: false,
          )
        ]);
        await settle();

        verifyNever(mockIap.completePurchase(any));
      });

      test('a completePurchase failure is logged and the stream stays live',
          () async {
        await service.initialize();
        when(mockIap.completePurchase(any)).thenAnswer((_) async {
          throw Exception('acknowledgement rejected');
        });

        final failing = _purchase(
          status: PurchaseStatus.purchased,
          pendingCompletePurchase: true,
        );
        platformStream.add([failing]);
        await settle();

        expect(
          mockLogger.errorLogs,
          contains(allOf(
            contains('Failed to complete purchase'),
            contains('premium_monthly'),
          )),
        );

        // The listener must still be attached: an uncaught error would have
        // cancelled the subscription and silently killed all later updates.
        final later = _purchase(
          status: PurchaseStatus.restored,
          pendingCompletePurchase: true,
          productID: 'premium_yearly',
        );
        platformStream.add([later]);
        await settle();

        verify(mockIap.completePurchase(later)).called(1);
      });

      test('a successful purchase result is emitted before acknowledgement',
          () async {
        await service.initialize();
        final emitted = <PurchaseResult>[];
        service.purchaseStream.listen(emitted.add);

        platformStream.add([
          _purchase(
            status: PurchaseStatus.purchased,
            pendingCompletePurchase: true,
          )
        ]);
        await settle();

        expect(emitted, hasLength(1));
        expect(emitted.single.success, isTrue);
        expect(emitted.single.tier, SubscriptionTier.monthly);
        verify(mockIap.completePurchase(any)).called(1);
      });
    });

    group('dispose', () {
      test('does not throw before initialize has run', () {
        expect(service.dispose, returnsNormally);
      });

      test('does not throw after initialize failed', () async {
        when(mockIap.isAvailable()).thenAnswer((_) async => false);

        await expectLater(service.initialize(), throwsA(isA<Exception>()));
        expect(service.dispose, returnsNormally);
      });

      test('cancels the platform subscription after a successful initialize',
          () async {
        await service.initialize();
        service.dispose();

        platformStream.add([
          _purchase(
            status: PurchaseStatus.purchased,
            pendingCompletePurchase: true,
          )
        ]);
        await settle();

        verifyNever(mockIap.completePurchase(any));
      });
    });
  });
}
