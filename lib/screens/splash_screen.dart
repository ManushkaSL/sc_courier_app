import 'dart:async';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'dart:developer' as developer;
import 'login_screen.dart';
import 'dashboard_screen.dart';
import '../services/supabase_service.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  static const String routeName = '/splash';

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  /// Hard ceiling on the splash, no matter what the player reports.
  static const Duration _maxSplashDuration = Duration(seconds: 12);

  /// The player rarely reports a position exactly equal to the duration, so
  /// treat "close enough to the end" as finished.
  static const Duration _endTolerance = Duration(milliseconds: 250);

  late final VideoPlayerController _videoController;
  bool _hasNavigated = false;
  bool _navigationDispatched = false;
  Timer? _fallbackTimer;
  Timer? _navigationWatchdog;
  final _supabaseService = SupabaseService();

  @override
  void initState() {
    super.initState();
    _videoController = VideoPlayerController.asset('assets/logo_animation.mp4');
    _initializeVideo();
    _fallbackTimer = Timer(_maxSplashDuration, () {
      developer.log('Splash timeout reached - navigating');
      _navigateToNextScreen();
    });
  }

  Future<void> _initializeVideo() async {
    try {
      await _videoController.initialize();
      if (!mounted) return;

      await _videoController.setVolume(0);
      await _videoController.setLooping(false);

      _videoController.addListener(_onVideoProgress);
      await _videoController.play();

      // Tighten the fallback to the clip's own length so a player that stops
      // reporting progress (or ends without a final callback) never strands us.
      final duration = _videoController.value.duration;
      if (duration > Duration.zero) {
        _fallbackTimer?.cancel();
        _fallbackTimer = Timer(
          duration + const Duration(milliseconds: 800),
          () {
            developer.log('Video end not reported - navigating');
            _navigateToNextScreen();
          },
        );
      }

      if (mounted) {
        setState(() {
          developer.log('Video initialized and playing successfully');
        });
      }
    } catch (e) {
      developer.log('Video initialization error: $e');
      _navigateToNextScreen();
    }
  }

  void _onVideoProgress() {
    final value = _videoController.value;

    if (value.hasError) {
      developer.log('Video playback error: ${value.errorDescription}');
      _navigateToNextScreen();
      return;
    }

    if (!value.isInitialized) return;

    final duration = value.duration;
    final position = value.position;

    if (duration > Duration.zero && position >= duration - _endTolerance) {
      _navigateToNextScreen();
    }
  }

  void _navigateToNextScreen() {
    if (_hasNavigated || !mounted) return;
    _hasNavigated = true;

    _fallbackTimer?.cancel();
    _videoController.removeListener(_onVideoProgress);

    final nextScreen = _supabaseService.isAuthenticated
        ? DashboardScreen.routeName
        : LoginScreen.routeName;

    // _onVideoProgress can fire from inside a frame; navigating there runs
    // route lifecycle callbacks while the Navigator is locked. Defer to the
    // end of the frame instead.
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _performNavigation(nextScreen),
    );

    // addPostFrameCallback does NOT schedule a frame. Once the video reaches
    // its last frame nothing repaints, so without this the callback would sit
    // unfired forever and the app would hang on the finished splash.
    WidgetsBinding.instance.scheduleFrame();

    // Belt and braces: if the engine still produces no frame (app backgrounded
    // mid-splash, texture stalled), navigate from a timer instead. Timers run
    // outside the frame, so the Navigator is not locked there.
    _navigationWatchdog = Timer(
      const Duration(milliseconds: 500),
      () => _performNavigation(nextScreen),
    );
  }

  void _performNavigation(String routeName) {
    if (_navigationDispatched || !mounted) return;
    _navigationDispatched = true;

    _navigationWatchdog?.cancel();
    Navigator.of(context).pushReplacementNamed(routeName);
  }

  @override
  void dispose() {
    // Anything that throws here runs inside Navigator._flushHistoryUpdates,
    // which would leave the Navigator permanently locked.
    _fallbackTimer?.cancel();
    _navigationWatchdog?.cancel();
    try {
      _videoController.removeListener(_onVideoProgress);
      _videoController.dispose();
    } catch (e) {
      developer.log('Video controller dispose error: $e');
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 12),
            Expanded(
              child: Center(
                child: AspectRatio(
                  aspectRatio: _videoController.value.isInitialized
                      ? _videoController.value.aspectRatio
                      : 16 / 9,
                  child: VideoPlayer(_videoController),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 20),
              child: Image.asset(
                'assets/w.png',
                height: 56,
                fit: BoxFit.contain,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
