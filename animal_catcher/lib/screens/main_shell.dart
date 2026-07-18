import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'achievements_screen.dart';
import 'camera_screen.dart';
import 'collection_screen.dart';
import 'friends_screen.dart';
import 'home_screen.dart';

enum MainShellTab { profile, collection, scan, achievements, friends }

/// Persistent 5-tab shell with a raised Scan button in the center.
class MainShell extends StatefulWidget {
  const MainShell({super.key, this.initialTab = MainShellTab.profile});

  final MainShellTab initialTab;

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  late int _index;

  @override
  void initState() {
    super.initState();
    _index = widget.initialTab.index;
  }

  void goToTab(MainShellTab tab) => setState(() => _index = tab.index);

  @override
  Widget build(BuildContext context) {
    final pages = [
      HomeScreen(onOpenScan: () => goToTab(MainShellTab.scan)),
      CollectionScreen(onOpenScan: () => goToTab(MainShellTab.scan)),
      CameraScreen(embedded: true, isActive: _index == MainShellTab.scan.index),
      const AchievementsScreen(),
      const FriendsScreen(),
    ];

    return Scaffold(
      body: IndexedStack(index: _index, children: pages),
      bottomNavigationBar: _BottomNav(
        index: _index,
        onSelect: (i) => setState(() => _index = i),
      ),
    );
  }
}

class _BottomNav extends StatelessWidget {
  const _BottomNav({required this.index, required this.onSelect});

  final int index;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(
          top: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        ),
      ),
      child: SafeArea(
        top: false,
        // Keep nav labels a fixed size regardless of the device's system font
        // scale so the compact bar never overflows vertically.
        child: MediaQuery.withNoTextScaling(
          child: SizedBox(
            height: 66,
            child: Row(
              children: [
                // Order: Profile | Collection | Scan (raised) | Awards | Friends
                _navItem(
                  MainShellTab.profile.index,
                  Icons.person_outline,
                  Icons.person,
                  'Profile',
                ),
                _navItem(
                  MainShellTab.collection.index,
                  Icons.grid_view_outlined,
                  Icons.grid_view,
                  'Collection',
                ),
                _scanButton(),
                _navItem(
                  MainShellTab.achievements.index,
                  Icons.emoji_events_outlined,
                  Icons.emoji_events,
                  'Awards',
                ),
                _navItem(
                  MainShellTab.friends.index,
                  Icons.group_outlined,
                  Icons.group,
                  'Friends',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _navItem(int i, IconData outlined, IconData filled, String label) {
    final selected = index == i;
    return Expanded(
      child: InkWell(
        onTap: () => onSelect(i),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                selected ? filled : outlined,
                color: selected ? AppColors.accent : AppColors.textMuted,
                size: 24,
              ),
              const SizedBox(height: 2),
              // scaleDown guarantees the label always fits its cell width,
              // eliminating any horizontal overflow on narrow screens.
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: selected ? AppColors.accent : AppColors.textMuted,
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _scanButton() {
    final selected = index == MainShellTab.scan.index;
    return Expanded(
      child: Center(
        child: GestureDetector(
          onTap: () => onSelect(MainShellTab.scan.index),
          child: Transform.translate(
            offset: const Offset(0, -14),
            child: Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.accent,
                border: Border.all(
                  color: selected ? Colors.white : Colors.transparent,
                  width: 2,
                ),
              ),
              child: const Icon(
                Icons.camera_alt,
                color: Colors.black,
                size: 28,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
