import 'dart:typed_data';

import './asn1_tags.dart';

///
/// Utils class holding different methods to ease the handling of ANS1Objects and their byte representation.
///
class ASN1Utils {
  static final _byteMask = BigInt.from(0xff);
  static final negativeFlag = BigInt.from(0x80);

  /// Decode a BigInt from bytes in big-endian encoding.
  static BigInt decodeBigInt(List<int> bytes) {
    var result = BigInt.from(0);
    final isNegative = bytes[0] & 0x80 == 0x80;
    bytes[0] = ~0x80 & bytes[0];
    for (var i = 0; i < bytes.length; i++) {
      result += BigInt.from(bytes[bytes.length - i - 1]) << (8 * i);
    }
    if (isNegative) {
      result *= -BigInt.one;
    }
    return result;
  }

  /// Encode a BigInt into bytes using big-endian encoding.
  static Uint8List encodeBigInt(BigInt number) {
    // Not handling negative numbers. Decide how you want to do that.
    var rawSize = (number.bitLength + 7) >> 3;
    // If the first byte has 0x80 set, we need an extra byte
    final needsPaddingByte = number > BigInt.from(0) &&
            ((number >> (rawSize - 1) * 8) & negativeFlag) == negativeFlag
        ? 1
        : 0;

    final size = rawSize + needsPaddingByte;
    var result = Uint8List(size);
    for (var i = 0; i < rawSize; i++) {
      result[size - i - 1] = (number & _byteMask).toInt();
      number = number >> 8;
    }
    if (number < BigInt.zero) {
      result[0] |= 0x80;
    }
    return result;
  }

  ///
  /// Calculates the start position of the value bytes for the given [encodedBytes].
  ///
  /// It will return 2 if the **length byte** is less than 127 or the length calculate on the **length byte** value.
  /// This will throw a [RangeError] if the given [encodedBytes] has length < 2.
  ///
  static int calculateValueStartPosition(Uint8List encodedBytes) {
    var length = encodedBytes[1];
    if (length < 0x7F) {
      return 2;
    } else {
      return 2 + (length & 0x7F);
    }
  }

  ///
  /// Calculates the length of the **value bytes** for the given [encodedBytes].
  ///
  /// Will return **-1** if the length byte equals **0x80**. Throws an [ArgumentError] if the length could not be calculated for the given [encodedBytes].
  ///
  static int decodeLength(Uint8List encodedBytes) {
    var valueStartPosition = 2;
    var length = encodedBytes[1];
    if (length < 0x7F) {
      return length;
    }
    if (length == 0x80) {
      return -1;
    }
    if (length > 127) {
      var length = encodedBytes[1] & 0x7F;

      var numLengthBytes = length;

      length = 0;
      for (var i = 0; i < numLengthBytes; i++) {
        length <<= 8;
        length |= (encodedBytes[valueStartPosition++] & 0xFF);
      }
      return length;
    }
    throw ArgumentError('Could not calculate the length from the given bytes.');
  }

  ///
  /// Encode the given [length] to byte representation.
  ///
  static Uint8List encodeLength(int length, {bool longform = false}) {
    Uint8List e;
    if (length <= 127 && longform == false) {
      e = Uint8List(1);
      e[0] = length;
    } else {
      var x = Uint32List(1);
      x[0] = length;
      var y = Uint8List.view(x.buffer);
      // Skip null bytes
      var num = 3;
      while (y[num] == 0) {
        --num;
      }
      e = Uint8List(num + 2);
      e[0] = 0x80 + num + 1;
      for (var i = 1; i < e.length; ++i) {
        e[i] = y[num--];
      }
    }
    return e;
  }

  ///
  /// Checks if the given int [i] is constructed according to <https://www.bouncycastle.org/asn1_layman_93.txt> section 3.2.
  ///
  /// The Identifier octets (represented by the given [i]) is marked as constructed if bit 6 has the value **1**.
  ///
  /// Example with the IA5 String tag:
  ///
  /// 0x36 = 0 0 1 1 0 1 1 0
  ///
  /// 0x16 = 0 0 0 1 0 1 1 0
  /// ```
  /// ASN1Utils.isConstructed(0x36);  // true
  /// ASN1Utils.isConstructed(0x16);  // false
  /// ```
  ///
  ///
  static bool isConstructed(int i) {
    // Shift bits
    var newNum = i >> (6 - 1);
    // Check if bit is set to 1
    return (newNum & 1) == 1;
  }

  static bool isASN1Tag(int i) {
    return ASN1Tags.TAGS.contains(i);
  }

  ///
  /// Checks if the given [bytes] ends with 0x00, 0x00
  ///
  static bool hasIndefiniteLengthEnding(Uint8List bytes) {
    var last = bytes.elementAt(bytes.length - 1);
    var lastMinus1 = bytes.elementAt(bytes.length - 2);
    if (last == 0 && lastMinus1 == 0) {
      return true;
    }
    return false;
  }
}
