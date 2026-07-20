import 'package:flutter/material.dart';

class DraftInfoRow extends StatelessWidget {
  final String label;
  final String value;
  final double labelWidth;
  final bool monospace;

  const DraftInfoRow({
    super.key,
    required this.label,
    required this.value,
    this.labelWidth = 110,
    this.monospace = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: labelWidth,
            child: Text('$label:',
                style: const TextStyle(fontSize: 12, color: Colors.grey)),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 12,
                fontFamily: monospace ? 'monospace' : null,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
