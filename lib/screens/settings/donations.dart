import 'dart:io';

import 'package:flutter/material.dart';

import 'package:flutter_donation_buttons/flutter_donation_buttons.dart';
import 'package:url_launcher/url_launcher.dart';

import '/services/donation_iap.dart';

class DonationScreen extends StatefulWidget {
  const DonationScreen({super.key});

  @override
  State<DonationScreen> createState() => _DonationScreenState();
}

class _DonationScreenState extends State<DonationScreen> {
  int _lastMessageId = 0;

  @override
  void initState() {
    super.initState();
    _lastMessageId = DonationIAP.instance.messageId;
    DonationIAP.instance.addListener(_onIapChanged);
  }

  @override
  void dispose() {
    DonationIAP.instance.removeListener(_onIapChanged);
    super.dispose();
  }

  void _onIapChanged() {
    if (!mounted) return;

    final iap = DonationIAP.instance;
    if (iap.messageId != _lastMessageId) {
      _lastMessageId = iap.messageId;
      final message = iap.message;
      if (message != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              message.type == DonationIapMessageType.success
                  ? "Thank you for your support!"
                  : "Purchase failed. Please try again.",
            ),
          ),
        );
      }
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    String donationText = "If you are enjoying this app and want to support "
      "it's continued development and maintenance, consider donating."
      "\n\n"
      "My aim is to keep SnapDrafter free, ad-free, and available to as many "
        "cube-lovers as possible. \n\nDonations like yours help make that happen.";

    return Scaffold(
      appBar: AppBar(title: const Text("Donation")),
      body: Container(
        padding: EdgeInsets.symmetric(vertical: 50, horizontal: 50),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Spacer(flex: 3),
              Text(donationText,
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 16
                ),
              ),
              Spacer(flex: 1),
              if (Platform.isIOS) ..._buildIosButtons() else ..._buildAndroidButtons(),
              Spacer(flex: 3),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildAndroidButtons() {
    return [
      BuyMeACoffeeButton(buyMeACoffeeName: "ballzoffury"),
      TextButton(
          style: TextButton.styleFrom(
              padding: EdgeInsets.symmetric(horizontal: 30, vertical: 11),
              foregroundColor: Colors.white,
              backgroundColor: Colors.blue
          ),
          child: Text("Support me on Paypal"),
          onPressed: () {
            String url = "https://www.paypal.com/donate/?business=UTF5TNGA8XYP2&no_recurring=0&item_name=To+keep+SnapDrafter+ad-free+and+available+to+as+many+cube-lovers+as+possible.+Your+donation+helps+make+that+happen.&currency_code=EUR";
            launchUrl(Uri.parse(url));
          }
      ),
      PatreonButton(
        patreonName: "ballzoffury",
        style: TextButton.styleFrom(
            foregroundColor: Colors.white,
            backgroundColor: Colors.red
        ),
      ),
    ];
  }

  List<Widget> _buildIosButtons() {
    final iap = DonationIAP.instance;

    if (iap.loading) {
      return const [
        Padding(
          padding: EdgeInsets.all(16),
          child: CircularProgressIndicator(),
        ),
      ];
    }

    if (!iap.available || iap.products.isEmpty) {
      return [
        Text(
          "Donations are currently unavailable in the App Store.",
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14, color: Colors.grey),
        ),
      ];
    }

    return [
      for (final product in iap.products)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: SizedBox(
            width: double.infinity,
            child: TextButton(
              style: TextButton.styleFrom(
                  padding: EdgeInsets.symmetric(horizontal: 30, vertical: 13),
                  foregroundColor: Colors.white,
                  backgroundColor: Colors.blue
              ),
              onPressed: iap.purchasing
                  ? null
                  : () => iap.buyTip(product),
              child: Text("Tip ${product.price}"),
            ),
          ),
        ),
    ];
  }
}
