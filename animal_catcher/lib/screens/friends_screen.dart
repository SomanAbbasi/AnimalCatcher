import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/api_service.dart';
import '../state/session_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_container.dart';
import 'friend_profile_screen.dart';

/// Minimal Friends tab: search by username, send/accept requests, and view a
/// read-only friend profile. Requires a Supabase account; guests see an empty
/// "sign in to add friends" state.
class FriendsScreen extends StatefulWidget {
  const FriendsScreen({super.key});

  @override
  State<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends State<FriendsScreen> {
  final ApiService _api = ApiService();
  final TextEditingController _searchController = TextEditingController();

  List<ProfileSummary> _friends = [];
  List<UserSearchResult> _requests = [];
  List<UserSearchResult> _results = [];
  final Set<String> _pendingSends = {};

  bool _loading = false;
  bool _searching = false;

  String get _userId =>
      context.read<SessionProvider>().profile?.userId ?? '';

  @override
  void initState() {
    super.initState();
    final session = context.read<SessionProvider>();
    if (!session.isGuest && session.isLoggedIn) {
      _refresh();
    }
  }

  @override
  void dispose() {
    _api.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    final uid = _userId;
    if (uid.isEmpty) return;
    setState(() => _loading = true);
    try {
      final friends = await _api.fetchFriends(uid);
      final requests = await _api.fetchIncomingRequests(uid);
      if (!mounted) return;
      setState(() {
        _friends = friends;
        _requests = requests;
      });
    } catch (_) {
      // Non-fatal; leave existing lists in place.
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _search() async {
    final term = _searchController.text.trim();
    final uid = _userId;
    if (term.isEmpty || uid.isEmpty) {
      setState(() => _results = []);
      return;
    }
    setState(() => _searching = true);
    try {
      final results = await _api.searchUsers(term, uid);
      if (!mounted) return;
      setState(() => _results = results);
    } catch (_) {
      if (mounted) _snack('Search failed.');
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _sendRequest(UserSearchResult user) async {
    final uid = _userId;
    if (uid.isEmpty) return;
    setState(() => _pendingSends.add(user.userId));
    try {
      await _api.sendFriendRequest(uid, user.userId);
      if (!mounted) return;
      _snack('Request sent to ${user.username}.');
    } catch (_) {
      if (mounted) _snack('Could not send request.');
    } finally {
      if (mounted) setState(() => _pendingSends.remove(user.userId));
    }
  }

  Future<void> _acceptRequest(UserSearchResult user) async {
    final uid = _userId;
    if (uid.isEmpty) return;
    try {
      await _api.acceptFriendRequest(uid, user.userId);
      if (!mounted) return;
      _snack('You are now friends with ${user.username}.');
      await _refresh();
    } catch (_) {
      if (mounted) _snack('Could not accept request.');
    }
  }

  void _openProfile(String userId, String username,
      {ProfileSummary? summary}) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => FriendProfileScreen(
          userId: userId,
          username: username,
          initialSummary: summary,
        ),
      ),
    );
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionProvider>();
    final isGuest = session.isGuest || !session.isLoggedIn;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Friends', style: AppTheme.heading(AppColors.accent, size: 26)),
              const SizedBox(height: 16),
              if (isGuest)
                const Expanded(child: _GuestEmptyState())
              else
                Expanded(child: _authedBody()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _authedBody() {
    return RefreshIndicator(
      color: AppColors.accent,
      onRefresh: _refresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          _searchField(),
          const SizedBox(height: 12),
          if (_results.isNotEmpty) ...[
            _sectionLabel('SEARCH RESULTS'),
            ..._results.map(_searchResultTile),
            const SizedBox(height: 16),
          ],
          if (_requests.isNotEmpty) ...[
            _sectionLabel('FRIEND REQUESTS'),
            ..._requests.map(_requestTile),
            const SizedBox(height: 16),
          ],
          _sectionLabel('YOUR FRIENDS'),
          if (_loading && _friends.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: CircularProgressIndicator(color: AppColors.accent),
              ),
            )
          else if (_friends.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Text('No friends yet — search a username to add one.',
                  style: TextStyle(color: AppColors.textMuted)),
            )
          else
            ..._friends.map(_friendTile),
        ],
      ),
    );
  }

  Widget _searchField() {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _searchController,
            style: const TextStyle(color: AppColors.textPrimary),
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _search(),
            decoration: InputDecoration(
              hintText: 'Search by username',
              hintStyle: const TextStyle(color: AppColors.textMuted),
              prefixIcon:
                  const Icon(Icons.search, color: AppColors.textMuted),
              filled: true,
              fillColor: AppColors.surfaceAlt,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          height: 48,
          child: ElevatedButton(
            onPressed: _searching ? null : _search,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.accent,
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: _searching
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.black),
                  )
                : const Text('Search'),
          ),
        ),
      ],
    );
  }

  Widget _sectionLabel(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8, top: 4),
        child: Text(text, style: AppTheme.label),
      );

  Widget _searchResultTile(UserSearchResult user) {
    final sending = _pendingSends.contains(user.userId);
    return _tile(
      user.username,
      'Level ${user.level}',
      trailing: TextButton.icon(
        onPressed: sending ? null : () => _sendRequest(user),
        icon: sending
            ? const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: AppColors.accent),
              )
            : const Icon(Icons.person_add_alt_1, color: AppColors.accent),
        label: const Text('Add', style: TextStyle(color: AppColors.accent)),
      ),
    );
  }

  Widget _requestTile(UserSearchResult user) {
    return _tile(
      user.username,
      'Level ${user.level}',
      trailing: TextButton.icon(
        onPressed: () => _acceptRequest(user),
        icon: const Icon(Icons.check_circle, color: AppColors.accent),
        label: const Text('Accept', style: TextStyle(color: AppColors.accent)),
      ),
    );
  }

  Widget _friendTile(ProfileSummary friend) {
    return _tile(
      friend.username,
      'Level ${friend.level}  •  ${friend.speciesCount} species',
      onTap: () => _openProfile(friend.userId, friend.username,
          summary: friend),
      trailing: const Icon(Icons.chevron_right, color: AppColors.textMuted),
    );
  }

  Widget _tile(
    String title,
    String subtitle, {
    Widget? trailing,
    VoidCallback? onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GlassContainer(
        borderColor: AppColors.accent,
        glow: false,
        borderWidth: 1.2,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: InkWell(
          onTap: onTap,
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.accent.withValues(alpha: 0.14),
                  border: Border.all(color: AppColors.accent, width: 1.5),
                ),
                child: Text(
                  title.isNotEmpty ? title[0].toUpperCase() : '?',
                  style: const TextStyle(
                    color: AppColors.accent,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w700,
                        )),
                    Text(subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 12,
                        )),
                  ],
                ),
              ),
              ?trailing,
            ],
          ),
        ),
      ),
    );
  }
}

class _GuestEmptyState extends StatelessWidget {
  const _GuestEmptyState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.group_outlined, size: 56, color: AppColors.textMuted),
          SizedBox(height: 12),
          Text(
            'Sign in to add friends',
            style: TextStyle(
              color: AppColors.textMuted,
              fontWeight: FontWeight.w700,
              fontSize: 16,
            ),
          ),
          SizedBox(height: 6),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 40),
            child: Text(
              'Create an account to search for players, send requests, and '
              'view their collections.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textMuted, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}
