import 'dart:math' as math;

import 'package:auto_size_text/auto_size_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../debug/dummy_data.dart';
import '../models/fauna_card_model.dart';
import '../services/audio_manager.dart';
import '../state/session_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/fauna_card.dart';
import '../widgets/glass_container.dart';

enum BattleMove { strike, deflect, classTrait, finisher }

/// Habitat advantage matrix (+25% damage).
double habitatMultiplier(String attacker, String defender) {
  final a = attacker.toLowerCase();
  final d = defender.toLowerCase();
  if ((a == 'ocean') && (d == 'desert' || d == 'land' || d == 'mammal')) {
    return 1.25;
  }
  if ((a == 'land' || a == 'mammal' || a == 'desert') && d == 'insect') {
    return 1.25;
  }
  if (a == 'insect' && d == 'avian') return 1.25;
  if (a == 'avian' && d == 'ocean') return 1.25;
  return 1.0;
}

/// AP-economy turn combat with heuristic Battle Bot.
class BattleScreen extends StatefulWidget {
  const BattleScreen({
    super.key,
    this.playerCard,
    this.enemyCard,
    this.vsBot = true,
  });

  final FaunaCard? playerCard;
  final FaunaCard? enemyCard;
  final bool vsBot;

  @override
  State<BattleScreen> createState() => _BattleScreenState();
}

