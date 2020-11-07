import 'dart:typed_data';

import 'package:cashew/bitcoincash/bitcoincash.dart';
import 'package:cashew/wallet/vault.dart';
import 'package:pointycastle/digests/sha256.dart';
import 'package:convert/convert.dart';

import 'keys.dart';
import '../electrum/client.dart';

Uint8List calculateScriptHash(Address address) {
  final scriptPubkey = P2PKHLockBuilder(address).getScriptPubkey();
  final rawScriptPubkey = scriptPubkey.buffer;
  final digest = SHA256Digest().process(rawScriptPubkey);
  final reversedDigest = Uint8List.fromList(digest.reversed.toList());
  return reversedDigest;
}

class Wallet {
  Wallet(this.walletPath, this.electrumFactory, {this.network});

  NetworkType network;
  String walletPath;
  ElectrumFactory electrumFactory;

  Keys keys;
  String bip39Seed;

  Vault _vault = Vault([]);

  final BigInt _feePerByte = BigInt.one;
  int _balance = 0;

  /// Gets the fees per byte.
  Future<BigInt> feePerByte() async {
    // TODO: Refresh from electrum.
    return _feePerByte;
  }

  /// Fetch UTXOs from electrum then update vault.
  Future<void> updateUtxos() async {
    final clientFuture = electrumFactory.build();
    final externalScriptHashes = keys.externalKeys.map((privateKey) {
      final address = privateKey.toAddress(networkType: network);
      return calculateScriptHash(address);
    });
    final changeScriptHashes = keys.changeKeys.map((privateKey) {
      final address = privateKey.toAddress(networkType: network);
      return calculateScriptHash(address);
    });

    final client = await clientFuture;
    final externalFuts = externalScriptHashes.map((scriptHash) {
      final hexScriptHash = hex.encode(scriptHash);
      return client.blockchainScripthashListunspent(hexScriptHash);
    });
    final changeFuts = changeScriptHashes.map((scriptHash) {
      final hexScriptHash = hex.encode(scriptHash);
      return client.blockchainScripthashListunspent(hexScriptHash);
    });
    final externalUnspent = await Future.wait(externalFuts);
    final changeUnspent = await Future.wait(changeFuts);

    // Collect external unspent
    var keyIndex = 0;
    for (final unspentList in externalUnspent) {
      for (final unspent in unspentList) {
        final outpoint =
            Outpoint(unspent.tx_hash, unspent.tx_pos, unspent.value);

        final spendable = Utxo(outpoint, true, keyIndex);

        _vault.add(spendable);
      }
      keyIndex += 1;
    }

    // Collect change unspent
    keyIndex = 0;
    for (final unspentList in changeUnspent) {
      for (final unspent in unspentList) {
        final outpoint =
            Outpoint(unspent.tx_hash, unspent.tx_pos, unspent.value);

        final spendable = Utxo(outpoint, false, keyIndex);

        _vault.add(spendable);
      }
      keyIndex += 1;
    }
  }

  /// Use locally stored UTXOs to refresh balance.
  void refreshBalanceLocal() {
    _balance = _vault.calculateBalance().toInt();
  }

  /// Use electrum to refresh balance.
  Future<void> refreshBalanceRemote() async {
    final clientFuture = electrumFactory.build();

    final externalScriptHashes = keys.externalKeys.map((privateKey) {
      final address = privateKey.toAddress(networkType: network);
      return calculateScriptHash(address);
    });
    final changeScriptHashes = keys.changeKeys.map((privateKey) {
      final address = privateKey.toAddress(networkType: network);
      return calculateScriptHash(address);
    });
    final scriptHashes = externalScriptHashes.followedBy(changeScriptHashes);

    final client = await clientFuture;
    final responses = await Future.wait(scriptHashes.map((scriptHash) {
      final scriptHashHex = hex.encode(scriptHash);
      return client.blockchainScripthashGetBalance(scriptHashHex);
    }));

    final totalBalance = responses
        .map((response) => response.confirmed + response.unconfirmed)
        .fold(0, (p, c) => p + c);
    _balance = totalBalance;
  }

  /// Read wallet file from disk. Returns true if successful.
  Future<bool> loadFromDisk() async {
    // TODO
    return false;
  }

  Future<void> writeToDisk() async {
    // TODO
  }

  /// Generate new random seed.
  String newSeed() {
    // TODO: Randomize and can we move to bytes
    // rather than string (crypto API awkard)?
    return 'festival shrimp feel before tackle pyramid immense banner fire wash steel fiscal';
  }

  /// Generate new wallet from scratch.
  Future<void> generateWallet() async {
    bip39Seed = newSeed();
    keys = await Keys.construct(bip39Seed);
  }

  /// Attempts to load wallet from disk, else constructs a new wallet.
  Future<void> initialize() async {
    final loaded = await loadFromDisk();
    if (!loaded) {
      await generateWallet();
    }
  }

  /// Use electrum to update wallet.
  Future<void> updateWallet() async {}

  int balanceSatoshis() {
    return _balance;
  }

  Transaction _constructTransaction(Address recipientAddress, BigInt amount) {
    final feePerInput = BigInt.from(130);
    final baseFee = BigInt.one;

    // Collect UTXOs required for transaction
    final utxos = _vault.collectUtxos(amount, baseFee, feePerInput);

    var tx = Transaction();
    var privateKeys = [];

    // Add inputs
    for (final utxo in utxos) {
      // Get private key from store
      BCHPrivateKey privateKey;
      if (utxo.externalOutput) {
        privateKey = keys.externalKeys[utxo.keyIndex];
      } else {
        privateKey = keys.changeKeys[utxo.keyIndex];
      }
      privateKeys.add(privateKey);

      // Create input
      final address = privateKey.toAddress(networkType: network);
      tx = tx.spendFromMap({
        'satoshis': utxo.outpoint.amount,
        'txId': utxo.outpoint.transactionId,
        'outputIndex': utxo.outpoint.vout,
        'scriptPubKey': P2PKHLockBuilder(address).getScriptPubkey().toHex()
      });
    }
    final changeAddress = keys.getChangeAddress(0);
    tx = tx.spendTo(recipientAddress, amount);
    tx = tx.sendChangeTo(changeAddress);

    // Sign transaction
    privateKeys.asMap().forEach((index, privateKey) {
      tx.signInput(index, privateKey);
    });

    return tx;
  }

  Future<Transaction> sendTransaction(
      Address recipientAddress, BigInt amount) async {
    final clientFuture = electrumFactory.build();
    final transaction = _constructTransaction(recipientAddress, amount);

    final transactionHex = transaction.serialize();
    final client = await clientFuture;

    await client.blockchainTransactionBroadcast(transactionHex);
    return transaction;
  }
}
