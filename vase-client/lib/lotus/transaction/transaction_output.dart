import 'dart:typed_data';

import 'package:buffer/buffer.dart';
import 'package:hex/hex.dart';
import 'package:sprintf/sprintf.dart';

import '../encoding/utils.dart';
import '../script/bchscript.dart';
import '../script/opcodes.dart';
import '../constants.dart';

import 'locking_script_builder.dart';
import 'default_builder.dart';

/// Class that represents the output (UTXO) of a transaction.
///
/// When creating new transactions, the outputs can be :
///
/// 1) Locked up for another recipient to spend
/// 2) Locked up for ourselves to spend
/// 3) Represented as a "data" transaction by using `OP_FALSE OP_RETURN <data>` in the script
/// 4) Represents any arbitrary bitcoin script on the BSV network after the Genesis restoration
/// in February 2020.
///
class TransactionOutput {
  BigInt _satoshis = BigInt.zero;
  String? _transactionId;
  int? _outputIndex;
  bool _isChangeOutput = false;

  LockingScriptBuilder? _scriptBuilder;

  /// The default constructor. Initializes a "clean slate" output.
  TransactionOutput({LockingScriptBuilder? scriptBuilder}) {
    _scriptBuilder = scriptBuilder ??= DefaultLockBuilder();
  }

  // TODO: FIX This should be default constructor
  // TransactionOutput(this._satoshis, this._script, this._outputIndex, this._transactionId);

  /// Constructs a new Transaction output from a ByteDataReader that
  /// has been initialized with the raw transaction output data.
  ///
  /// This method is useful when iteratively reading the transaction
  /// outputs in a raw transaction, which is also how it is currently
  /// being used.
  TransactionOutput.fromReader(ByteDataReader reader,
      {LockingScriptBuilder? scriptBuilder}) {
    _scriptBuilder = scriptBuilder ??= DefaultLockBuilder();

    satoshis = BigInt.from(reader.readUint64(Endian.little));
    var size = readVarIntNum(reader);
    if (size != 0) {
      var script = BCHScript.fromBuffer(reader.read(size, copy: true));
      _scriptBuilder!.fromScript(script);
    } else {
      var script = BCHScript.fromBuffer(Uint8List(0));
      _scriptBuilder!.fromScript(script);
    }
  }

  /// Returns true is satoshi amount if outside of valid range
  ///
  /// See [MAX_MONEY]
  bool invalidSatoshis() {
    if (_satoshis < BigInt.zero) {
      return true;
    }

    if (_satoshis > MAX_MONEY) {
      return true;
    }

    return false;
  }

  /// Returns a byte array containing the raw transaction output
  List<int> serialize() {
    var buffer = <int>[];

    // add value in satoshis - 8 bytes BigInt
    // lazy way to get to 8 byte padding
    var satArr = sprintf('%016s', [_satoshis.abs().toRadixString(16)]);
    // hack around sprintf not padding zeros
    satArr = satArr.replaceAll(' ', '0');
    buffer.addAll(HEX.decode(satArr).reversed.toList());

    // add scriptPubKey size - varInt
    var scriptHex = HEX.decode(script.toHex());
    var varIntVal = varintBufNum(scriptHex.length);
    buffer.addAll(varIntVal);

    // add scriptPubKey hex
    buffer.addAll(scriptHex);

    return buffer;
  }

  /// Returns the Transaction output as structured data to make
  /// working with JSON serializers easier.
  Map<String, dynamic> toObject() {
    return {
      'satoshis': _satoshis.toInt(),
      'script': _scriptBuilder!.getScriptPubkey().toHex()
    };
  }

  /// Returns the output script in it's raw hexadecimal form
  String get scriptHex {
    return _scriptBuilder!.getScriptPubkey().toHex();
  }

  /// Returns the output script as a [BCHScript] instance
  BCHScript get script => _scriptBuilder!.getScriptPubkey();

  /// Sets the output script to the provided value
  set script(BCHScript script) {
    _scriptBuilder!.fromScript(script);
  }

  /// Returns the number of satoshis the output is sending
  BigInt get satoshis => _satoshis;

  /// Sets the number of satoshis the output is sending
  set satoshis(BigInt value) {
    _satoshis = value;
  }

  /// Returns the transactionId of the transaction this output belongs to
  String? get transactionId => _transactionId;

  /// Sets the transactionId of the transaction this output belongs to
  set transactionId(String? value) {
    _transactionId = value;
  }

  /// Returns the index of the (UTXO) in the transaction this output belongs to
  int? get outputIndex => _outputIndex;

  /// sets the index of the (UTXO) in the transaction this output belongs to
  set outputIndex(int? value) {
    _outputIndex = value;
  }

  /// Convenience property to check if this output has been made unspendable
  /// using either an OP_RETURN or "OP_FALSE OP_RETURN" in first positions of
  /// the script.
  ///
  ///
  bool get isDataOut {
    var scriptChunks = scriptBuilder!.getScriptPubkey().chunks;
    if (scriptChunks.isNotEmpty &&
        scriptChunks[0].opcodenum == OpCodes.OP_FALSE) {
      // safe data out
      return scriptChunks.length >= 2 &&
          scriptChunks[1].opcodenum == OpCodes.OP_RETURN;
    } else if (scriptChunks[0].opcodenum == OpCodes.OP_RETURN) {
      // older unsafe data output
      return true;
    }

    return false;
  }

  /// Returns true if this output is meant to generate change back
  /// the person creating the transaction this output will belong to.
  bool get isChangeOutput => _isChangeOutput;

  /// Set to true if this output is meant to generate change back
  /// the person creating the transaction this output will belong to.
  set isChangeOutput(bool value) {
    _isChangeOutput = value;
  }

  /// Returns the current instance of LockingScriptBuilder in use by this instance
  LockingScriptBuilder? get scriptBuilder => _scriptBuilder;
}
