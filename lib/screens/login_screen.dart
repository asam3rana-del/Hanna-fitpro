import 'package:flutter/material.dart';

import '../app_info.dart';
import '../db/gym_repo.dart';
import '../db/user_repository.dart';
import '../services/app_lock.dart';
import '../services/biometric.dart';
import '../services/session.dart';
import '../theme/theme_manager.dart';
import '../utils/loc.dart';
import '../widgets/refresh.dart';
import '../widgets/ui.dart';
import 'cloud_setup_screen.dart';
import 'home_shell.dart';

/// Gym ka logo (assets/images/logo.png — Hanna Fitness icon).
class GymLogo extends StatelessWidget {
  final double size;
  const GymLogo({super.key, this.size = 84});

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(size * 0.24),
          boxShadow: [BoxShadow(color: pal.gold.withValues(alpha: 0.25), blurRadius: 24, offset: const Offset(0, 8))],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(size * 0.24),
          child: Image.asset('assets/images/logo.png', fit: BoxFit.cover),
        ),
      );
}

/// Pehli dafa: gym + owner account banao (ya cloud se maujooda gym jorein). Baad mein: login.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _loading = true;
  bool _setup = false;
  bool _busy = false;
  bool _hide = true;
  bool _bioAvailable = false;
  String _loginMethod = 'password';
  String? _error;

  final _user = TextEditingController();
  final _pass = TextEditingController();
  final _pass2 = TextEditingController();
  final _gym = TextEditingController();
  final _owner = TextEditingController();

  @override
  void initState() {
    super.initState();
    AppLock.instance.enterLoginScreen();
    _init();
  }

  @override
  void dispose() {
    AppLock.instance.leaveLoginScreen();
    for (final c in [_user, _pass, _pass2, _gym, _owner]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _init() async {
    final any = await UserRepository.instance.hasAnyUser();
    final last = await Session.lastUsername();
    final method = await UserRepository.instance.getSetting('login_method') ?? 'password';
    final bio = await Biometric.isAvailable();
    if (!mounted) return;
    setState(() {
      _setup = !any;
      _loading = false;
      _loginMethod = method;
      _bioAvailable = bio;
      if (_user.text.isEmpty) _user.text = last;
      if (_gym.text.isEmpty) _gym.text = GymSettings.get('gym_name');
    });
    if (any && bio && last.isNotEmpty && (method == 'fingerprint' || method == 'both')) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _fingerprint());
    }
  }

  void _goHome() {
    Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const HomeShell()), (_) => false);
  }

  Future<void> _login() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final u = await UserRepository.instance.authenticate(_user.text, _pass.text);
    if (!mounted) return;
    if (u == null) {
      setState(() {
        _busy = false;
        _error = Loc.t('Wrong username or password', 'یوزر نیم یا پاس ورڈ غلط ہے');
      });
      return;
    }
    await Session.start(u);
    if (mounted) _goHome();
  }

  Future<void> _fingerprint() async {
    final last = _user.text.trim().isNotEmpty ? _user.text.trim() : await Session.lastUsername();
    if (last.isEmpty) return;
    final ok = await Biometric.authenticate(reason: Loc.t('Login to Hanna Fitness', 'حنا فٹنس میں لاگ اِن'));
    if (!ok || !mounted) return;
    final u = await UserRepository.instance.find(last);
    if (u == null || !u.active) {
      if (mounted) setState(() => _error = Loc.t('User not found — use password', 'یوزر نہیں ملا — پاس ورڈ استعمال کریں'));
      return;
    }
    await Session.start(u);
    if (mounted) _goHome();
  }

  Future<void> _createGym() async {
    final user = _user.text.trim();
    if (_gym.text.trim().isEmpty || user.isEmpty) {
      setState(() => _error = Loc.t('Enter gym name and username', 'جم کا نام اور یوزر نیم لکھیں'));
      return;
    }
    if (_pass.text.length < 4) {
      setState(() => _error = Loc.t('Password must be at least 4 characters', 'پاس ورڈ کم از کم 4 حروف'));
      return;
    }
    if (_pass.text != _pass2.text) {
      setState(() => _error = Loc.t('Passwords do not match', 'پاس ورڈ ایک جیسے نہیں'));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    await GymSettings.set('gym_name', _gym.text.trim());
    await PlanRepo.seedDefaults();
    await UserRepository.instance.create(
      username: user,
      displayName: _owner.text.trim().isEmpty ? user : _owner.text.trim(),
      password: _pass.text,
      role: 'admin',
    );
    final u = await UserRepository.instance.find(user);
    if (u != null) await Session.start(u);
    if (mounted) _goHome();
  }

  Future<void> _joinCloud() async {
    await push(context, const CloudSetupScreen(joining: true));
    if (!mounted) return;
    setState(() => _loading = true);
    await GymSettings.load();
    await _init();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: pal.bg,
      body: SafeArea(
        child: _loading
            ? Center(child: CircularProgressIndicator(color: pal.gold))
            : Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 440),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      const Center(child: GymLogo(size: 92)),
                      const SizedBox(height: 18),
                      Text(
                        _setup ? AppInfo.appName.toUpperCase() : GymSettings.gymName.toUpperCase(),
                        textAlign: TextAlign.center,
                        style: TextStyle(color: pal.ink, fontSize: 24, fontWeight: FontWeight.w900, letterSpacing: 3),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _setup
                            ? Loc.t('Set up your gym in one minute', 'ایک منٹ میں اپنا جم سیٹ اپ کریں')
                            : AppInfo.tagline,
                        textAlign: TextAlign.center,
                        style: TextStyle(color: pal.gold, fontWeight: FontWeight.w600, letterSpacing: 1),
                      ),
                      const SizedBox(height: 28),
                      PCard(
                        padding: const EdgeInsets.all(20),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: _setup ? _setupFields() : _loginFields()),
                      ),
                      const SizedBox(height: 14),
                      if (_setup)
                        OutlinedButton.icon(
                          onPressed: _busy ? null : _joinCloud,
                          icon: Icon(Icons.cloud_sync_outlined, color: pal.gold),
                          label: Text(Loc.t('Join an existing gym (cloud sync)', 'موجودہ جم سے جوڑیں (کلاؤڈ سنک)')),
                        ),
                      const SizedBox(height: 10),
                      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                        TextButton(
                          onPressed: () => Loc.setLanguage(Loc.isUrdu ? 'en' : 'ur'),
                          child: Text(Loc.isUrdu ? 'English' : 'اردو', style: TextStyle(color: pal.muted)),
                        ),
                        Text('·', style: TextStyle(color: pal.muted)),
                        IconButton(
                          tooltip: Loc.t('Light / Dark', 'لائٹ / ڈارک'),
                          onPressed: () => ThemeManager.setDarkMode(!ThemeManager.isDark.value),
                          icon: Icon(pal.isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined, color: pal.muted),
                        ),
                      ]),
                      Text('${AppInfo.business} · ${AppInfo.supportPhone}',
                          textAlign: TextAlign.center, style: TextStyle(color: pal.muted, fontSize: 12)),
                    ]),
                  ),
                ),
              ),
      ),
    );
  }

  Widget _errorBox() => _error == null
      ? const SizedBox.shrink()
      : Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: pal.redSoft, borderRadius: BorderRadius.circular(12)),
            child: Text(_error!, style: TextStyle(color: pal.red, fontWeight: FontWeight.w600)),
          ),
        );

  Widget _passField(TextEditingController c, String label, {VoidCallback? onSubmit}) => TextField(
        controller: c,
        obscureText: _hide,
        onSubmitted: (_) => onSubmit?.call(),
        decoration: ThemeManager.field(
          label,
          icon: Icons.lock_outline,
          suffix: IconButton(
            icon: Icon(_hide ? Icons.visibility_outlined : Icons.visibility_off_outlined, color: pal.muted),
            onPressed: () => setState(() => _hide = !_hide),
          ),
        ),
      );

  List<Widget> _loginFields() => [
        Text(Loc.t('Welcome back', 'خوش آمدید'),
            style: TextStyle(color: pal.ink, fontSize: 18, fontWeight: FontWeight.w800)),
        const SizedBox(height: 16),
        _errorBox(),
        TextField(
          controller: _user,
          textInputAction: TextInputAction.next,
          decoration: ThemeManager.field(Loc.t('Username', 'یوزر نیم'), icon: Icons.person_outline),
        ),
        const SizedBox(height: 12),
        _passField(_pass, Loc.t('Password', 'پاس ورڈ'), onSubmit: _login),
        const SizedBox(height: 18),
        GoldButton(label: Loc.t('LOGIN', 'لاگ اِن'), icon: Icons.login, busy: _busy, onPressed: _login),
        if (_bioAvailable && _loginMethod != 'password') ...[
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _fingerprint,
            icon: Icon(Icons.fingerprint, color: pal.gold),
            label: Text(Loc.t('Login with fingerprint', 'فنگر پرنٹ سے لاگ اِن')),
          ),
        ],
      ];

  List<Widget> _setupFields() => [
        Text(Loc.t('Create your gym', 'اپنا جم بنائیں'),
            style: TextStyle(color: pal.ink, fontSize: 18, fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        Text(
          Loc.t('This will be the owner (admin) account.', 'یہ مالک (ایڈمن) کا اکاؤنٹ ہو گا۔'),
          style: TextStyle(color: pal.muted),
        ),
        const SizedBox(height: 16),
        _errorBox(),
        TextField(
          controller: _gym,
          textCapitalization: TextCapitalization.words,
          decoration: ThemeManager.field(Loc.t('Gym name', 'جم کا نام'), icon: Icons.fitness_center),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _owner,
          textCapitalization: TextCapitalization.words,
          decoration: ThemeManager.field(Loc.t('Owner name', 'مالک کا نام'), icon: Icons.badge_outlined),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _user,
          decoration: ThemeManager.field(Loc.t('Username (for login)', 'یوزر نیم (لاگ اِن کے لیے)'), icon: Icons.person_outline),
        ),
        const SizedBox(height: 12),
        _passField(_pass, Loc.t('Password', 'پاس ورڈ')),
        const SizedBox(height: 12),
        _passField(_pass2, Loc.t('Confirm password', 'پاس ورڈ دوبارہ'), onSubmit: _createGym),
        const SizedBox(height: 18),
        GoldButton(label: Loc.t('CREATE GYM', 'جم بنائیں'), icon: Icons.rocket_launch_outlined, busy: _busy, onPressed: _createGym),
      ];
}
