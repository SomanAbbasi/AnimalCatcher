import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'arena_screen.dart';
import 'camera_screen.dart';
import 'collection_screen.dart';
import 'home_screen.dart';

enum MainShellTab { profile, scan, collection, arena }

/// Persistent 4-tab shell with a raised Scan button in the center.
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
      HomeScreen(
        onOpenScan: () => goToTab(MainShellTab.scan),
        onOpenArena: () => goToTab(MainShellTab.arena),
      ),
      CameraScreen(embedded: true, isActive: _index == 1),
      const CollectionScreen(),
      const ArenaScreen(),
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
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 12,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 64,
          child: Row(
            children: [
              // Visual order: Profile | Collection | Scan (raised) | Arena
              _navItem(0, Icons.person_outline, Icons.person, 'Profile'),
              _navItem(2, Icons.grid_view_outlined, Icons.grid_view, 'Collection'),
              _scanButton(),
              _navItem(3, Icons.sports_kabaddi_outlined, Icons.sports_kabaddi, 'Arena'),
            ],
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
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              selected ? filled : outlined,
              color: selected ? AppColors.neonGreen : AppColors.textMuted,
              size: 24,
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                color: selected ? AppColors.neonGreen : AppColors.textMuted,
                fontSize: 10,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _scanButton() {
    final selected = index == 1;
    return Expanded(
      child: Center(
        child: GestureDetector(
          onTap: () => onSelect(1),
          child: Transform.translate(
            offset: const Offset(0, -14),
            child: Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.neonGreen,
                boxShadow: [
                  BoxShadow(
                    color: AppColors.neonGreen.withValues(alpha: 0.45),
                    blurRadius: 14,
                    offset: const Offset(0, 4),
                  ),
                ],
                border: Border.all(
                  color: selected ? Colors.white : Colors.transparent,
                  width: 2,
                ),
              ),
              child: const Icon(Icons.camera_alt, color: Colors.black, size: 28),
            ),
          ),
        ),
      ),
    );
  }
}
