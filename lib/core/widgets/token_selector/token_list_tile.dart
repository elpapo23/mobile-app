import 'dart:ui';

import 'package:deus_mobile/models/swap/crypto_currency.dart';
import 'package:deus_mobile/routes/navigation_service.dart';
import 'package:deus_mobile/service/ethereum_service.dart';
import 'package:deus_mobile/statics/styles.dart';
import 'package:flutter/material.dart';

import '../../../locator.dart';
import '../../../models/token.dart';

class TokenListTile extends StatelessWidget {
  final CryptoCurrency currency;

  TokenListTile({@required this.currency});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: () {
        locator<NavigationService>().goBack(context, currency);
      },
      contentPadding: const EdgeInsets.all(0),
      leading: currency.logoPath.showCircleImage(),
      title: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text(currency.symbol,maxLines: 1,overflow: TextOverflow.ellipsis, style: MyStyles.whiteMediumTextStyle), //const TextStyle(fontSize: 25, height: 0.99999)
          const SizedBox(
            width: 15,
          ),
          Text(currency.name, maxLines: 1,overflow: TextOverflow.ellipsis, style: MyStyles.lightWhiteSmallTextStyle), //  const TextStyle(fontSize: 15, height: 0.99999)
        ],
      ),
      trailing: Text(
        EthereumService.formatDouble(currency.balance??"0.0"),
        style: MyStyles.whiteSmallTextStyle,
      ),
    );
  }
}
