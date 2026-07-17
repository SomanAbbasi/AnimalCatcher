import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../debug/dummy_data.dart';
import '../models/fauna_card_model.dart';
import '../services/api_service.dart';
import '../services/audio_manager.dart';
import '../services/geofence_service.dart';
import '../state/session_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/fauna_card.dart';
import '../widgets/glass_container.dart';
import '../widgets/neon_button.dart';

enum _ScanPhase { idle, scanning, awaitingTap, flipping, revealed }

/// Interactive AR holographic scanner with TAP TO UNVEIL reveal sequence.
class CameraScreen extends StatefulWidget {
  const CameraScreen({
    super.key,
    this.embedded = false,
    this.isActive = true,
  });

  final bool embedded;

  /// When false (e.g. another tab is selected), the camera hardware is released.
  final bool isActive;

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  CameraController? _controller;
  bool _cameraAvailable = false;
  final ApiService _api = ApiService();
  final GeofenceService _geo = GeofenceService();

  _ScanPhase _phase = _ScanPhase.idle;
  int _statusIndex = 0;
  FaunaCard? _minted;
  bool _localSandbox = false;
  String? _banner;
  int _xpAwarded = 0;

  double? _lat;
  double? _lng;
  bool _zooBlocked = false;
  bool _checkingLocation = false;

