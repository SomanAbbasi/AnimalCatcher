import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:vibration/vibration.dart';

/// Short one-shot sound effects.
enum Sfx { buttonTap, cardFlip, hitImpact, victory, shutter }

/// Looping background music stems.
enum Bgm { lobby, battle }

/// Global audio + haptics manager (a [ChangeNotifier] so the profile screen's
/// master toggle can react to state changes).
///
/// SFX use built-in [SystemSound] clicks so gameplay never depends on flaky
/// third-party CDN URLs. BGM is optional and skipped until local assets exist.
class AudioManager extends ChangeNotifier {
  AudioManager() {
    _bgmPlayer.setReleaseMode(ReleaseMode.loop);
  }

  final AudioPlayer _bgmPlayer = AudioPlayer(playerId: 'bgm');

  bool _muted = false;
  bool _vibrationEnabled = true;

  bool get muted => _muted;
  bool get vibrationEnabled => _vibrationEnabled;

  /// Master toggle for ALL sound + haptics (wired to the profile screen).
  Future<void> setMuted(bool value) async {
    _muted = value;
    if (_muted) {
      await _bgmPlayer.pause();
    }
    notifyListeners();
  }

  void setVibrationEnabled(bool value) {
    _vibrationEnabled = value;
    notifyListeners();
  }

  /// Start (or switch to) a looping BGM stem.
  ///
  /// Network BGM was removed after Pixabay CDN 403s on Android. Re-enable by
  /// bundling CC0 tracks under `assets/audio/` and using [AssetSource].
  Future<void> playBgm(Bgm bgm) async {
    if (_muted) return;
    try {
      await _bgmPlayer.stop();
    } catch (_) {}
  }

  Future<void> stopBgm() async {
    try {
      await _bgmPlayer.stop();
    } catch (_) {}
  }

  /// Play a one-shot SFX via system sounds (always available offline).
  Future<void> playSfx(Sfx sfx) async {
    if (_muted) return;
    try {
      switch (sfx) {
        case Sfx.hitImpact:
        case Sfx.victory:
          await SystemSound.play(SystemSoundType.alert);
        case Sfx.buttonTap:
        case Sfx.cardFlip:
        case Sfx.shutter:
          await SystemSound.play(SystemSoundType.click);
      }
    } catch (_) {}
  }

  /// Fire a haptic pulse (respects the master toggle + vibration setting).
  Future<void> vibrate({int duration = 20}) async {
    if (_muted || !_vibrationEnabled) return;
    try {
      if (await Vibration.hasVibrator()) {
        Vibration.vibrate(duration: duration);
      }
    } catch (_) {}
  }

  /// Convenience: tap feedback = short SFX + light haptic.
  Future<void> tap() async {
    await playSfx(Sfx.buttonTap);
    await vibrate(duration: 12);
  }

  @override
  void dispose() {
    _bgmPlayer.dispose();
    super.dispose();
  }
}
