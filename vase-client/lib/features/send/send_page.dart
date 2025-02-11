import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:slide_to_confirm/slide_to_confirm.dart';
import 'package:vase/config/colors.dart';
import 'package:vase/config/theme.dart';
import 'package:vase/features/numpad/numpad_view.dart';
import 'package:vase/features/send/qr_view.dart';
import 'package:vase/features/send/send_model.dart';
import 'package:vase/features/wallet/wallet_model.dart';
import 'package:vase/lotus/lotus.dart';
import 'package:vase/lotus/utils/parse_uri.dart';
import 'package:vase/utils/currency.dart';

import '../numpad/numpad_model.dart';

final qrKey = GlobalKey(debugLabel: 'QR');

class SendPage extends HookWidget {
  const SendPage({Key? key}) : super(key: key);

  void _showSnackBar(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sendModel = context.watch<SendModel>();
    final amountCtrl = useTextEditingController();
    final addressCtrl = useTextEditingController();

    amountCtrl.text = sendModel.amount > BigInt.zero
        ? formatAmount(amount: sendModel.amount)
        : '';
    addressCtrl.text = sendModel.address;
    final sendEnabled =
        amountCtrl.text.isNotEmpty && addressCtrl.text.isNotEmpty;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          splashRadius: AppTheme.splashRadius,
          onPressed: () => context.pop(),
          icon: const Icon(Icons.navigate_before),
        ),
        title: const Text('Send'),
        centerTitle: true,
      ),
      body: Center(
        child: Column(
          children: [
            Expanded(
              child: QRView(
                onScanResult: (String? result) {
                  if (result == null) {
                    return;
                  }

                  final parseResult = parseSendURI(result);
                  final address = parseResult.address;
                  final amount = parseResult.amount;

                  if (address.isEmpty) {
                    _showSnackBar(context, 'Unable to parse QR code');
                    return;
                  }

                  sendModel.setAddress(address);

                  if (sendModel.amount == BigInt.zero) {
                    sendModel.setAmount(amount);
                  }
                },
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    InkWell(
                      onTap: () {
                        final sendModel = context.read<SendModel>();
                        final numpadModel = context.read<NumpadModel>();
                        numpadModel.setValue(satsToLotus(sendModel.amount));
                        showModalBottomSheet(
                          isScrollControlled: true,
                          context: context,
                          builder: (ctx) => ConstrainedBox(
                            constraints: const BoxConstraints(
                              maxHeight: 600,
                            ),
                            child: NumpadView(
                              onDoneTap: () {
                                Navigator.of(ctx).pop();
                              },
                            ),
                          ),
                        );
                      },
                      child: Row(
                        children: [
                          Expanded(
                            child: IgnorePointer(
                              child: TextField(
                                minLines: 1,
                                maxLines: 2,
                                readOnly: true,
                                decoration: const InputDecoration(
                                  labelText: 'Amount',
                                  floatingLabelBehavior:
                                      FloatingLabelBehavior.always,
                                  hintText: 'Enter or scan qr code',
                                  labelStyle:
                                      TextStyle(color: AppColors.lotusPink),
                                  border: InputBorder.none,
                                ),
                                controller: amountCtrl,
                              ),
                            ),
                          ),
                          if (amountCtrl.text.isNotEmpty)
                            IconButton(
                              splashRadius: AppTheme.splashRadius,
                              icon: const Icon(
                                Icons.close,
                                color: Colors.white70,
                              ),
                              onPressed: () {
                                sendModel.setAmount(BigInt.zero);
                              },
                            )
                        ],
                      ),
                    ),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: TextField(
                            minLines: 1,
                            maxLines: 2,
                            readOnly: true,
                            decoration: InputDecoration(
                              labelText: 'Address',
                              floatingLabelBehavior:
                                  FloatingLabelBehavior.always,
                              hintText: 'Paste or scan qr code',
                              labelStyle:
                                  const TextStyle(color: AppColors.lotusPink),
                              border: InputBorder.none,
                              suffixIcon: addressCtrl.text.isNotEmpty
                                  ? IconButton(
                                      splashRadius: AppTheme.splashRadius,
                                      icon: const Icon(
                                        Icons.close,
                                        color: Colors.white70,
                                      ),
                                      onPressed: () {
                                        sendModel.setAddress("");
                                      },
                                    )
                                  : null,
                            ),
                            controller: addressCtrl,
                            onChanged: (String value) {
                              sendModel.setAddress(value);
                            },
                          ),
                        ),
                        const SizedBox(width: 16),
                        TextButton(
                          style: TextButton.styleFrom(
                            backgroundColor: Colors.white24,
                            shape: const CircleBorder(),
                            padding: const EdgeInsets.all(12),
                            elevation: 0,
                          ),
                          onPressed: () async {
                            final data = await Clipboard.getData('text/plain');
                            sendModel.setAddress(data?.text ?? '');
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Pasted address from clipboard'),
                                duration: Duration(seconds: 3),
                              ),
                            );
                          },
                          child: const Icon(
                            Icons.paste,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        child: const Icon(
          Icons.check,
          color: Colors.white,
        ),
        backgroundColor: sendEnabled ? AppColors.lotusPink : Colors.grey,
        elevation: sendEnabled ? 1 : 0,
        onPressed: sendEnabled
            ? () {
                showModalBottomSheet(
                  context: context,
                  builder: (context) {
                    return const TransactionModal();
                  },
                );
              }
            : null,
      ),
    );
  }
}

