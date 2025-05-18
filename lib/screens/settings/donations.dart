import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'package:flutter_donation_buttons/flutter_donation_buttons.dart';
import 'package:url_launcher/url_launcher.dart';

class DonationScreen extends StatelessWidget {

  @override
  Widget build(BuildContext context) {

    String donationText = "If you are enjoying this app and want to support "
      "it's continued maintenance and development, consider donating."
      "\n\n"
      "My aim is to keep SnapDrafter ad-free and available to as many cube-lovers"
        " as possible. \n\nDonations like yours help make that happen.";

    return Scaffold(
      appBar: AppBar(title: const Text("Donation")),
      body: Container(
        padding: EdgeInsets.symmetric(vertical: 50, horizontal: 50),
        child: Center(
            child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Spacer(flex: 3,),
                  Text(donationText,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 16
                    ),
                  ),
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
                ]
            )
        )
      )
    );
  }
}