import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';

/// Login shuda user (is device par). Roles:
///  * admin — sab kuch (users, settings, delete, reports)
///  * manager — sab kuch siwaye users / cloud settings
///  * reception — members, check-in, fees (reports / expenses / delete nahi)
class Session {
  Session._();

  static String? username;
  static String displayName = '';
  static String role = 'reception';

  static bool get isLoggedIn => username != null;
  static bool get isAdmin => role == 'admin';
  static bool get isManager => role == 'manager';
  static bool get canManage => isAdmin || isManager;

  static Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    username = p.getString('session_username');
    displayName = p.getString('session_display') ?? '';
    role = p.getString('session_role') ?? 'reception';
  }

  static Future<void> start(AppUser u) async {
    username = u.username;
    displayName = u.displayName;
    role = u.role;
    final p = await SharedPreferences.getInstance();
    await p.setString('session_username', u.username);
    await p.setString('session_display', u.displayName);
    await p.setString('session_role', u.role);
    await p.setString('last_username', u.username);
  }

  static Future<String> lastUsername() async {
    final p = await SharedPreferences.getInstance();
    return p.getString('last_username') ?? '';
  }

  static Future<void> clear() async {
    username = null;
    displayName = '';
    role = 'reception';
    final p = await SharedPreferences.getInstance();
    await p.remove('session_username');
    await p.remove('session_display');
    await p.remove('session_role');
  }

  static String roleLabel(String r) {
    switch (r) {
      case 'admin':
        return 'Owner / Admin';
      case 'manager':
        return 'Manager';
      default:
        return 'Reception';
    }
  }
}
