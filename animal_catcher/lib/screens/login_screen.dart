import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/profile_model.dart';
import '../services/audio_manager.dart';
import '../services/auth_service.dart' as auth;
import '../services/permission_service.dart';
import '../state/session_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_container.dart';
import '../widgets/neon_button.dart';

/// Onboarding + authentication.
///
/// Flow: lore slides -> account creation (with class emblem + validation) ->
/// permission rationale popups -> into the game.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _pageController = PageController();
  int _page = 0;

  static const _loreSlides = [
    _Lore(
      title: 'THE RIFT IS OPEN',
      body:
          'Real-world animals are channeling primal energy templates. Every '
          'creature you meet can be captured as a living battle card.',
      icon: Icons.blur_on_rounded,
      color: AppColors.neonPurple,
    ),
    _Lore(
      title: 'SCAN THE WILD',
      body:
          'Point your scanner at any real animal. The rift analyses its species '
          'and mints its stats, rarity, and battle-ready profile.',
      icon: Icons.center_focus_strong_rounded,
      color: AppColors.neonGreen,
    ),
    _Lore(
      title: 'BATTLE FOR DOMINION',
      body:
          'Assemble a team and clash in tactical, turn-based coliseum duels. '
          'Charge your Ultimate and unleash devastation.',
      icon: Icons.bolt_rounded,
      color: AppColors.neonPink,
    ),
  ];

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _next() {
    context.read<AudioManager>().tap();
    if (_page < _loreSlides.length) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment.topCenter,
            radius: 1.3,
            colors: [Color(0xFF141033), AppColors.background],
          ),
        ),
        child: SafeArea(
          child: PageView(
            controller: _pageController,
            onPageChanged: (p) => setState(() => _page = p),
            children: [
              ..._loreSlides.map((l) => _LoreView(lore: l, onNext: _next)),
              _AuthView(onNext: _next),
            ],
          ),
        ),
      ),
    );
  }
}

class _Lore {
  const _Lore({
    required this.title,
    required this.body,
    required this.icon,
    required this.color,
  });
  final String title;
  final String body;
  final IconData icon;
  final Color color;
}

class _LoreView extends StatelessWidget {
  const _LoreView({required this.lore, required this.onNext});
  final _Lore lore;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Spacer(),
          Container(
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: lore.color.withValues(alpha: 0.12),
              border: Border.all(color: lore.color, width: 1.6),
              boxShadow: [
                BoxShadow(color: lore.color.withValues(alpha: 0.5), blurRadius: 40),
              ],
            ),
            child: Icon(lore.icon, size: 72, color: lore.color),
          ),
          const SizedBox(height: 40),
          Text(lore.title, style: AppTheme.heading(lore.color, size: 30)),
          const SizedBox(height: 18),
          Text(
            lore.body,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.textPrimary,
              height: 1.5,
              fontSize: 15,
            ),
          ),
          const Spacer(),
          NeonButton(label: 'Continue', color: lore.color, onPressed: onNext),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

class _AuthView extends StatefulWidget {
  const _AuthView({required this.onNext});
  final VoidCallback onNext;

  @override
  State<_AuthView> createState() => _AuthViewState();
}

class _AuthViewState extends State<_AuthView> {
  final _formKey = GlobalKey<FormState>();
  final _username = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();

  bool _isRegister = true;
  bool _loading = false;
  StartingClass _selectedClass = StartingClass.apexHunter;

  @override
  void dispose() {
    _username.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  String? _validateUsername(String? v) {
    if (!_isRegister) return null;
    final value = (v ?? '').trim();
    // 3-16 chars, letters/numbers/underscore.
    if (!RegExp(r'^[a-zA-Z0-9_]{3,16}$').hasMatch(value)) {
      return '3-16 chars: letters, numbers, underscore';
    }
    return null;
  }

  String? _validateEmail(String? v) {
    final value = (v ?? '').trim();
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(value)) {
      return 'Enter a valid email';
    }
    return null;
  }

  String? _validatePassword(String? v) {
    final value = v ?? '';
    if (!_isRegister) {
      return value.isEmpty ? 'Password required' : null;
    }
    // Strong password: 8+ chars, at least one letter and one number.
    if (value.length < 8) return 'At least 8 characters';
    if (!RegExp(r'[A-Za-z]').hasMatch(value) || !RegExp(r'\d').hasMatch(value)) {
      return 'Mix letters and numbers';
    }
    return null;
  }

