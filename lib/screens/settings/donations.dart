import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'package:flutter_donation_buttons/flutter_donation_buttons.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

class DonationScreen extends StatefulWidget {
  const DonationScreen({super.key});

  @override
  State<DonationScreen> createState() => DonationScreenState();
}

class DonationScreenState extends State<DonationScreen> {

  List<ProductDetails> donationOptions = [];
  Set<String> donationProductIds = {
    "donate_5_once",
    "donate_10_once",
    "donate_2_monthly",
    "donate_3_monthly",
    "donate_5_monthly"
  };

  @override
  void initState() {
    super.initState();
    if (Platform.isIOS) {
      loadInAppPurchases();
    }
  }

  Future loadInAppPurchases() async {
    ProductDetailsResponse response = await InAppPurchase.instance.queryProductDetails(donationProductIds);
    donationOptions = response.productDetails;
  }

  Widget purchaseButton(ProductDetails productDetails) {

    final buttonStyle = ElevatedButton.styleFrom(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
      ),
    );

    final String buttonText = productDetails.price;
    PurchaseParam purchaseParam = PurchaseParam(productDetails: productDetails);

    return ElevatedButton(
      onPressed: () => InAppPurchase.instance.buyConsumable(purchaseParam: purchaseParam),
      style: buttonStyle,
      child: Text(
        buttonText,
        style: TextStyle(
            fontSize: 20
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {

    String donationText = "If you are enjoying this app and want to support "
      "it's continued maintenance and development, consider donating."
      "\n\n"
      "My aim is to keep SnapDrafter free, ad-free, and available to as many "
        "cube-lovers as possible. \n\nDonations like yours help make that happen.";

    List<Widget> widgets = [
      Spacer(flex: 3,),
      Text(donationText,
        textAlign: TextAlign.center,
        style: TextStyle(
            fontSize: 16
        ),
      ),
    ];
    if (Platform.isIOS) {
      widgets.addAll([
        Spacer(flex: 1),
        Wrap(
          spacing: 5,
          children: donationOptions.map((el) => purchaseButton(el)).toList(),
        ),
        Spacer(flex: 3,)
      ]);
    } else {
      widgets.addAll([
        Spacer(flex: 1),
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
        Spacer(flex: 3)
      ]);
    }

    return Scaffold(
      appBar: AppBar(title: const Text("Donation")),
      body: Container(
        padding: EdgeInsets.symmetric(vertical: 50, horizontal: 50),
        child: Center(
            child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: widgets
            )
        )
      )
    );
  }
}