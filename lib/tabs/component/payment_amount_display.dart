import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class PaymentAmountDisplay extends StatelessWidget {
  final String amount;
  final String function;
  PaymentAmountDisplay({Key key, this.amount, this.function})
      : super(
          key: key,
        );

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Row(children: [
        Expanded(
            child: Text(
          '${function}',
          style: TextStyle(
              fontSize: Theme.of(context).textTheme.headline5.fontSize,
              fontWeight: FontWeight.bold),
        ))
      ]),
      Row(children: [
        Expanded(
            child: Text(
          '= ${amount} sats',
          textAlign: TextAlign.right,
          style: TextStyle(
              fontSize: Theme.of(context).textTheme.headline5.fontSize,
              fontWeight: FontWeight.bold),
        ))
      ]),
    ]);
  }
}