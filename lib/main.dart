import 'dart:async' show unawaited;

import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;

import 'app_info.dart';
import 'db/desktop_db_init.dart';
import 'db/gym_db.dart';
import 'db/user_repository.dart';
import 'screens/home_shell.dart';
import 'screens/login_screen.dart';
import 'services/app_lock.dart';
import 'services/backup_service.dart';
import 'services/crash_handler.dart';
import 'services/license_service.dart';
import 'services/session.dart';
import 'sync/device_tag.dart';
import 'sync/gym_sync.dart';
import 'sync/network_monitor.dart';
import 'theme/theme_manager.dart';
import 'utils/loc.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  CrashHandler.install();
  try {
    await initDesktopDatabase();
    await DeviceTag.init();
    await Loc.load();
    await ThemeManager.load();
    await GymDb.instance.database;
    await GymSettings.load();
    await Session.load();
    await _revalidateSession();
    await LicenseService.init();
    await AppLock.instance.register(loginBuilder: (_) => const LoginScreen());
  } catch (e, st) {
    CrashHandler.record('Startup', e, st);
    runApp(_StartupErrorApp(error: '$e', stack: '$st'));
    return;
  }
  unawaited(BackupService.autoBackupIfDue());
  NetworkMonitor.onOnline = () => GymSync.instance.syncNow();
  try {
    await NetworkMonitor.register();
  } catch (_) {}
  unawaited(GymSync.instance.start());
  runApp(const HannaFitnessApp());
}

/// Har launch par user DB se dobara milao (deactivate / role badla ho to foran asar).
Future<void> _revalidateSession() async {
  final name = Session.username;
  if (name == null) return;
  try {
    final u = await UserRepository.instance.find(name);
    if (u == null || !u.active) {
      await Session.clear();
      return;
    }
    if (u.role != Session.role || u.displayName != Session.displayName) await Session.start(u);
  } catch (_) {}
}

class HannaFitnessApp extends StatelessWidget {
  const HannaFitnessApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([Loc.language, ThemeManager.isDark]),
      builder: (context, _) {
        final lang = Loc.language.value;
        final dark = ThemeManager.isDark.value;
        final p = ThemeManager.palette;
        return MaterialApp(
          navigatorKey: AppLock.navigatorKey,
          // Zabaan / theme badalne par saari screens dobara banein.
          key: ValueKey('$lang-$dark'),
          title: AppInfo.appName,
          debugShowCheckedModeBanner: false,
          theme: ThemeManager.buildTheme(),
          scrollBehavior: const _DesktopScrollBehavior(),
          builder: (context, child) => Directionality(
            textDirection: lang == 'ur' ? TextDirection.rtl : TextDirection.ltr,
            child: _BottomSystemBarGuard(background: p.bg, child: child ?? const SizedBox.shrink()),
          ),
          home: Session.isLoggedIn ? const HomeShell() : const LoginScreen(),
        );
      },
    );
  }
}

/// Android 15+ edge-to-edge: app ko neeche wali system bar ke upar khatam karo.
class _BottomSystemBarGuard extends StatelessWidget {
  const _BottomSystemBarGuard({required this.child, required this.background});
  final Widget child;
  final Color background;

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    if (bottom <= 0) return child;
    return ColoredBox(
      color: background,
      child: Padding(
        padding: EdgeInsets.only(bottom: bottom),
        child: MediaQuery.removePadding(context: context, removeBottom: true, child: child),
      ),
    );
  }
}

class _DesktopScrollBehavior extends MaterialScrollBehavior {
  const _DesktopScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.stylus,
        PointerDeviceKind.trackpad,
      };
}

/// App start na ho sake to ye screen (sab saada — theme / DB par bharosa nahi).
class _StartupErrorApp extends StatelessWidget {
  const _StartupErrorApp({required this.error, required this.stack});
  final String error;
  final String stack;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Builder(
        builder: (context) => Scaffold(
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                const Icon(Icons.error_outline, size: 56, color: Colors.red),
                const SizedBox(height: 12),
                const Text('App start nahi ho saki',
                    textAlign: TextAlign.center, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                const Text(
                  'Aap ka data mehfooz hai. Pehle "Dobara koshish" dabayein. Phir bhi na chale to '
                  '"Error copy" kar ke support (03006296815) ko bhejein — app uninstall NA karein.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: SingleChildScrollView(
                    child: SelectableText(error, style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(onPressed: main, icon: const Icon(Icons.refresh), label: const Text('Dobara koshish (Retry)')),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: 'Startup error\n$error\n\n$stack'));
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Error copy ho gaya')));
                    }
                  },
                  icon: const Icon(Icons.copy),
                  label: const Text('Error copy'),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
