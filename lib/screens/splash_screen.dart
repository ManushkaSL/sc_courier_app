import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'login_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  static const String routeName = '/splash';

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  late final VideoPlayerController _videoController;
  bool _hasNavigated = false;

  @override
  void initState() {
    super.initState();
    _videoController = VideoPlayerController.asset('assets/logo animation.mp4');
    _initializeVideo();
  }

  Future<void> _initializeVideo() async {
    try {
      await _videoController.initialize();
      await _videoController.setVolume(0);
      await _videoController.setLooping(false);

      _videoController.addListener(_onVideoProgress);
      await _videoController.play();

      if (mounted) setState(() {});
    } catch (_) {
      _goToLogin();
    }
  }

  void _onVideoProgress() {
    if (!_videoController.value.isInitialized) return;

    final duration = _videoController.value.duration;
    final position = _videoController.value.position;

    if (duration > Duration.zero && position >= duration) {
      _goToLogin();
    }
  }

  void _goToLogin() {
    if (_hasNavigated || !mounted) return;
    _hasNavigated = true;
    Navigator.pushReplacementNamed(context, LoginScreen.routeName);
  }

  @override
  void dispose() {
    _videoController.removeListener(_onVideoProgress);
    _videoController.dispose();
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
                child: _videoController.value.isInitialized
                    ? AspectRatio(
                        aspectRatio: _videoController.value.aspectRatio,
                        child: VideoPlayer(_videoController),
                      )
                    : const SizedBox(
                        width: 36,
                        height: 36,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.8,
                          color: Colors.white54,
                        ),
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
