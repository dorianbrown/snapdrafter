import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

enum DonationIapMessageType { success, error }

class DonationIapMessage {
  final DonationIapMessageType type;
  final String? error;

  const DonationIapMessage(this.type, {this.error});
}

class DonationIAP extends ChangeNotifier {
  static final DonationIAP instance = DonationIAP._();
  DonationIAP._();

  static const List<String> productIds = [
    'com.dorianbrown.snapdrafter.donate_5',
    'com.dorianbrown.snapdrafter.donate_10',
  ];

  final InAppPurchase _inAppPurchase = InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? _subscription;

  List<ProductDetails> _products = [];
  bool _available = false;
  bool _loading = true;
  bool _purchasing = false;
  DonationIapMessage? _message;
  int _messageId = 0;

  List<ProductDetails> get products => _products;
  bool get available => _available;
  bool get loading => _loading;
  bool get purchasing => _purchasing;
  DonationIapMessage? get message => _message;
  int get messageId => _messageId;

  /// Must be called once at app startup so that unfinished transactions
  /// from previous sessions are delivered to the purchase stream.
  Future<void> init() async {
    _subscription = _inAppPurchase.purchaseStream.listen(
      _onPurchaseUpdate,
      onDone: () => _subscription?.cancel(),
      onError: (Object error) =>
          debugPrint('In-app purchase stream error: $error'),
    );

    _available = await _inAppPurchase.isAvailable();
    await loadProducts();
  }

  Future<void> loadProducts() async {
    if (!_available) {
      _loading = false;
      notifyListeners();
      return;
    }

    final response = await _inAppPurchase.queryProductDetails(
      productIds.toSet(),
    );
    _products = response.productDetails;
    _loading = false;
    notifyListeners();
  }

  Future<void> buyTip(ProductDetails product) async {
    _purchasing = true;
    notifyListeners();

    final param = PurchaseParam(productDetails: product);
    try {
      await _inAppPurchase.buyConsumable(purchaseParam: param);
    } catch (e) {
      debugPrint('Error starting purchase of ${product.id}: $e');
      _purchasing = false;
      notifyListeners();
    }
  }

  void _onPurchaseUpdate(List<PurchaseDetails> purchaseDetailsList) {
    for (final purchaseDetails in purchaseDetailsList) {
      switch (purchaseDetails.status) {
        case PurchaseStatus.pending:
          break;
        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          _deliverProduct(purchaseDetails);
        case PurchaseStatus.error:
          _purchasing = false;
          _setMessage(
            DonationIapMessage(
              DonationIapMessageType.error,
              error: purchaseDetails.error?.message,
            ),
          );
          notifyListeners();
        case PurchaseStatus.canceled:
          _purchasing = false;
          notifyListeners();
      }
    }
  }

  Future<void> _deliverProduct(PurchaseDetails purchaseDetails) async {
    if (purchaseDetails.pendingCompletePurchase) {
      await _inAppPurchase.completePurchase(purchaseDetails);
    }
    _purchasing = false;
    _setMessage(
      const DonationIapMessage(
        DonationIapMessageType.success,
      ),
    );
    notifyListeners();
  }

  void _setMessage(DonationIapMessage msg) {
    _message = msg;
    _messageId++;
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
