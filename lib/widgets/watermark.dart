import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../db/gym_db.dart';
import '../db/user_repository.dart';

/// Gym ka banner / logo dashboard par halka sa watermark (Settings > Gym profile se).
/// Touch ko nahi rokta; sync se doosre devices par bhi pohnchta hai.
class GymWatermark extends StatelessWidget {
  const GymWatermark({super.key});

  /// Settings se badalne par foran naya dikhe.
  static final ValueNotifier<int> changes = ValueNotifier<int>(0);

  static int _key = 0;
  static Uint8List? _bytes;

  static Uint8List? bytes() {
    final b64 = GymSettings.watermark;
    if (b64.isEmpty) return null;
    final k = Object.hash(b64.length, b64.hashCode);
    if (k != _key) {
      try {
        _bytes = base64Decode(b64);
      } catch (_) {
        _bytes = null;
      }
      _key = k;
    }
    return _bytes;
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([changes, GymDb.changes]),
      builder: (context, _) {
        final b = bytes();
        if (b == null) return const SizedBox.shrink();
        return IgnorePointer(
          child: Opacity(
            opacity: GymSettings.watermarkOpacity,
            child: SizedBox.expand(
              child: Image.memory(
                b,
                fit: GymSettings.watermarkFit == 'cover' ? BoxFit.cover : BoxFit.contain,
                gaplessPlayback: true,
              ),
            ),
          ),
        );
      },
    );
  }
}