class TransactionModal extends HookWidget {
  const TransactionModal({
    Key? key,
  }) : super(key: key);

  Future<Transaction?> _sendTransaction(
      BuildContext context, String address, BigInt amount) async {
    try {
      final walletModel = context.read<WalletModel>();
      return await walletModel.wallet
          ?.sendTransaction(Address(address), amount);
    } on AppException catch (e) {
      _showSnackBar(context, e.message);
    } catch (error) {
      _showSnackBar(context, error.toString());
    }
    return null;
  }

  void _showSnackBar(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 3)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final loading = useState(false);
    final success = useState(false);
    final error = useState(false);
    final txIdCtrl = useTextEditingController();
    final sendModel = context.watch<SendModel>();
    final amount = sendModel.amount;
    final address = sendModel.address;
    return ConstrainedBox(
      constraints: success.value
          ? const BoxConstraints(maxHeight: 300)
          : const BoxConstraints(maxHeight: 200),
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Center(
              child: loading.value
                  ? const CircularProgressIndicator()
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (success.value) ...[
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: const ShapeDecoration(
                              color: Colors.green,
                              shape: CircleBorder(),
                            ),
                            child: const Icon(
                              Icons.check,
                              size: 56,
                            ),
                          ),
                          const SizedBox(height: 16),
                          const Text('Transaction sent!'),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Expanded(
                                child: TextField(
                                  maxLines: 2,
                                  readOnly: true,
                                  decoration: const InputDecoration(
                                    labelText: 'TxId',
                                    labelStyle:
                                        TextStyle(color: AppColors.lotusPink),
                                    border: InputBorder.none,
                                  ),
                                  controller: txIdCtrl,
                                ),
                              ),
                              const SizedBox(width: 16),
                              ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  shape: const CircleBorder(),
                                  padding: const EdgeInsets.all(12),
                                  elevation: 0,
                                ),
                                onPressed: () {
                                  Clipboard.setData(
                                    ClipboardData(
                                      text: txIdCtrl.text,
                                    ),
                                  );
                                  _showSnackBar(
                                    context,
                                    'Copied txId to clipboard',
                                  );
                                },
                                child: const Icon(
                                  Icons.copy,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          )
                        ] else ...[
                          if (error.value) ...[
                            const Text(
                              'Error sending transaction.\nPlease try again',
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 16),
                          ],
                          ConfirmationSlider(
                            foregroundColor: AppColors.lotusGrey,
                            textStyle: const TextStyle(color: Colors.black),
                            shadow: const BoxShadow(),
                            sliderButtonContent: Image.asset(
                              'assets/images/logo.png',
                            ),
                            onConfirmation: () async {
                              loading.value = true;

                              final transaction = await _sendTransaction(
                                context,
                                address,
                                amount,
                              );

                              if (transaction != null) {
                                txIdCtrl.text = transaction.id ?? '';
                                success.value = true;
                              } else {
                                error.value = true;
                              }
                              loading.value = false;
                            },
                          ),
                        ]
                      ],
                    ),
            ),
          ),
          const IgnorePointer(
            child: Scaffold(
              backgroundColor: Colors.transparent,
            ),
          ),
        ],
      ),
    );
  }
}