class _BattleScreenState extends State<BattleScreen>
    with TickerProviderStateMixin {
  final _rng = math.Random();
  final List<String> _combatLog = [];

  late FaunaCard _player;
  late FaunaCard _enemy;

  late int _playerHp;
  late int _enemyHp;
  late int _playerMaxHp;
  late int _enemyMaxHp;

  int _playerAp = 3;
  int _enemyAp = 3;
  int _playerEnergy = 0;
  int _enemyEnergy = 0;

  bool _playerShield = false;
  bool _enemyShield = false;
  int _enemyPoisonTurns = 0;
  int _enemySpeedDebuffTurns = 0;
  int _enemyStunApLoss = 0;
  int _playerGaleTurns = 0;

  bool _busy = false;
  bool _playerTurn = true;
  String? _damageText;
  bool _damageOnEnemy = true;

  late final AnimationController _playerSlam =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 280));
  late final AnimationController _enemySlam =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 280));
  late final AnimationController _shake =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 360));
  late final AnimationController _damagePop =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 750));

  bool _flashEnemy = false;
  bool _flashPlayer = false;

  @override
  void initState() {
    super.initState();
    final team = context.read<SessionProvider>().battleTeam;
    _player = widget.playerCard ??
        (team.isNotEmpty ? team.first : kSandboxStarterCards.first);
    _enemy = widget.enemyCard ??
        kSpeciesDexSeed.firstWhere(
          (c) => c.name == 'Hornet',
          orElse: () => kSpeciesDexSeed[1],
        );
    _playerMaxHp = _player.maxHp;
    _enemyMaxHp = _enemy.maxHp;
    _playerHp = _playerMaxHp;
    _enemyHp = _enemyMaxHp;
    _log('Battle start: ${_player.name} vs ${_enemy.name}!');

    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AudioManager>().playBgm(Bgm.battle);
    });
  }

  @override
  void dispose() {
    _playerSlam.dispose();
    _enemySlam.dispose();
    _shake.dispose();
    _damagePop.dispose();
    context.read<AudioManager>().playBgm(Bgm.lobby);
    super.dispose();
  }

  void _log(String line) {
    _combatLog.insert(0, line);
    if (_combatLog.length > 40) {
      _combatLog.removeLast();
    }
  }

  Future<void> _haptic([int ms = 40]) async {
    context.read<AudioManager>().vibrate(duration: ms);
    HapticFeedback.lightImpact();
  }

  Future<void> _showDamage(int amount, {required bool onEnemy}) async {
    setState(() {
      _damageText = '-$amount HP';
      _damageOnEnemy = onEnemy;
    });
    await _damagePop.forward(from: 0);
    if (mounted) setState(() => _damageText = null);
  }

  Future<void> _shakeScreen() async {
    await _shake.forward(from: 0);
    _shake.reset();
  }

  int _strikeDamage(FaunaCard attacker, FaunaCard defender, {bool shielded = false}) {
    final base = attacker.attack * 0.4;
    final mult = habitatMultiplier(attacker.habitat, defender.habitat);
    var dmg = (base * mult).round();
    if (shielded) dmg = (dmg * 0.5).round();
    return math.max(1, dmg);
  }

  int _finisherDamage(FaunaCard attacker, FaunaCard defender, {bool shielded = false}) {
    final base = attacker.attack * 1.5;
    final mult = habitatMultiplier(attacker.habitat, defender.habitat);
    var dmg = (base * mult).round();
    if (shielded) dmg = (dmg * 0.5).round();
    return math.max(1, dmg);
  }

  Future<void> _onMove(BattleMove move) async {
    if (_busy || !_playerTurn) return;

    final costs = {
      BattleMove.strike: 1,
      BattleMove.deflect: 2,
      BattleMove.classTrait: 2,
      BattleMove.finisher: 3,
    };
    final cost = costs[move]!;
    if (_playerAp < cost) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Need $cost AP for that move.')),
      );
      return;
    }
    if (move == BattleMove.finisher && _playerEnergy < 3) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Finisher requires 3 Energy blocks.')),
      );
      return;
    }

    setState(() => _busy = true);
    await _resolvePlayerMove(move);
    if (_enemyHp <= 0) {
      await _endBattle(true);
      return;
    }

    // End player turn when AP depleted OR after any action then auto bot if AP=0
    if (_playerAp <= 0) {
      await _startEnemyTurn();
    } else {
      setState(() => _busy = false);
    }
  }

  Future<void> _resolvePlayerMove(BattleMove move) async {
    final audio = context.read<AudioManager>();
    switch (move) {
      case BattleMove.strike:
        setState(() => _playerAp -= 1);
        await _playerSlam.forward(from: 0);
        audio.playSfx(Sfx.hitImpact);
        await _haptic();
        await _shakeScreen();
        final dmg = _strikeDamage(_player, _enemy, shielded: _enemyShield);
        setState(() {
          _enemyShield = false;
          _enemyHp = math.max(0, _enemyHp - dmg);
          _playerEnergy = math.min(3, _playerEnergy + 1);
          _flashEnemy = true;
          _log('${_player.name} used Strike! Deals $dmg damage.');
        });
        await _showDamage(dmg, onEnemy: true);
        await _playerSlam.reverse();
        setState(() => _flashEnemy = false);
        break;
      case BattleMove.deflect:
        setState(() {
          _playerAp -= 2;
          _playerShield = true;
          // Light self-heal for Strategic Counter flavor.
          final heal = math.max(4, (_playerMaxHp * 0.06).round());
          _playerHp = math.min(_playerMaxHp, _playerHp + heal);
          _log(
            '${_player.name} used Strategic Counter! Shield 50% + restored $heal HP.',
          );
        });
        audio.playSfx(Sfx.buttonTap);
        await Future<void>.delayed(const Duration(milliseconds: 350));
        break;
      case BattleMove.classTrait:
        setState(() => _playerAp -= 2);
        await _applyClassTrait(fromPlayer: true);
        break;
      case BattleMove.finisher:
        setState(() {
          _playerAp -= 3;
          _playerEnergy = 0;
        });
        await _playerSlam.forward(from: 0);
        audio.playSfx(Sfx.hitImpact);
        await _haptic(120);
        await _shakeScreen();
        final dmg = _finisherDamage(_player, _enemy, shielded: _enemyShield);
        setState(() {
          _enemyShield = false;
          _enemyHp = math.max(0, _enemyHp - dmg);
          _flashEnemy = true;
          _log('${_player.name} used Ultimate Finisher! Deals $dmg damage.');
        });
        await _showDamage(dmg, onEnemy: true);
        await _playerSlam.reverse();
        setState(() => _flashEnemy = false);
        break;
    }
  }

  Future<void> _applyClassTrait({required bool fromPlayer}) async {
    final habitat = (fromPlayer ? _player : _enemy).habitat.toLowerCase();
    final actor = fromPlayer ? _player.name : _enemy.name;
    if (habitat == 'ocean') {
      setState(() {
        if (fromPlayer) {
          _enemySpeedDebuffTurns = 2;
          _log(
            '$actor used Status Ailment: Drench! Speed reduced for 2 turns.',
          );
        } else {
          _log('$actor used Status Ailment: Drench!');
        }
      });
    } else if (habitat == 'insect') {
      setState(() {
        if (fromPlayer) {
          _enemyPoisonTurns = 3;
          _log(
            '$actor used Status Ailment: Venom! ${_enemy.name} is Poisoned!',
          );
        } else {
          _log('$actor used Status Ailment: Venom!');
        }
      });
    } else if (habitat == 'avian') {
      setState(() {
        if (fromPlayer) {
          _playerGaleTurns = 2;
          _log('$actor used Status Ailment: Gale! Evasion primed.');
        }
      });
    } else {
      setState(() {
        if (fromPlayer) {
          _enemyStunApLoss = 1;
          _log(
            '$actor used Status Ailment: Stun! Bot loses 1 AP next turn.',
          );
        }
      });
    }
    await Future<void>.delayed(const Duration(milliseconds: 400));
  }

  Future<void> _startEnemyTurn() async {
    setState(() {
      _playerTurn = false;
      _playerShield = false;
    });
    await _tickPoison();
    if (_enemyHp <= 0) {
      await _endBattle(true);
      return;
    }

    setState(() {
      _enemyAp = 3 - _enemyStunApLoss;
      _enemyStunApLoss = 0;
      if (_enemyAp < 0) _enemyAp = 0;
    });

    await Future<void>.delayed(const Duration(milliseconds: 550));
    while (_enemyAp > 0 && _enemyHp > 0 && _playerHp > 0 && mounted) {
      final move = _pickBotMove();
      await _resolveBotMove(move);
      if (_playerHp <= 0) {
        await _endBattle(false);
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 420));
    }

    setState(() {
      _playerAp = 3;
      _playerTurn = true;
      _busy = false;
      if (_playerGaleTurns > 0) _playerGaleTurns--;
      if (_enemySpeedDebuffTurns > 0) _enemySpeedDebuffTurns--;
    });
  }

  BattleMove _pickBotMove() {
    final hpFrac = _enemyHp / _enemyMaxHp;
    // Priority 1: Ultimate when energy is full.
    if (_enemyEnergy >= 3 && _enemyAp >= 3) return BattleMove.finisher;
    // Priority 2: Low HP — shield / strategic counter.
    if (hpFrac < 0.35 && _enemyAp >= 2) return BattleMove.deflect;
    // If player is shielding, prefer status.
    if (_playerShield && _enemyAp >= 2) return BattleMove.classTrait;
    // Healthy (>70%): prioritize low-cost Strikes to build Energy.
    if (hpFrac > 0.70) {
      return _enemyAp >= 1 ? BattleMove.strike : BattleMove.deflect;
    }
    if (_enemyAp >= 2 && _rng.nextDouble() < 0.4) return BattleMove.classTrait;
    if (_enemyAp >= 1) return BattleMove.strike;
    return BattleMove.deflect;
  }

  Future<void> _resolveBotMove(BattleMove move) async {
    final audio = context.read<AudioManager>();
    final costs = {
      BattleMove.strike: 1,
      BattleMove.deflect: 2,
      BattleMove.classTrait: 2,
      BattleMove.finisher: 3,
    };
    final cost = costs[move]!;
    if (_enemyAp < cost) {
      setState(() => _enemyAp = 0);
      return;
    }
    if (move == BattleMove.finisher && _enemyEnergy < 3) {
      move = BattleMove.strike;
    }

    switch (move) {
      case BattleMove.strike:
        setState(() => _enemyAp -= 1);
        // Gale evade
        if (_playerGaleTurns > 0 && _rng.nextDouble() < 0.35) {
          setState(() => _log('${_player.name} evaded the attack (Gale)!'));
          return;
        }
        await _enemySlam.forward(from: 0);
        audio.playSfx(Sfx.hitImpact);
        await _haptic(50);
        await _shakeScreen();
        final dmg = _strikeDamage(_enemy, _player, shielded: _playerShield);
        setState(() {
          _playerShield = false;
          _playerHp = math.max(0, _playerHp - dmg);
          _enemyEnergy = math.min(3, _enemyEnergy + 1);
          _flashPlayer = true;
          _log('${_enemy.name} used Strike! Deals $dmg damage.');
        });
        await _showDamage(dmg, onEnemy: false);
        await _enemySlam.reverse();
        setState(() => _flashPlayer = false);
        break;
      case BattleMove.deflect:
        setState(() {
          _enemyAp -= 2;
          _enemyShield = true;
          _log('${_enemy.name} used Strategic Counter! Shield active.');
        });
        break;
      case BattleMove.classTrait:
        setState(() => _enemyAp -= 2);
        final h = _enemy.habitat.toLowerCase();
        if (h == 'insect') {
          setState(() {
            _log(
              '${_enemy.name} used Status Ailment: Venom! ${_player.name} is afflicted.',
            );
          });
          setState(() => _playerHp = math.max(0, _playerHp - 8));
          await _showDamage(8, onEnemy: false);
        } else if (h == 'ocean') {
          setState(
            () => _log('${_enemy.name} used Status Ailment: Drench!'),
          );
        } else {
          setState(() {
            _playerAp = math.max(0, _playerAp - 1);
            _log(
              '${_enemy.name} used Status Ailment: Stun! You lose 1 AP next turn.',
            );
          });
        }
        break;
      case BattleMove.finisher:
        setState(() {
          _enemyAp -= 3;
          _enemyEnergy = 0;
        });
        if (_playerGaleTurns > 0 && _rng.nextDouble() < 0.35) {
          setState(() => _log('${_player.name} evaded the Ultimate Finisher!'));
          return;
        }
        await _enemySlam.forward(from: 0);
        audio.playSfx(Sfx.hitImpact);
        await _haptic(140);
        await _shakeScreen();
        final dmg = _finisherDamage(_enemy, _player, shielded: _playerShield);
        setState(() {
          _playerShield = false;
          _playerHp = math.max(0, _playerHp - dmg);
          _flashPlayer = true;
          _log('${_enemy.name} used Ultimate Finisher! Deals $dmg damage.');
        });
        await _showDamage(dmg, onEnemy: false);
        await _enemySlam.reverse();
        setState(() => _flashPlayer = false);
        break;
    }
  }

  Future<void> _tickPoison() async {
    if (_enemyPoisonTurns <= 0) return;
    setState(() {
      _enemyHp = math.max(0, _enemyHp - 8);
      _enemyPoisonTurns--;
      _log('${_enemy.name} takes 8 poison damage!');
    });
    await _showDamage(8, onEnemy: true);
  }

  Future<void> _endBattle(bool playerWon) async {
    final audio = context.read<AudioManager>();
    if (playerWon) {
      audio.playSfx(Sfx.victory);
      context.read<SessionProvider>().addRewards(gold: 50, wildEssence: 20);
    }
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        child: GlassContainer(
          borderColor: playerWon ? AppColors.neonGreen : AppColors.neonMagenta,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                playerWon ? Icons.emoji_events : Icons.dangerous,
                color: playerWon ? AppColors.neonGreen : AppColors.neonMagenta,
                size: 56,
              ),
              const SizedBox(height: 12),
              Text(
                playerWon ? 'VICTORY' : 'DEFEATED',
                style: AppTheme.heading(
                  playerWon ? AppColors.neonGreen : AppColors.neonMagenta,
                ),
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  Navigator.of(context).maybePop();
                },
                child: const Text('Leave Arena',
                    style: TextStyle(color: AppColors.textMuted)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: AnimatedBuilder(
        animation: _shake,
        builder: (context, child) {
          final e = math.sin(_shake.value * math.pi);
          return Transform.translate(
            offset: Offset((_rng.nextDouble() - 0.5) * 12 * e,
                (_rng.nextDouble() - 0.5) * 12 * e),
            child: child,
          );
        },
        child: Stack(
          children: [
            Column(
              children: [
                Expanded(flex: 3, child: _enemyPane()),
                Expanded(flex: 2, child: _combatLogConsole()),
                Expanded(flex: 3, child: _playerPane()),
                _actionBar(),
              ],
            ),
            _damagePopup(),
          ],
        ),
      ),
    );
  }

  Widget _enemyPane() {
    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 12, 0),
            child: Row(
              children: [
                SizedBox(
                  width: 40,
                  child: IconButton(
                    padding: EdgeInsets.zero,
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: AutoSizeText(
                    'VS BOT — ${_enemy.name}',
                    maxLines: 1,
                    minFontSize: 10,
                    style: AppTheme.heading(AppColors.neonMagenta, size: 16),
                  ),
                ),
              ],
            ),
          ),
          _meter(_enemyHp, _enemyMaxHp, _enemyEnergy, _enemyAp, _enemy.name),
          Expanded(
            child: Center(
              child: AnimatedBuilder(
                animation: _enemySlam,
                builder: (_, child) {
                  final t = Curves.easeOut.transform(_enemySlam.value);
                  return Transform.translate(offset: Offset(0, t * 60), child: child);
                },
                child: Opacity(
                  opacity: _flashEnemy ? 0.55 : 1,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: AppColors.neonMagenta, width: 2),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.neonMagenta.withValues(alpha: 0.35),
                          blurRadius: 14,
                        ),
                      ],
                    ),
                    child: FaunaCardWidget(
                      card: _enemy,
                      flip: false,
                      width: 140,
                      height: 200,
                      compact: true,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _playerPane() {
    return Column(
      children: [
        Expanded(
          child: Center(
            child: AnimatedBuilder(
              animation: _playerSlam,
              builder: (_, child) {
                final t = Curves.easeOut.transform(_playerSlam.value);
                return Transform.translate(offset: Offset(0, -t * 70), child: child);
              },
              child: Opacity(
                opacity: _flashPlayer ? 0.55 : 1,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: AppColors.neonGreen, width: 2),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.neonGreen.withValues(alpha: 0.35),
                        blurRadius: 14,
                      ),
                    ],
                  ),
                  child: FaunaCardWidget(
                    card: _player,
                    flip: false,
                    width: 140,
                    height: 200,
                    compact: true,
                  ),
                ),
              ),
            ),
          ),
        ),
        _meter(_playerHp, _playerMaxHp, _playerEnergy, _playerAp, _player.name),
        const SizedBox(height: 6),
      ],
    );
  }

  Widget _meter(int hp, int maxHp, int energy, int ap, String name) {
    final pct = (hp / maxHp).clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w800)),
              ),
              Text('$hp / $maxHp',
                  style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
              const SizedBox(width: 10),
              Text('AP $ap',
                  style: const TextStyle(
                      color: AppColors.neonCyan, fontWeight: FontWeight.w800)),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: pct,
              minHeight: 7,
              backgroundColor: Colors.white12,
              valueColor: AlwaysStoppedAnimation(AppColors.hpColor(pct)),
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              const Text('ENERGY ', style: AppTheme.label),
              ...List.generate(3, (i) {
                final on = i < energy;
                return Container(
                  margin: const EdgeInsets.only(right: 4),
                  width: 20,
                  height: 8,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(3),
                    color: on ? AppColors.warning : Colors.transparent,
                    border: Border.all(
                      color: on ? AppColors.warning : AppColors.textMuted,
                    ),
                  ),
                );
              }),
            ],
          ),
        ],
      ),
    );
  }

  Widget _combatLogConsole() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.neonCyan.withValues(alpha: 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('COMBAT LOG', style: AppTheme.label),
          const SizedBox(height: 6),
          Expanded(
            child: ListView.builder(
              itemCount: _combatLog.length,
              itemBuilder: (_, i) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  _combatLog[i],
                  style: TextStyle(
                    color: i == 0 ? AppColors.neonGreen : AppColors.textMuted,
                    fontSize: 11.5,
                    height: 1.3,
                  ),
                ),
              ),
            ),
          ),
          TextButton(
            onPressed: _playerTurn && !_busy && _playerAp > 0
                ? () async {
                    setState(() {
                      _busy = true;
                      _playerAp = 0;
                    });
                    await _startEnemyTurn();
                  }
                : null,
            child: const Text('END TURN',
                style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
          ),
        ],
      ),
    );
  }

  Widget _actionBar() {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.only(left: 4, bottom: 8),
              child: Text('YOUR HAND / MOVES', style: AppTheme.label),
            ),
            GridView.count(
              shrinkWrap: true,
              crossAxisCount: 2,
              childAspectRatio: 2.4,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                _moveTile(
                  BattleMove.strike,
                  'Strike',
                  '1 AP • ATK×0.4 • +1 Energy',
                  Icons.sports_mma,
                  AppColors.neonGreen,
                ),
                _moveTile(
                  BattleMove.deflect,
                  'Strategic Counter',
                  '2 AP • Heal + Shield 50%',
                  Icons.shield,
                  AppColors.neonCyan,
                ),
                _moveTile(
                  BattleMove.classTrait,
                  'Status Ailment',
                  '2 AP • Habitat debuff',
                  Icons.science,
                  AppColors.neonPurple,
                ),
                _moveTile(
                  BattleMove.finisher,
                  'Ultimate Finisher',
                  '3 AP • Needs 3 Energy',
                  Icons.flash_on,
                  AppColors.warning,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _moveTile(
    BattleMove move,
    String title,
    String subtitle,
    IconData icon,
    Color color,
  ) {
    final costs = {
      BattleMove.strike: 1,
      BattleMove.deflect: 2,
      BattleMove.classTrait: 2,
      BattleMove.finisher: 3,
    };
    final locked = !_playerTurn ||
        _busy ||
        _playerAp < costs[move]! ||
        (move == BattleMove.finisher && _playerEnergy < 3);
    return GestureDetector(
      onTap: locked ? null : () => _onMove(move),
      child: Opacity(
        opacity: locked ? 0.4 : 1,
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: color.withValues(alpha: 0.1),
            border: Border.all(color: color, width: 1.5),
          ),
          child: Row(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AutoSizeText(
                      title,
                      maxLines: 1,
                      minFontSize: 10,
                      style: TextStyle(
                          color: color,
                          fontWeight: FontWeight.w800,
                          fontSize: 13),
                    ),
                    Text(
                      subtitle,
                      maxLines: 2,
                      style: const TextStyle(
                          color: AppColors.textMuted, fontSize: 10),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _damagePopup() {
    if (_damageText == null) return const SizedBox.shrink();
    return AnimatedBuilder(
      animation: _damagePop,
      builder: (_, _) {
        final t = _damagePop.value;
        return Align(
          alignment:
              _damageOnEnemy ? const Alignment(0, -0.25) : const Alignment(0, 0.35),
          child: Opacity(
            opacity: (1 - t).clamp(0.0, 1.0),
            child: Transform.translate(
              offset: Offset(0, -40 * t),
              child: Text(
                _damageText!,
                style: TextStyle(
                  color: _damageOnEnemy
                      ? AppColors.neonMagenta
                      : AppColors.textPrimary,
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
