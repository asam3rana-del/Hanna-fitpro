import 'package:flutter/widgets.dart';

import '../db/gym_db.dart';

/// Kisi bhi data tabdeeli (is device ya sync se) par [onDataChanged] chalata hai.
mixin AutoRefresh<T extends StatefulWidget> on State<T> {
  void onDataChanged();

  void _listener() {
    if (mounted) onDataChanged();
  }

  @override
  void initState() {
    super.initState();
    GymDb.changes.addListener(_listener);
  }

  @override
  void dispose() {
    GymDb.changes.removeListener(_listener);
    super.dispose();
  }
}

Future<T?> push<T>(BuildContext context, Widget page) =>
    Navigator.of(context).push<T>(PageRouteBuilder<T>(
      transitionDuration: const Duration(milliseconds: 220),
      reverseTransitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (_, __, ___) => page,
      transitionsBuilder: (_, anim, __, child) => FadeTransition(
        opacity: anim,
        child: SlideTransition(
          position: Tween<Offset>(begin: const Offset(0.04, 0), end: Offset.zero)
              .animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
          child: child,
        ),
      ),
    ));
