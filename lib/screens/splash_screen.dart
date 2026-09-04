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
  late final VideoPlayerController _videoController;
  bool _hasNavigated = false;
  Timer? _fallbackTimer;
  final _supabaseService = SupabaseService();

  @override
  void initState() {
    super.initState();
    _videoController = VideoPlayerController.asset('assets/logo_animation.mp4');
    _initializeVideo();
    // Fallback timeout - navigate after 10 seconds if video fails
    _fallbackTimer = Timer(const Duration(seconds: 10), () {
      if (mounted && !_hasNavigated) {
        developer.log('Video initialization timeout - navigating');
        _navigateToNextScreen();
      }
    });
  }

  Future<void> _initializeVideo() async {
    try {
      await _videoController.initialize();
      await _videoController.setVolume(0);
      await _videoController.setLooping(false);

      _videoController.addListener(_onVideoProgress);
      await _videoController.play();

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
    if (!_videoController.value.isInitialized) return;

    final duration = _videoController.value.duration;
    final position = _videoController.value.position;

    if (duration > Duration.zero && position >= duration) {
      _navigateToNextScreen();
    }
  }

  void _navigateToNextScreen() {
    if (_hasNavigated || !mounted) return;
    _hasNavigated = true;

    _fallbackTimer?.cancel();
    _videoController.removeListener(_onVideoProgress);

    final isAuthenticated = _supabaseService.isAuthenticated;
    final nextScreen = isAuthenticated
        ? DashboardScreen.routeName
        : LoginScreen.routeName;

    // _onVideoProgress can fire from inside a frame; navigating there runs
    // route lifecycle callbacks while the Navigator is locked.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.pushReplacementNamed(context, nextScreen);
    });
  }

  @override
  void dispose() {
    // Anything that throws here runs inside Navigator._flushHistoryUpdates,
    // which would leave the Navigator permanently locked.
    _fallbackTimer?.cancel();
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
