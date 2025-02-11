import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:vase/lotus/lotus.dart';

import '../keys.dart';

part 'keys.g.dart';

const KEYS_KEY_PREFIX = 'keys_';
const METADATA = 'metadata';

@JsonSerializable()
class KeyStorageMetadata {
  KeyStorageMetadata(this.keyCount);

  int? keyCount;

  static String _getDatabaseKey() {
    return KEYS_KEY_PREFIX + METADATA;
  }

  static Future<KeyStorageMetadata> readFromDisk() async {
    const storage = FlutterSecureStorage();
    final storageMetadataString =
        await (storage.read(key: _getDatabaseKey())) ?? '';
    final storageMetadataJson = jsonDecode(storageMetadataString);
    return KeyStorageMetadata.fromJson(storageMetadataJson);
  }

  Future<void> writeToDisk() async {
    const storage = FlutterSecureStorage();
    final serialized = jsonEncode(toJson());
    await storage.write(key: _getDatabaseKey(), value: serialized);
  }

  factory KeyStorageMetadata.fromJson(Map<String, dynamic> json) =>
      _$KeyStorageMetadataFromJson(json);
  Map<String, dynamic> toJson() => _$KeyStorageMetadataToJson(this);
}

@JsonSerializable()
class StoredKey {
  StoredKey(this.privateKey, this.isChange);

  String? privateKey;
  bool? isChange;

  static String _getDatabaseKey(int number) {
    return KEYS_KEY_PREFIX + number.toString();
  }

  factory StoredKey.fromKeyInfo(KeyInfo keyInfo) {
    return StoredKey(keyInfo.key.toWIF(), keyInfo.isChange);
  }

  static Future<StoredKey> readFromDisk(int number) async {
    const storage = FlutterSecureStorage();
    final storageMetadataString =
        await (storage.read(key: _getDatabaseKey(number))) ?? '';
    final storageMetadataJson = jsonDecode(storageMetadataString);
    return StoredKey.fromJson(storageMetadataJson);
  }

  Future<void> writeToDisk(int number) async {
    const storage = FlutterSecureStorage();
    final serialized = jsonEncode(toJson());
    await storage.write(key: _getDatabaseKey(number), value: serialized);
  }

  KeyInfo toKeyInfo(NetworkType network) {
    final key = BCHPrivateKey.fromWIF(privateKey!);
    return KeyInfo(key: key, isChange: isChange, network: network);
  }

  factory StoredKey.fromJson(Map<String, dynamic> json) =>
      _$StoredKeyFromJson(json);
  Map<String, dynamic> toJson() => _$StoredKeyToJson(this);
}
