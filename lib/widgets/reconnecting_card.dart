import 'package:flutter/material.dart';

class ReconnectingCard extends StatelessWidget {
  const ReconnectingCard({super.key});

  @override
  Widget build(BuildContext context) {
    return const Card(
      color: Colors.orange,
      child: Padding(
        padding: EdgeInsets.all(12),
        child: Row(
          children: [
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            ),
            SizedBox(width: 12),
            Text(
              'Reconnecting...',
              style: TextStyle(color: Colors.white),
            ),
          ],
        ),
      ),
    );
  }
}