  static const _zooMessage =
      'Scans are for wild encounters only — this looks like a zoo or aquarium.';

  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat(reverse: true);
  late final AnimationController _flash = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
  );
  late final AnimationController _flip = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );
  late final AnimationController _tapPulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  static const _statusMessages = [
    'Targeting...',
    'Analysing Habitat Signature...',
    'Consulting Database archives...',
    'Minting Fauna Card...',
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.isActive) {
      _setupCamera();
      _resolveLocationAndGeofence();
    }
  }

  @override
  void didUpdateWidget(CameraScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isActive != widget.isActive) {
      if (widget.isActive && _phase == _ScanPhase.idle) {
        _setupCamera();
        _resolveLocationAndGeofence();
      } else {
        _releaseCamera();
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (widget.isActive && _phase == _ScanPhase.idle) {
        _setupCamera();
      }
    } else {
      _releaseCamera();
    }
  }

  Future<void> _setupCamera() async {
    if (_controller != null) return;
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) return;
      final controller = CameraController(
        cameras.first,
        ResolutionPreset.high,
        enableAudio: false,
      );
      await controller.initialize();
      if (!mounted) return;
      setState(() {
        _controller = controller;
        _cameraAvailable = true;
      });
    } catch (_) {
      if (mounted) setState(() => _cameraAvailable = false);
    }
  }

  /// Resolve the device location, push it into the session (real capture
  /// location), then run the zoo/aquarium geofence. Fails open: any failure
  /// leaves [_zooBlocked] false so legitimate wild scans are never blocked.
  Future<void> _resolveLocationAndGeofence() async {
    if (_checkingLocation) return;
    _checkingLocation = true;
    try {
      final location = await _geo.currentLocation();
      if (!mounted) return;
      if (location == null) {
        setState(() => _zooBlocked = false);
        return;
      }
      _lat = location.lat;
      _lng = location.lng;
      if (mounted) {
        context.read<SessionProvider>().updateLocation(location.lat, location.lng);
      }
      final near = await _geo.isNearZooOrAquarium(location.lat, location.lng);
      if (!mounted) return;
      setState(() => _zooBlocked = near);
    } finally {
      _checkingLocation = false;
    }
  }

  Future<void> _releaseCamera() async {
    final controller = _controller;
    _controller = null;
    if (controller != null) {
      try {
        await controller.dispose();
      } catch (_) {}
    }
    if (mounted) {
      setState(() => _cameraAvailable = false);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pulse.dispose();
    _flash.dispose();
    _flip.dispose();
    _tapPulse.dispose();
    final controller = _controller;
    _controller = null;
    controller?.dispose();
    _api.dispose();
    _geo.dispose();
    super.dispose();
  }

  Future<void> _cycleStatus() async {
    for (var i = 0; i < _statusMessages.length; i++) {
      if (!mounted || _phase != _ScanPhase.scanning) return;
      setState(() => _statusIndex = i);
      await Future<void>.delayed(const Duration(milliseconds: 550));
    }
  }

  Future<void> _capture() async {
    if (_phase != _ScanPhase.idle) return;
    if (_zooBlocked) {
      _snack(_zooMessage);
      return;
    }
    context.read<AudioManager>().playSfx(Sfx.shutter);
    _flash.forward(from: 0);

    String imageBase64;
    String? photoPath;
    try {
      if (_cameraAvailable && _controller != null) {
        final file = await _controller!.takePicture();
        photoPath = file.path;
        imageBase64 = base64Encode(await file.readAsBytes());
      } else {
        imageBase64 = base64Encode(List<int>.filled(32, 1));
      }
      await _runScan(imageBase64: imageBase64, photoPath: photoPath);
    } catch (_) {
      if (!mounted) return;
      setState(() => _phase = _ScanPhase.idle);
      _snack('Capture failed.');
    }
  }

  Future<void> _pickFromGallery() async {
    if (_phase != _ScanPhase.idle) return;
    if (_zooBlocked) {
      _snack(_zooMessage);
      return;
    }
    context.read<AudioManager>().tap();
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
    );
    if (picked == null) return;
    final bytes = await File(picked.path).readAsBytes();
    await _runScan(imageBase64: base64Encode(bytes), photoPath: picked.path);
  }

  Future<void> _runScan({
    required String imageBase64,
    String? photoPath,
  }) async {
    final session = context.read<SessionProvider>();
    setState(() {
      _phase = _ScanPhase.scanning;
      _statusIndex = 0;
      _banner = null;
      _minted = null;
      _localSandbox = false;
    });
    _cycleStatus();

    try {
      final result = await _api.scan(
        userId: session.profile?.userId ?? 'anonymous',
        imageBase64: imageBase64,
        lat: _lat ?? session.profile?.locationLat,
        lng: _lng ?? session.profile?.locationLng,
      );
      if (!mounted) return;
      final card = result.card.copyWith(photoPath: photoPath);
      final wasNew = !session.hasCaught(card.name);
      session.applyScanXp(
        awarded: result.xpAwarded,
        xp: result.xp,
        level: result.level,
        wasNew: wasNew,
      );
      await _releaseCamera();
      if (!mounted) return;
      setState(() {
        _minted = card;
        _localSandbox = result.localSandbox;
        _xpAwarded = result.xpAwarded > 0
            ? result.xpAwarded
            : (wasNew ? 50 : 5);
        _phase = _ScanPhase.awaitingTap;
        _banner = result.localSandbox ? 'Local Scan Complete' : null;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.type == ScanErrorType.antiCheat) {
        setState(() => _phase = _ScanPhase.idle);
        _showAnomaly(e.message);
        return;
      }
      if (e.type == ScanErrorType.network || e.type == ScanErrorType.timeout) {
        final mock = kSandboxStarterCards[
            math.Random().nextInt(kSandboxStarterCards.length)];
        final wasNew = !session.hasCaught(mock.name);
        session.applyScanXp(
          awarded: 0,
          xp: 0,
          level: session.level,
          wasNew: wasNew,
        );
        await _releaseCamera();
        if (!mounted) return;
        setState(() {
          _minted = mock.copyWith(photoPath: photoPath);
          _localSandbox = true;
          _xpAwarded = wasNew ? 50 : 5;
          _banner = 'Local Scan Complete';
          _phase = _ScanPhase.awaitingTap;
        });
        return;
      }
      setState(() => _phase = _ScanPhase.idle);
      _snack(e.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _phase = _ScanPhase.idle);
      _snack('Unexpected scanner error.');
    }
  }

  Future<void> _unveil() async {
    if (_phase != _ScanPhase.awaitingTap || _minted == null) return;
    context.read<AudioManager>().playSfx(Sfx.cardFlip);
    setState(() => _phase = _ScanPhase.flipping);
    var midHapticDone = false;
    void listener() {
      if (!midHapticDone && _flip.value >= 0.48 && _flip.value <= 0.55) {
        midHapticDone = true;
        HapticFeedback.mediumImpact();
        context.read<AudioManager>().vibrate(duration: 55);
      }
    }

    _flip.addListener(listener);
    await _flip.forward(from: 0);
    _flip.removeListener(listener);
    if (!mounted) return;
    setState(() => _phase = _ScanPhase.revealed);
  }

  void _addToCollection() {
    if (_minted == null) return;
    final session = context.read<SessionProvider>();
    session.addToCollection(_minted!);
    session.addRewards(gold: 10, wildEssence: 5);
    context.read<AudioManager>().tap();
    setState(() {
      _phase = _ScanPhase.idle;
      _minted = null;
      _banner = null;
      _xpAwarded = 0;
      _flip.reset();
    });
    if (widget.isActive) {
      _setupCamera();
    }
  }

  void _showAnomaly(String message) {
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        child: GlassContainer(
          borderColor: AppColors.neonMagenta,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.report_gmailerrorred,
                  color: AppColors.neonMagenta, size: 48),
              const SizedBox(height: 12),
              Text('ANOMALY DETECTED',
                  style: AppTheme.heading(AppColors.neonMagenta, size: 18)),
              const SizedBox(height: 10),
              Text(message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.textPrimary)),
              const SizedBox(height: 16),
              NeonButton(
                label: 'Find a Real Animal',
                color: AppColors.neonMagenta,
                onPressed: () => Navigator.pop(ctx),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          _preview(),
          _vignette(),
          if (_phase == _ScanPhase.idle || _phase == _ScanPhase.scanning)
            _hud(),
          _buildFlash(),
          if (_phase == _ScanPhase.idle) _bottomControls(),
          if (_phase == _ScanPhase.scanning) _scanningBanner(),
          if (_phase == _ScanPhase.awaitingTap ||
              _phase == _ScanPhase.flipping ||
              _phase == _ScanPhase.revealed)
            _revealOverlay(),
          if (!widget.embedded) _topBar(),
          if (_banner != null) _localBanner(),
        ],
      ),
    );
  }

  Widget _preview() {
    if (_cameraAvailable && _controller != null) {
      return FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: _controller!.value.previewSize?.height ?? 1080,
          height: _controller!.value.previewSize?.width ?? 1920,
          child: CameraPreview(_controller!),
        ),
      );
    }
    return Container(
      color: AppColors.background,
      alignment: Alignment.center,
      child: const Text('CAMERA PREVIEW\n(demo mode)',
          textAlign: TextAlign.center, style: AppTheme.label),
    );
  }

  Widget _vignette() => IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.black.withValues(alpha: 0.45),
                Colors.transparent,
                Colors.black.withValues(alpha: 0.7),
              ],
            ),
          ),
        ),
      );

  Widget _hud() {
    return AnimatedBuilder(
      animation: _pulse,
      builder: (_, _) => Center(
        child: SizedBox(
          width: 280,
          height: 280,
          child: CustomPaint(
            painter: _GridHudPainter(
              progress: _pulse.value,
              scanning: _phase == _ScanPhase.scanning,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFlash() {
    return AnimatedBuilder(
      animation: _flash,
      builder: (_, _) => IgnorePointer(
        child: Container(
          color: Colors.white.withValues(
            alpha: (1 - _flash.value) * _flash.value * 3,
          ),
        ),
      ),
    );
  }

  Widget _topBar() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.only(left: 4, top: 4),
        child: Row(
          children: [
            SizedBox(
              width: 40,
              child: IconButton(
                padding: EdgeInsets.zero,
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                onPressed: () async {
                  await _releaseCamera();
                  if (!mounted) return;
                  Navigator.of(context).maybePop();
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text('SCAN',
                  style: AppTheme.heading(AppColors.neonGreen, size: 18)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _bottomControls() {
    final captureColor =
        _zooBlocked ? AppColors.textMuted : AppColors.accent;
    return SafeArea(
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_zooBlocked) _zooBanner(),
            Padding(
              padding: const EdgeInsets.only(bottom: 28),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _sideBtn(Icons.photo_library, 'Gallery', _pickFromGallery),
                  const SizedBox(width: 28),
                  Opacity(
                    opacity: _zooBlocked ? 0.4 : 1.0,
                    child: GestureDetector(
                      onTap: _capture,
                      child: Container(
                        width: 78,
                        height: 78,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: captureColor, width: 4),
                        ),
                        child: Icon(
                          _zooBlocked ? Icons.block : Icons.camera_alt,
                          color: captureColor,
                          size: 30,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 28),
                  const SizedBox(width: 56),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _zooBanner() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.warning),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.info_outline, color: AppColors.warning, size: 20),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              _zooMessage,
              style: const TextStyle(
                color: AppColors.warning,
                fontWeight: FontWeight.w700,
                fontSize: 12.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sideBtn(IconData icon, String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.neonCyan),
              color: Colors.black45,
            ),
            child: Icon(icon, color: AppColors.neonCyan, size: 22),
          ),
          const SizedBox(height: 4),
          Text(label,
              style: const TextStyle(color: AppColors.textMuted, fontSize: 10)),
        ],
      ),
    );
  }

  Widget _scanningBanner() {
    return SafeArea(
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 48),
          child: GlassContainer(
            borderColor: AppColors.neonMagenta,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.neonMagenta,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  _statusMessages[_statusIndex],
                  style: const TextStyle(
                    color: AppColors.neonMagenta,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _localBanner() {
    return SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: Container(
          margin: const EdgeInsets.only(top: 56),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.warning.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.warning),
          ),
          child: Text(
            _banner!,
            style: const TextStyle(
              color: AppColors.warning,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
    );
  }

  Widget _revealOverlay() {
    final showFront = _flip.value > 0.5 || _phase == _ScanPhase.revealed;
    return Positioned.fill(
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF16211A),
              Color(0xFF0E1410),
              Color(0xFF0A0E0B),
            ],
          ),
        ),
        child: BackdropFilter(
          // Frosted dimming over frozen camera / table.
          filter: ImageFilter.blur(sigmaX: 2, sigmaY: 2),
          child: SafeArea(
            child: Column(
              children: [
                const Spacer(),
                GestureDetector(
                  onTap: _phase == _ScanPhase.awaitingTap ? _unveil : null,
                  child: AnimatedBuilder(
                    animation: Listenable.merge([_flip, _tapPulse]),
                    builder: (_, _) {
                      final t = _phase == _ScanPhase.awaitingTap
                          ? 0.0
                          : _flip.value;
                      final angle = t * math.pi;
                      final scale = 1.0 + (math.sin(t * math.pi) * 0.08);
                      final transform = Matrix4.identity()
                        ..setEntry(3, 2, 0.0016)
                        ..rotateY(angle);
                      return Transform.scale(
                        scale: scale,
                        child: Transform(
                          alignment: Alignment.center,
                          transform: transform,
                          child: showFront && _minted != null
                              ? Transform(
                                  alignment: Alignment.center,
                                  transform: Matrix4.identity()..rotateY(math.pi),
                                  child: FaunaCardWidget(
                                    card: _minted!,
                                    flip: false,
                                    width: 260,
                                    height: 390,
                                  ),
                                )
                              : _cardBack(),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 20),
                if (_phase == _ScanPhase.awaitingTap)
                  AnimatedBuilder(
                    animation: _tapPulse,
                    builder: (_, _) => Opacity(
                      opacity: 0.45 + _tapPulse.value * 0.55,
                      child: Text(
                        'TAP TO DRAW & REVEAL',
                        style: AppTheme.heading(AppColors.neonCyan, size: 18),
                      ),
                    ),
                  ),
                if (_phase == _ScanPhase.revealed) ...[
                  if (_xpAwarded > 0)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 7),
                        decoration: BoxDecoration(
                          color: AppColors.neonGreen.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: AppColors.neonGreen),
                        ),
                        child: Text(
                          '+$_xpAwarded XP',
                          style: AppTheme.heading(AppColors.neonGreen, size: 16),
                        ),
                      ),
                    ),
                  if (_localSandbox)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 8),
                      child: Text('Local Scan Complete',
                          style: TextStyle(color: AppColors.warning)),
                    ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 40),
                    child: NeonButton(
                      label: 'ADD TO COLLECTION',
                      onPressed: _addToCollection,
                    ),
                  ),
                ],
                const Spacer(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _cardBack() {
    return Container(
      width: 260,
      height: 390,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF8FAE8A), width: 2),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            'assets/images/card_back.png',
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) {
              return Container(
                color: const Color(0xFF8FAE8A),
                alignment: Alignment.center,
                child: const Icon(Icons.style, size: 72, color: Colors.white70),
              );
            },
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 18,
            child: Text(
              'FAUNA DEX',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.85),
                fontWeight: FontWeight.w900,
                letterSpacing: 2,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GridHudPainter extends CustomPainter {
  _GridHudPainter({required this.progress, required this.scanning});
  final double progress;
  final bool scanning;

  @override
  void paint(Canvas canvas, Size size) {
    final color = scanning ? AppColors.neonMagenta : AppColors.neonGreen;
    final paint = Paint()
      ..color = color.withValues(alpha: 0.55 + progress * 0.35)
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;

    const corner = 40.0;
    final rect = Offset.zero & size;
    void c(Offset o, Offset a, Offset b) {
      canvas.drawLine(o, o + a, paint);
      canvas.drawLine(o, o + b, paint);
    }

    c(rect.topLeft, const Offset(corner, 0), const Offset(0, corner));
    c(rect.topRight, const Offset(-corner, 0), const Offset(0, corner));
    c(rect.bottomLeft, const Offset(corner, 0), const Offset(0, -corner));
    c(rect.bottomRight, const Offset(-corner, 0), const Offset(0, -corner));

    final y = size.height * progress;
    canvas.drawLine(
      Offset(10, y),
      Offset(size.width - 10, y),
      Paint()
        ..color = color.withValues(alpha: 0.55)
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(covariant _GridHudPainter old) =>
      old.progress != progress || old.scanning != scanning;
}
