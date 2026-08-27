import 'dart:async';
import 'package:in_app_purchase/in_app_purchase.dart';

import '../entities/subscription_tier.dart';
import '../entities/subscription_status.dart';
import '../entities/purchase_result.dart';
import '../services/subscription_service.dart';
import '../dependency_injection.dart';
import 'provider_base.dart';

/// Provider for managing subscription state and purchase operations
class SubscriptionProvider extends AuthAwareProvider {
  final SubscriptionService _subscriptionService = locator<SubscriptionService>();
  
  StreamSubscription<PurchaseResult>? _purchaseSubscription;

  // State variables
  SubscriptionStatus _subscriptionStatus = SubscriptionStatus.free(currentWordCount: 0);
  List<ProductDetails> _availableProducts = [];
  bool _isLoading = false;
  String? _errorMessage;
  bool _isPurchasing = false;

  // Getters
  SubscriptionStatus get subscriptionStatus => _subscriptionStatus;
  List<ProductDetails> get availableProducts => _availableProducts;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  bool get isPurchasing => _isPurchasing;

  // Convenience getters
  bool get hasPremiumFeatures => _subscriptionStatus.hasPremiumFeatures;
  bool get canAddWords => _subscriptionStatus.canAddWords;
  int get remainingWords => _subscriptionStatus.remainingWords;
  int get currentWordCount => _subscriptionStatus.currentWordCount;
  SubscriptionTier get currentTier => _subscriptionStatus.tier;

  /// Initialize the subscription provider
  Future<void> initialize() async {
    await executeWithErrorHandling(
      operation: () async {
        await _subscriptionService.initialize();
        _purchaseSubscription = _subscriptionService.purchaseStream.listen(_onPurchaseResult);
        await loadAvailableProducts();
        await loadSubscriptionStatus();
      },
      setLoading: _setLoading,
      setError: _setError,
      operationName: 'initialize subscription provider',
    );
  }

  /// Load available products from Google Play
  Future<void> loadAvailableProducts() async {
    await executeWithErrorHandling(
      operation: () async {
        _availableProducts = await _subscriptionService.getAvailableProducts();
        return _availableProducts;
      },
      setLoading: _setLoading,
      setError: _setError,
      operationName: 'load available products',
    );
  }

  /// Load current subscription status
  Future<void> loadSubscriptionStatus() async {
    await executeWithErrorHandling(
      operation: () async {
        // TODO: This should call backend API to get subscription status
        // For now, we'll load from past purchases
        final pastPurchases = await _subscriptionService.getPastPurchases();
        _updateSubscriptionFromPurchases(pastPurchases);
        return _subscriptionStatus;
      },
      setLoading: _setLoading,
      setError: _setError,
      operationName: 'load subscription status',
    );
  }

  /// Purchase a subscription
  Future<void> purchaseSubscription(SubscriptionTier tier) async {
    if (_isPurchasing) return;
    
    _setPurchasing(true);
    // Deliberately not reset here: this call only *launches* the platform
    // purchase sheet. _isPurchasing stays true until a PurchaseResult arrives
    // via the stream (_onPurchaseResult), otherwise the UI re-enables the buy
    // button while the sheet is still open and a duplicate purchase can be
    // started. The service emits a failure result on every throw path, so an
    // initiation error still clears the flag.
    await executeWithErrorHandling(
      operation: () async {
        await _subscriptionService.purchaseSubscription(tier);
        return null;
      },
      setLoading: (loading) {}, // Don't use general loading state for purchases
      setError: _setError,
      operationName: 'purchase subscription',
    );
  }

  /// Restore previous purchases
  Future<void> restorePurchases() async {
    await executeWithErrorHandling(
      operation: () async {
        await _subscriptionService.restorePurchases();
        return null;
      },
      setLoading: _setLoading,
      setError: _setError,
      operationName: 'restore purchases',
    );
  }

  /// Update word count (called when user adds/removes words)
  void updateWordCount(int newCount) {
    _subscriptionStatus = _subscriptionStatus.copyWith(currentWordCount: newCount);
    notifyListeners();
  }

  /// Get product details for a specific tier
  ProductDetails? getProductDetails(SubscriptionTier tier) {
    return _availableProducts
        .where((product) => product.id == tier.productId)
        .firstOrNull;
  }

  /// Handle purchase results from the subscription service
  void _onPurchaseResult(PurchaseResult result) {
    if (result.success && result.tier != null) {
      // Update subscription status
      _subscriptionStatus = SubscriptionStatus.premium(
        tier: result.tier!,
        currentWordCount: _subscriptionStatus.currentWordCount,
        purchaseToken: result.purchaseDetails?.purchaseID,
        productId: result.purchaseDetails?.productID,
      );
      
      // TODO: Send purchase to backend for verification and storage
      
      _setError(null);
    } else if (!result.success) {
      _setError(result.errorMessage);
    }
    
    _setPurchasing(false);
    notifyListeners();
  }

  /// Update subscription status from past purchases
  void _updateSubscriptionFromPurchases(List<PurchaseDetails> purchases) {
    // Find the most recent valid purchase
    PurchaseDetails? latestPurchase;
    SubscriptionTier? latestTier;
    
    for (final purchase in purchases) {
      if (purchase.status == PurchaseStatus.purchased) {
        final tier = SubscriptionTier.values
            .where((t) => t.productId == purchase.productID)
            .firstOrNull;
        
        if (tier != null) {
          if (latestPurchase == null) {
            latestPurchase = purchase;
            latestTier = tier;
          }
          // For now, just use the latest found purchase
          // TODO: Implement proper date comparison when we understand the transactionDate type
        }
      }
    }

    if (latestPurchase != null && latestTier != null) {
      _subscriptionStatus = SubscriptionStatus.premium(
        tier: latestTier,
        currentWordCount: _subscriptionStatus.currentWordCount,
        purchaseToken: latestPurchase.purchaseID,
        productId: latestPurchase.productID,
      );
    }
  }

  /// Set loading state
  void _setLoading(bool loading) {
    _isLoading = loading;
    notifyListeners();
  }

  /// Set error message
  void _setError(String? error) {
    _errorMessage = error;
    notifyListeners();
  }

  /// Set purchasing state
  void _setPurchasing(bool purchasing) {
    _isPurchasing = purchasing;
    notifyListeners();
  }

  @override
  Future<void> onLogin() async {
    // Load user's subscription status when they log in
    await loadSubscriptionStatus();
  }

  @override
  void clearAllData() {
    _subscriptionStatus = SubscriptionStatus.free(currentWordCount: 0);
    _availableProducts = [];
    _isLoading = false;
    _errorMessage = null;
    _isPurchasing = false;
    notifyListeners();
  }

  @override
  void dispose() {
    // Nullable because initialize() may have thrown before assigning it.
    _purchaseSubscription?.cancel();
    _subscriptionService.dispose();
    super.dispose();
  }
}