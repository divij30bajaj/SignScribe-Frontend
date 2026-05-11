import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_tts/flutter_tts.dart';
import 'package:http_parser/http_parser.dart';
import 'package:camera/camera.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

// ── Global camera list (initialised in main) ──────────────────────────────────
List<CameraDescription> _cameras = [];

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  _cameras = await availableCameras();
  runApp(const SignScribeApp());
}

// ── App root ──────────────────────────────────────────────────────────────────

class SignScribeApp extends StatelessWidget {
  const SignScribeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SignScribe',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const WelcomeScreen(),
    );
  }
}

// ── Welcome screen ────────────────────────────────────────────────────────────

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  late VideoPlayerController _controller;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.asset('assets/welcome_video.mp4')
      ..initialize().then((_) {
        if (mounted) {
          setState(() {});
          _controller.play();
        }
      });

    _controller.addListener(() {
      if (_controller.value.isInitialized &&
          !_controller.value.isPlaying &&
          _controller.value.position >= _controller.value.duration) {
        if (mounted) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const HomeScreen()),
          );
        }
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const SizedBox(height: 60),
            Text('SignScribe',
                style: Theme.of(context).textTheme.headlineLarge,
                textAlign: TextAlign.center),
            const SizedBox(height: 24),
            ClipOval(
              child: SizedBox(
                width: 180,
                height: 180,
                child: _controller.value.isInitialized
                    ? AspectRatio(
                  aspectRatio: _controller.value.aspectRatio,
                  child: VideoPlayer(_controller),
                )
                    : Container(
                  color: Theme.of(context).colorScheme.surfaceVariant,
                  child: const Center(child: CircularProgressIndicator()),
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text('Welcome to SignScribe',
                style: Theme.of(context).textTheme.bodyLarge,
                textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

// ── Home screen ───────────────────────────────────────────────────────────────

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String _statusText = 'No video selected';
  bool _isUploading = false;

  final FlutterTts _tts = FlutterTts();
  bool _ttsReady = false;
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _initTts();
  }

  Future<void> _initTts() async {
    await _tts.setLanguage('en-US');
    await _tts.setSpeechRate(0.5);
    if (mounted) setState(() => _ttsReady = true);
  }

  @override
  void dispose() {
    _tts.stop();
    super.dispose();
  }

  // ── Upload: multipart POST → parse JSON → extract 'translation' ───────────

  Future<String> _uploadVideo(File videoFile) async {
    const backendUrl = 'http://3.109.38.123:8000/video/upload';

    final request = http.MultipartRequest('POST', Uri.parse(backendUrl));
    request.files.add(
      await http.MultipartFile.fromPath(
        'video',
        videoFile.path,
        contentType: MediaType('video', 'mp4'),
      ),
    );

    final streamed =
    await request.send().timeout(const Duration(seconds: 120));
    final response = await http.Response.fromStream(streamed);

    if (response.statusCode != 200) {
      throw Exception('Server error: ${response.statusCode}');
    }
    if (response.body.isEmpty) throw Exception('Empty response from server');

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return json['translation'] as String? ?? 'No translation found';
  }

  Future<void> _handleResult(String result) async {
    if (mounted) setState(() => _statusText = result);
  }

  Future<void> _handleUpload(File file) async {
    setState(() {
      _isUploading = true;
      _statusText = 'Uploading…';
    });
    try {
      final result = await _uploadVideo(file);
      await _handleResult(result);
    } catch (e) {
      if (mounted) setState(() => _statusText = 'Upload failed: $e');
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  Future<void> _pickVideo() async {
    final picked = await _picker.pickVideo(source: ImageSource.gallery);
    if (picked == null) return;
    await _handleUpload(File(picked.path));
  }

  // ── Record: open CameraStreamScreen, await translation result ────────────

  Future<void> _openCamera() async {
    if (_cameras.isEmpty) {
      setState(() => _statusText = 'No camera available.');
      return;
    }
    final result = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const CameraStreamScreen()),
    );
    if (result != null) await _handleResult(result);
  }

  Future<void> _speak() async {
    if (_ttsReady) await _tts.speak(_statusText);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: const Text('SignScribe'),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.menu),
            onSelected: (_) {},
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'settings', child: Text('Settings')),
              PopupMenuItem(value: 'about', child: Text('About')),
            ],
          ),
        ],
      ),
      body: Stack(
        children: [
          // ── Centre: spinner / result card / placeholder ─────────────────
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: _isUploading
                  ? const Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Processing video…'),
                ],
              )
                  : _statusText != 'No video selected'
                  ? ResultCard(
                text: _statusText,
                ttsReady: _ttsReady,
                onPlay: _speak,
              )
                  : Text(
                _statusText,
                textAlign: TextAlign.center,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(
                  color: Theme.of(context)
                      .colorScheme
                      .onSurfaceVariant,
                ),
              ),
            ),
          ),

          // ── Bottom buttons ──────────────────────────────────────────────
          Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _isUploading ? null : _pickVideo,
                      child: Text(
                          _isUploading ? 'Uploading…' : 'Upload Video'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _isUploading ? null : _openCamera,
                      child: const Text('Record'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Camera stream screen ──────────────────────────────────────────────────────

class CameraStreamScreen extends StatefulWidget {
  const CameraStreamScreen({super.key});

  @override
  State<CameraStreamScreen> createState() => _CameraStreamScreenState();
}

class _CameraStreamScreenState extends State<CameraStreamScreen> {
  late CameraController _cam;
  WebSocketChannel? _channel;

  bool _camReady = false;
  bool _streaming = false;   // true while frames are being sent
  bool _waiting = false;     // true after STOP, waiting for server response
  String? _error;

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera() async {
    // Prefer front camera for sign language; fall back to first available
    final desc = _cameras.firstWhere(
          (c) => c.lensDirection == CameraLensDirection.front,
      orElse: () => _cameras.first,
    );

    _cam = CameraController(
      desc,
      ResolutionPreset.medium,   // medium = good balance of quality vs bandwidth
      enableAudio: false,        // we only need frames, not audio
      imageFormatGroup: ImageFormatGroup.jpeg,
    );

    try {
      await _cam.initialize();
      if (mounted) setState(() => _camReady = true);
    } catch (e) {
      if (mounted) setState(() => _error = 'Camera error: $e');
    }
  }

  // ── Start streaming ───────────────────────────────────────────────────────

  Future<void> _startStreaming() async {
    const wsUrl = 'ws://3.109.38.123:8000/video/stream';

    try {
      _channel = WebSocketChannel.connect(Uri.parse(wsUrl));
      setState(() => _streaming = true);

      // Send each captured frame as raw JPEG bytes
      await _cam.startImageStream((CameraImage image) {
        if (!_streaming) return;

        // CameraImage with JPEG group gives us the bytes directly in plane[0]
        final bytes = image.planes[0].bytes;
        try {
          _channel?.sink.add(bytes);
        } catch (_) {
          // socket closed mid-stream — stop gracefully
          _stopStreaming();
        }
      });
    } catch (e) {
      if (mounted) setState(() => _error = 'WebSocket error: $e');
    }
  }

  // ── Stop streaming → send STOP → wait for response ───────────────────────

  Future<void> _stopStreaming() async {
    if (!_streaming) return;

    setState(() {
      _streaming = false;
      _waiting = true;
    });

    await _cam.stopImageStream();

    // Signal the server that recording is done
    _channel?.sink.add('STOP');

    // Wait for the server's JSON response
    try {
      final response = await _channel!.stream.first
          .timeout(const Duration(seconds: 60));

      final json = jsonDecode(response as String) as Map<String, dynamic>;
      final translation = json['translation'] as String? ?? 'No translation';

      if (mounted) Navigator.of(context).pop(translation); // return to HomeScreen
    } catch (e) {
      if (mounted) {
        setState(() {
          _waiting = false;
          _error = 'Failed to receive response: $e';
        });
      }
    } finally {
      await _channel?.sink.close();
    }
  }

  @override
  void dispose() {
    _cam.dispose();
    _channel?.sink.close();
    super.dispose();
  }

  // ── UI ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // ── Camera preview ──────────────────────────────────────────────
          if (_camReady) CameraPreview(_cam),

          // ── Error message ───────────────────────────────────────────────
          if (_error != null)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(_error!,
                    style: const TextStyle(color: Colors.red, fontSize: 16),
                    textAlign: TextAlign.center),
              ),
            ),

          // ── Waiting spinner (after STOP, before response) ───────────────
          if (_waiting)
            Container(
              color: Colors.black54,
              child: const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: Colors.white),
                    SizedBox(height: 16),
                    Text('Waiting for translation…',
                        style: TextStyle(color: Colors.white, fontSize: 16)),
                  ],
                ),
              ),
            ),

          // ── Bottom controls ─────────────────────────────────────────────
          if (!_waiting)
            Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 48),
                child: _streaming
                // ── STOP button ────────────────────────────────────────
                    ? GestureDetector(
                  onTap: _stopStreaming,
                  child: Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 4),
                    ),
                    child: const Icon(Icons.stop,
                        color: Colors.white, size: 36),
                  ),
                )
                // ── START button ───────────────────────────────────────
                    : _camReady
                    ? GestureDetector(
                  onTap: _startStreaming,
                  child: Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: Colors.red, width: 6),
                    ),
                  ),
                )
                    : const CircularProgressIndicator(
                    color: Colors.white),
              ),
            ),

          // ── Back button (top-left) ──────────────────────────────────────
          if (!_streaming && !_waiting)
            Positioned(
              top: 48,
              left: 16,
              child: IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
        ],
      ),
    );
  }
}

// ── Result card ───────────────────────────────────────────────────────────────

class ResultCard extends StatelessWidget {
  final String text;
  final bool ttsReady;
  final VoidCallback onPlay;

  const ResultCard({
    super.key,
    required this.text,
    required this.ttsReady,
    required this.onPlay,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      color: cs.primaryContainer,
      elevation: 6,
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('\u201C',
                style: tt.displayLarge
                    ?.copyWith(color: cs.primary.withOpacity(0.4))),
            Text(
              text,
              style: tt.titleLarge?.copyWith(
                  fontWeight: FontWeight.w500, height: 1.4),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text('Interpreted Sign Language',
                style: tt.labelMedium
                    ?.copyWith(color: cs.primary.withOpacity(0.7))),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: ttsReady ? onPlay : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: cs.primary,
                foregroundColor: cs.onPrimary,
                shape: const StadiumBorder(),
                padding: const EdgeInsets.symmetric(
                    horizontal: 28, vertical: 12),
              ),
              icon: const Icon(Icons.play_arrow, size: 20),
              label: const Text('Play Aloud'),
            ),
          ],
        ),
      ),
    );
  }
}