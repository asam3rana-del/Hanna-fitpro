import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

import '../db/gym_repo.dart';
import 'app_lock.dart';

/// Member ki tasveer: chhoti JPEG (≈20 KB) base64 ki surat mein DB mein — is tarah cloud sync ke saath
/// doosre phone / PC par bhi pohnch jati hai. List mein sirf zaroorat par load (cache).
class PhotoService {
  PhotoService._();

  static final Map<String, Uint8List?> _cache = {};
  static final ValueNotifier<int> changes = ValueNotifier<int>(0);

  static Future<Uint8List?> bytesFor(String memberId) async {
    if (_cache.containsKey(memberId)) return _cache[memberId];
    Uint8List? bytes;
    try {
      final b64 = await MemberRepo.photo(memberId);
      if (b64 != null) bytes = base64Decode(b64);
    } catch (_) {
      bytes = null;
    }
    _cache[memberId] = bytes;
    return bytes;
  }

  static void invalidate(String memberId) {
    _cache.remove(memberId);
    changes.value++;
  }

  static void clearAll() {
    _cache.clear();
    changes.value++;
  }

  /// Camera / gallery se. Cancel / masla => null. Wapas: base64 JPEG.
  static Future<String?> pick(ImageSource source, {double maxSide = 360, int quality = 72}) async {
    final picker = ImagePicker();
    AppLock.instance.suspendLock = true;
    try {
      XFile? x = await picker.pickImage(source: source, maxWidth: maxSide, maxHeight: maxSide, imageQuality: quality);
      if (x == null && defaultTargetPlatform == TargetPlatform.android) {
        try {
          final lost = await picker.retrieveLostData();
          if (!lost.isEmpty && lost.file != null) x = lost.file;
        } catch (_) {}
      }
      if (x == null) return null;
      final bytes = await x.readAsBytes();
      if (bytes.isEmpty) return null;
      return base64Encode(bytes);
    } catch (_) {
      return null;
    } finally {
      AppLock.instance.suspendLock = false;
    }
  }
}
