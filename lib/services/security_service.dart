import 'package:encrypt/encrypt.dart' as encrypt;
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'windows_secure_storage.dart';

/// Service for handling secure storage of sensitive information
/// and encryption/decryption of data.
class SecurityService {
  // Singleton pattern
  static final SecurityService _instance = SecurityService._internal();
  factory SecurityService() => _instance;
  SecurityService._internal();

  static const String _apiKeyName = 'gemini_api_key';
  static const String _aesKeyName = 'aes_encryption_key';
  static const String _modelNameKey = 'gemini_model_name';

  encrypt.Key? _encryptionKey;
  encrypt.Encrypter? _encrypter;

  Future<void> _writeSecure(String key, String value) async {
    await WindowsSecureStorage.write(key, value);
  }

  Future<String?> _readSecure(String key) async {
    return await WindowsSecureStorage.read(key);
  }

  /// Initializes the SecurityService by loading or generating the AES key.
  /// This should be called before any encryption/decryption operations.
  Future<void> init() async {
    try {
      String? storedKey = await _readSecure(_aesKeyName);

      if (storedKey == null) {
        // Requirement: Generate a random 32-character AES key if one doesn't exist.
        // We generate a 32-character random string to be used as a 256-bit key.
        storedKey = _generateRandom32CharString();
        await _writeSecure(_aesKeyName, storedKey);
      }

      // AES-256 requires a 32-byte key. 32 UTF-8 characters = 32 bytes (if ASCII).
      _encryptionKey = encrypt.Key.fromUtf8(storedKey);
      _encrypter = encrypt.Encrypter(encrypt.AES(_encryptionKey!));
    } catch (e) {
      throw Exception('Failed to initialize SecurityService: $e');
    }
  }

  /// Generates a random 32-character string.
  String _generateRandom32CharString() {
    const chars = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final rnd = Random.secure();
    return String.fromCharCodes(Iterable.generate(
        32, (_) => chars.codeUnitAt(rnd.nextInt(chars.length))));
  }

  /// Securely saves the Gemini API key.
  Future<void> saveApiKey(String key) async {
    try {
      await _writeSecure(_apiKeyName, key);
    } catch (e) {
      throw Exception('Failed to save API key: $e');
    }
  }

  /// Retrieves the securely stored Gemini API key.
  Future<String?> getApiKey() async {
    try {
      return await _readSecure(_apiKeyName);
    } catch (e) {
      throw Exception('Failed to retrieve API key: $e');
    }
  }

  /// Securely saves the selected Gemini model name.
  Future<void> saveModelName(String model) async {
    try {
      await _writeSecure(_modelNameKey, model);
    } catch (e) {
      throw Exception('Failed to save model name: $e');
    }
  }

  /// Retrieves the securely stored Gemini model name.
  /// Defaults to 'gemini-1.5-flash' if not set.
  Future<String> getModelName() async {
    try {
      final model = await _readSecure(_modelNameKey);
      return model ?? 'gemini-1.5-flash';
    } catch (e) {
      debugPrint('Error retrieving model name: $e');
      return 'gemini-1.5-flash';
    }
  }

  /// Encrypts plain text using AES and returns a Base64 encoded string.
  /// Prepends the IV to the encrypted data: "ivBase64:encryptedBase64"
  String encryptData(String plainText) {
    if (_encrypter == null) {
      throw Exception('SecurityService not initialized. Call init() first.');
    }
    
    try {
      final iv = encrypt.IV.fromSecureRandom(16);
      final encrypted = _encrypter!.encrypt(plainText, iv: iv);
      
      // Combine IV and encrypted data with a separator for storage.
      // Both are already base64 encoded by the encrypt package.
      return '${iv.base64}:${encrypted.base64}';
    } catch (e) {
      throw Exception('Encryption failed: $e');
    }
  }

  /// Decrypts data encrypted by [encryptData].
  /// Expects a string in the format "ivBase64:encryptedBase64".
  String decryptData(String encryptedText) {
    if (_encrypter == null) {
      throw Exception('SecurityService not initialized. Call init() first.');
    }
    
    try {
      final parts = encryptedText.split(':');
      if (parts.length != 2) {
        throw const FormatException('Invalid encrypted data format. Expected "iv:data"');
      }
      
      final iv = encrypt.IV.fromBase64(parts[0]);
      final encryptedData = parts[1];
      
      return _encrypter!.decrypt64(encryptedData, iv: iv);
    } catch (e) {
      throw Exception('Decryption failed: $e');
    }
  }
}