  Future<void> _submit() async {
    final audio = context.read<AudioManager>();
    audio.tap();
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _loading = true);
    final session = context.read<SessionProvider>();
    try {
      if (_isRegister) {
        await session.register(
          email: _email.text.trim(),
          password: _password.text,
          username: _username.text.trim(),
          startingClass: _selectedClass,
        );
        // Ask for camera + location with friendly rationale popups.
        if (mounted) {
          await PermissionService.runOnboardingRequests(context);
        }
      } else {
        await session.login(
          email: _email.text.trim(),
          password: _password.text,
        );
      }
      // On success, main.dart's Consumer swaps to the home screen automatically.
    } on auth.AuthException catch (e) {
      _showError(e.message);
    } catch (e) {
      _showError('Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _google() async {
    final audio = context.read<AudioManager>();
    audio.tap();
    try {
      await context.read<SessionProvider>().signInWithGoogle();
    } on auth.AuthException catch (e) {
      _showError(e.message);
    }
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: AppColors.neonPink.withValues(alpha: 0.25),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 8),
            Text(
              _isRegister ? 'FORGE YOUR LEGEND' : 'WELCOME BACK',
              textAlign: TextAlign.center,
              style: AppTheme.heading(AppColors.neonGreen, size: 24),
            ),
            const SizedBox(height: 24),
            GlassContainer(
              borderColor: AppColors.neonGreen,
              child: Column(
                children: [
                  if (_isRegister) ...[
                    _field(
                      controller: _username,
                      label: 'Username',
                      icon: Icons.person_outline,
                      validator: _validateUsername,
                    ),
                    const SizedBox(height: 14),
                  ],
                  _field(
                    controller: _email,
                    label: 'Email',
                    icon: Icons.mail_outline,
                    keyboardType: TextInputType.emailAddress,
                    validator: _validateEmail,
                  ),
                  const SizedBox(height: 14),
                  _field(
                    controller: _password,
                    label: 'Password',
                    icon: Icons.lock_outline,
                    obscure: true,
                    validator: _validatePassword,
                  ),
                ],
              ),
            ),
            if (_isRegister) ...[
              const SizedBox(height: 24),
              const Text('CHOOSE YOUR CLASS EMBLEM', style: AppTheme.label),
              const SizedBox(height: 12),
              _ClassSelector(
                selected: _selectedClass,
                onSelect: (c) {
                  context.read<AudioManager>().tap();
                  setState(() => _selectedClass = c);
                },
              ),
            ],
            const SizedBox(height: 26),
            NeonButton(
              label: _loading
                  ? 'Summoning...'
                  : (_isRegister ? 'Enter the Rift' : 'Log In'),
              enabled: !_loading,
              onPressed: _loading ? null : _submit,
            ),
            const SizedBox(height: 14),
            NeonButton(
              label: 'Continue with Google',
              color: AppColors.neonCyan,
              icon: Icons.g_mobiledata_rounded,
              onPressed: _loading ? null : _google,
            ),
            const SizedBox(height: 14),
            NeonButton(
              label: 'Sandbox Login (Offline)',
              color: AppColors.warning,
              icon: Icons.science_rounded,
              onPressed: _loading
                  ? null
                  : () {
                      context.read<AudioManager>().tap();
                      context.read<SessionProvider>().enterSandboxLogin();
                    },
            ),
            if (kDebugMode) ...[
              const SizedBox(height: 14),
              NeonButton(
                label: 'Continue as Guest (Test Mode)',
                color: AppColors.rarityLegendary,
                icon: Icons.bug_report_rounded,
                onPressed: _loading
                    ? null
                    : () {
                        context.read<AudioManager>().tap();
                        context.read<SessionProvider>().enterGuestMode();
                      },
              ),
            ],
            const SizedBox(height: 18),
            TextButton(
              onPressed: () => setState(() => _isRegister = !_isRegister),
              child: Text(
                _isRegister
                    ? 'Already have an account? Log in'
                    : 'New here? Create an account',
                style: const TextStyle(color: AppColors.textMuted),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _field({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool obscure = false,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: obscure,
      keyboardType: keyboardType,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      style: const TextStyle(color: AppColors.textPrimary),
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: AppColors.textMuted),
        prefixIcon: Icon(icon, color: AppColors.neonGreen, size: 20),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: AppColors.neonGreen.withValues(alpha: 0.4),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.neonGreen, width: 1.6),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.neonPink),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.neonPink, width: 1.6),
        ),
      ),
    );
  }
}

class _ClassSelector extends StatelessWidget {
  const _ClassSelector({required this.selected, required this.onSelect});
  final StartingClass selected;
  final ValueChanged<StartingClass> onSelect;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: StartingClass.values.map((c) {
        final isSelected = c == selected;
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: GestureDetector(
            onTap: () => onSelect(c),
            child: GlassContainer(
              borderColor:
                  isSelected ? AppColors.neonPurple : AppColors.textMuted,
              glow: isSelected,
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Icon(
                    c.emblemIcon,
                    size: 32,
                    color: isSelected
                        ? AppColors.neonPurple
                        : AppColors.textMuted,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          c.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: isSelected
                                ? AppColors.neonPurple
                                : AppColors.textPrimary,
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          c.tagline,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.textMuted,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (isSelected)
                    const Icon(Icons.check_circle,
                        color: AppColors.neonPurple, size: 22),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}
