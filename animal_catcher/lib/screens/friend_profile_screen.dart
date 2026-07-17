import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_container.dart';

/// Read-only friend profile: level, XP, and species-discovered count only.
/// No feed, no chat, no editing.
class FriendProfileScreen extends StatefulWidget {
  const FriendProfileScreen({
    super.key,
    required this.userId,
    required this.username,
    this.initialSummary,
  });

  final String userId;
  final String username;
  final ProfileSummary? initialSummary;

  @override
  State<FriendProfileScreen> createState() => _FriendProfileScreenState();
}

class _FriendProfileScreenState extends State<FriendProfileScreen> {
  final ApiService _api = ApiService();
  ProfileSummary? _summary;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _summary = widget.initialSummary;
    _load();
  }

  @override
  void dispose() {
    _api.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final summary = await _api.fetchFriendProfile(widget.userId);
      if (!mounted) return;
      setState(() => _summary = summary);
    } catch (_) {
      if (!mounted) return;
      // Keep any initial summary; only surface an error when we have nothing.
      if (_summary == null) setState(() => _error = 'Could not load profile.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _summary;
    final username =
        (s?.username.isNotEmpty ?? false) ? s!.username : widget.username;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(username, style: AppTheme.heading(AppColors.accent, size: 20)),
      ),
      body: SafeArea(
        child: _loading && s == null
            ? const Center(
                child: CircularProgressIndicator(color: AppColors.accent),
              )
            : _error != null
                ? Center(
                    child: Text(_error!,
                        style: const TextStyle(color: AppColors.textMuted)),
                  )
                : _content(username, s),
      ),
    );
  }

  Widget _content(String username, ProfileSummary? s) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          const SizedBox(height: 8),
          Container(
            width: 96,
            height: 96,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.accent.withValues(alpha: 0.12),
              border: Border.all(color: AppColors.accent, width: 3),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text('LVL',
                    style: TextStyle(
                        color: AppColors.accent,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1)),
                Text('${s?.level ?? 1}',
                    style: const TextStyle(
                        color: AppColors.accent,
                        fontSize: 34,
                        fontWeight: FontWeight.w900,
                        height: 1)),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Text(username, style: AppTheme.heading(AppColors.accent, size: 22)),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: _statCard(
                    'XP', '${s?.xp ?? 0}', Icons.bolt_rounded),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _statCard('SPECIES', '${s?.speciesCount ?? 0}',
                    Icons.pets_rounded),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statCard(String label, String value, IconData icon) {
    return GlassContainer(
      borderColor: AppColors.accent,
      glow: false,
      borderWidth: 1.5,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
      child: Column(
        children: [
          Icon(icon, color: AppColors.accent, size: 28),
          const SizedBox(height: 8),
          Text(value,
              style: const TextStyle(
                  color: AppColors.accent,
                  fontSize: 22,
                  fontWeight: FontWeight.w900)),
          const SizedBox(height: 2),
          Text(label, style: AppTheme.label),
        ],
      ),
    );
  }
}
