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
import 'package:speech_to_text/speech_to_text.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_mlkit_translation/google_mlkit_translation.dart';

// ── Global camera list (initialised in main) ──────────────────────────────────
List<CameraDescription> _cameras = [];

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  _cameras = await availableCameras();

  final prefs = await SharedPreferences.getInstance();
  final savedLanguage = prefs.getString('language');

  runApp(SignScribeApp(showLanguageSetup: savedLanguage == null));
}

// ── App root ──────────────────────────────────────────────────────────────────

class SignScribeApp extends StatelessWidget {
  final bool showLanguageSetup;
  const SignScribeApp({super.key, required this.showLanguageSetup});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SignScribe',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: WelcomeScreen(showLanguageSetup: showLanguageSetup),
    );
  }
}

// ── Welcome screen ────────────────────────────────────────────────────────────

class WelcomeScreen extends StatefulWidget {
  final bool showLanguageSetup;
  const WelcomeScreen({super.key, required this.showLanguageSetup});

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
            MaterialPageRoute(
              builder: (_) => widget.showLanguageSetup
                  ? const LanguageSetupScreen()   // ← first time
                  : const HomeScreen(),           // ← returning user
            ),
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
        body: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,  // ← was 'start'
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  'SignScribe',
                  style: Theme.of(context).textTheme.headlineLarge,
                  textAlign: TextAlign.center,
                ),
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
                Text(
                  'Your personal interpreter',
                  style: Theme.of(context).textTheme.bodyLarge,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
    );
  }
}


// ── Language setup screen (shown only on first launch) ───────────────────────

class LanguageSetupScreen extends StatefulWidget {
  const LanguageSetupScreen({super.key});

  @override
  State<LanguageSetupScreen> createState() => _LanguageSetupScreenState();
}

class _LanguageSetupScreenState extends State<LanguageSetupScreen> {
  String _selectedLanguage = 'English';
  late VideoPlayerController _controller;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.asset('assets/welcome_video.mp4')
      ..initialize().then((_) {
        if (mounted) {
          setState(() {});
          _controller.setLooping(true);
          _controller.play();
        }
      });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('language', _selectedLanguage);
    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const HomeScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // ── Question ──────────────────────────────────────────────
                Text(
                  'Which language are you comfortable reading in?',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  textAlign: TextAlign.center,
                ),

                const SizedBox(height: 32),

                // ── Circular video ────────────────────────────────────────
                ClipOval(
                  child: SizedBox(
                    width: 160,
                    height: 160,
                    child: _controller.value.isInitialized
                        ? AspectRatio(
                      aspectRatio: _controller.value.aspectRatio,
                      child: VideoPlayer(_controller),
                    )
                        : Container(
                      color: cs.surfaceVariant,
                      child: const Center(
                          child: CircularProgressIndicator()),
                    ),
                  ),
                ),

                const SizedBox(height: 32),

                // ── Dropdown ──────────────────────────────────────────────
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    border: Border.all(color: cs.outline),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _selectedLanguage,
                      isExpanded: true,
                      items: const [
                        DropdownMenuItem(
                            value: 'English', child: Text('English')),
                        DropdownMenuItem(
                            value: 'Hindi', child: Text('Hindi')),
                      ],
                      onChanged: (value) {
                        if (value != null) {
                          setState(() => _selectedLanguage = value);
                        }
                      },
                    ),
                  ),
                ),

                const SizedBox(height: 32),

                // ── Save button ───────────────────────────────────────────
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _saving ? null : _save,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _saving
                        ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                        : const Text('Save',
                        style: TextStyle(fontSize: 16)),
                  ),
                ),
              ],
            ),
          ),
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
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const CallLanguageScreen()),
    );
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
                      child: const Text('Start Live Call'),
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

// ── Live call screen ──────────────────────────────────────────────────────────

enum _LiveCallState {
  idle,        // showing "Start Signing" and "Listen"
  recording,   // recording video, only "Stop" visible
  processing,  // uploading, waiting for translation
  result,      // showing translation + "Play Aloud" + "Listen"
  listening,   // STT active, showing "Start Signing"
}


class CallLanguageScreen extends StatefulWidget {
  const CallLanguageScreen({super.key});

  @override
  State<CallLanguageScreen> createState() => _CallLanguageScreenState();
}

class _CallLanguageScreenState extends State<CallLanguageScreen> {
  String _selectedLanguage = 'English';

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'Choose your language',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  textAlign: TextAlign.center,
                ),

                const SizedBox(height: 32),

                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    border: Border.all(color: cs.outline),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _selectedLanguage,
                      isExpanded: true,
                      items: const [
                        DropdownMenuItem(
                            value: 'English', child: Text('English')),
                        DropdownMenuItem(
                            value: 'Hindi', child: Text('Hindi')),
                      ],
                      onChanged: (value) {
                        if (value != null) {
                          setState(() => _selectedLanguage = value);
                        }
                      },
                    ),
                  ),
                ),

                const SizedBox(height: 32),

                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.of(context).pushReplacement(
                        MaterialPageRoute(
                          builder: (_) => LiveCallScreen(
                            callLanguage: _selectedLanguage,
                          ),
                        ),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text('Submit',
                        style: TextStyle(fontSize: 16)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}


class LiveCallScreen extends StatefulWidget {
  final String callLanguage;
  const LiveCallScreen({super.key, required this.callLanguage});

  @override
  State<LiveCallScreen> createState() => _LiveCallScreenState();
}

class _LiveCallScreenState extends State<LiveCallScreen> {
  // ── Camera ────────────────────────────────────────────────────────────────
  late CameraController _cam;
  bool _camReady = false;
  late String _callLanguage;
  OnDeviceTranslator? _translator;

  // ── State machine ─────────────────────────────────────────────────────────
  _LiveCallState _state = _LiveCallState.idle;

  // ── Results ───────────────────────────────────────────────────────────────
  String? _translation;   // from sign → text
  String? _listenedText;  // from speech → text
  String? _error;

  // ── TTS ───────────────────────────────────────────────────────────────────
  final FlutterTts _tts = FlutterTts();
  bool _ttsReady = false;

  // ── STT ───────────────────────────────────────────────────────────────────
  final SpeechToText _stt = SpeechToText();
  bool _sttAvailable = false;

  @override
  void initState() {
    super.initState();
    _callLanguage = widget.callLanguage;  // ← from CallLanguageScreen
    _initCamera();
    _initTts();
    _initStt();
    _loadLanguage();
    _initCallTranslator();               // ← replaces _loadLanguage()
  }

  Future<void> _loadLanguage() async {
    final prefs = await SharedPreferences.getInstance();
    final language = prefs.getString('language') ?? 'English';
    if (mounted) setState(() => _callLanguage = language);

    // Only create translator if not English
    if (language != 'English') {
      const mlKitLanguageMap = {
        'Hindi':     TranslateLanguage.hindi,
        'Tamil':     TranslateLanguage.tamil,
        'Telugu':    TranslateLanguage.telugu,
        'Kannada':   TranslateLanguage.kannada,
        'Bengali':   TranslateLanguage.bengali,
        'Marathi':   TranslateLanguage.marathi,
        'Gujarati':  TranslateLanguage.gujarati,
      };

      final targetLanguage = mlKitLanguageMap[language];
      if (targetLanguage != null) {
        _translator = OnDeviceTranslator(
          sourceLanguage: TranslateLanguage.english,
          targetLanguage: targetLanguage,
        );

        // Download model in background if not already present
        final modelManager = OnDeviceTranslatorModelManager();
        final downloaded = await modelManager.isModelDownloaded(targetLanguage.bcpCode);
        if (!downloaded) {
          await modelManager.downloadModel(targetLanguage.bcpCode);
        }
      }
    }
  }

  Future<void> _initCallTranslator() async {
    const mlKitLanguageMap = {
      'Hindi':     TranslateLanguage.hindi,
      'Tamil':     TranslateLanguage.tamil,
      'Telugu':    TranslateLanguage.telugu,
      'Kannada':   TranslateLanguage.kannada,
      'Bengali':   TranslateLanguage.bengali,
      'Marathi':   TranslateLanguage.marathi,
      'Gujarati':  TranslateLanguage.gujarati,
    };

    final targetLanguage = mlKitLanguageMap[_callLanguage];
    if (targetLanguage != null) {
      _translator = OnDeviceTranslator(
        sourceLanguage: TranslateLanguage.english,
        targetLanguage: targetLanguage,
      );
      final modelManager = OnDeviceTranslatorModelManager();
      final downloaded = await modelManager.isModelDownloaded(
          targetLanguage.bcpCode);
      if (!downloaded) {
        await modelManager.downloadModel(targetLanguage.bcpCode);
      }
    }
  }

  Future<void> _initCamera() async {
    final desc = _cameras.firstWhere(
          (c) => c.lensDirection == CameraLensDirection.front,
      orElse: () => _cameras.first,
    );
    _cam = CameraController(
      desc,
      ResolutionPreset.medium,
      enableAudio: false,
    );
    try {
      await _cam.initialize();
      if (mounted) setState(() => _camReady = true);
    } catch (e) {
      if (mounted) setState(() => _error = 'Camera error: $e');
    }
  }

  Future<void> _initTts() async {
    await _tts.setLanguage('en-US');
    await _tts.setSpeechRate(0.5);
    if (mounted) setState(() => _ttsReady = true);
  }

  Future<void> _initStt() async {
    _sttAvailable = await _stt.initialize();
    if (mounted) setState(() {});
  }

  // ── Recording ─────────────────────────────────────────────────────────────

  Future<void> _startSigning() async {
    try {
      await _cam.startVideoRecording();
      setState(() {
        _state = _LiveCallState.recording;
        _translation = null;
        _listenedText = null;
        _error = null;
      });
    } catch (e) {
      setState(() => _error = 'Recording error: $e');
    }
  }

  Future<void> _stopSigning() async {
    setState(() => _state = _LiveCallState.processing);
    try {
      final file = await _cam.stopVideoRecording();
      final englishResult = await _uploadVideo(File(file.path));

      // Translate if call language is not English
      String displayResult = englishResult;
      if (_translator != null) {
        displayResult = await _translator!.translateText(englishResult);
      }

      setState(() {
        _translation = displayResult;
        _state = _LiveCallState.result;
      });
    } catch (e) {
      setState(() {
        _error = 'Error: $e';
        _state = _LiveCallState.idle;
      });
    }
  }

  // ── Upload (same as HomeScreen) ───────────────────────────────────────────

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
    final streamed = await request.send().timeout(const Duration(seconds: 120));
    final response = await http.Response.fromStream(streamed);
    if (response.statusCode != 200) {
      throw Exception('Server error: ${response.statusCode}');
    }
    if (response.body.isEmpty) throw Exception('Empty response');
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return json['translation'] as String? ?? 'No translation found';
  }

  // ── TTS ───────────────────────────────────────────────────────────────────

  Future<void> _playAloud() async {
    if (!_ttsReady || _translation == null) return;

    const ttsLocaleMap = {
      'Hindi':     'hi-IN',
      'Tamil':     'ta-IN',
      'Telugu':    'te-IN',
      'Kannada':   'kn-IN',
      'Bengali':   'bn-IN',
      'Marathi':   'mr-IN',
      'Gujarati':  'gu-IN',
    };

    final locale = ttsLocaleMap[_callLanguage] ?? 'en-US';
    await _tts.setLanguage(locale);
    await _tts.speak(_translation!);
  }

  // ── STT ───────────────────────────────────────────────────────────────────

  Future<void> _startListening() async {
    if (!_sttAvailable) {
      setState(() => _error = 'Speech recognition not available');
      return;
    }
    setState(() {
      _state = _LiveCallState.listening;
      _listenedText = null;
    });

    const sttLocaleMap = {
      'Hindi':     'hi-IN',
      'Tamil':     'ta-IN',
      'Telugu':    'te-IN',
      'Kannada':   'kn-IN',
      'Malayalam': 'ml-IN',
      'Bengali':   'bn-IN',
      'Marathi':   'mr-IN',
      'Gujarati':  'gu-IN',
      'Punjabi':   'pa-IN',
    };

    final locale = sttLocaleMap[_callLanguage] ?? 'en-US';

    await _stt.listen(
      onResult: (result) {
        if (mounted) setState(() => _listenedText = result.recognizedWords);
      },
      listenFor: const Duration(seconds: 30),
      pauseFor: const Duration(seconds: 5),
      localeId: locale,
      listenOptions: SpeechListenOptions(partialResults: true),
    );
  }

  Future<void> _stopListening() async {
    await _stt.stop();
  }

  @override
  void dispose() {
    _cam.dispose();
    _translator?.close();
    _tts.stop();
    _stt.stop();
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
          // ── Translucent camera preview ────────────────────────────────
          if (_camReady)
            Opacity(
              opacity: 0.15,   // almost black, slightly visible like FaceTime
              child: CameraPreview(_cam),
            ),

          // ── Main content overlay ──────────────────────────────────────
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Back button (hidden during recording)
                      if (_state != _LiveCallState.recording)
                        IconButton(
                          icon: const Icon(Icons.arrow_back, color: Colors.white),
                          onPressed: () => Navigator.of(context).pop(),
                        )
                      else
                        const SizedBox(width: 48), // keep layout balanced

                      // End Call — always visible
                      _TextButton(
                        onTap: () => Navigator.of(context).pop(),
                        label: 'End Call',
                        color: Colors.red,
                        textColor: Colors.white,
                      ),
                    ],
                  ),
                ),

                const Spacer(),

                // ── Centre content area ─────────────────────────────────
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: _buildCentreContent(),
                ),

                const Spacer(),

                // ── Bottom controls ─────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.only(bottom: 48),
                  child: _buildControls(),
                ),
              ],
            ),
          ),

          // ── Error ─────────────────────────────────────────────────────
          if (_error != null)
            Positioned(
              bottom: 120,
              left: 24,
              right: 24,
              child: Text(
                _error!,
                style: const TextStyle(color: Colors.red),
                textAlign: TextAlign.center,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCentreContent() {
    switch (_state) {
      case _LiveCallState.idle:
        return const Text(
          'Start signing or listen to the other person',
          style: TextStyle(color: Colors.white70, fontSize: 16),
          textAlign: TextAlign.center,
        );

      case _LiveCallState.recording:
        return const Text(
          'Recording…',
          style: TextStyle(color: Colors.redAccent, fontSize: 18),
          textAlign: TextAlign.center,
        );

      case _LiveCallState.processing:
        return const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: Colors.white),
            SizedBox(height: 16),
            Text('Translating…',
                style: TextStyle(color: Colors.white70, fontSize: 16)),
          ],
        );

      case _LiveCallState.result:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Translation card
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white24),
              ),
              child: Column(
                children: [
                  const Text('\u201C',
                      style: TextStyle(color: Colors.white38, fontSize: 40)),
                  Text(
                    _translation ?? '',
                    style: const TextStyle(
                        color: Colors.white, fontSize: 20, height: 1.4),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  const Text('Interpreted Sign Language',
                      style: TextStyle(color: Colors.white38, fontSize: 12)),
                ],
              ),
            ),

            // Listened text (if any)
            if (_listenedText != null && _listenedText!.isNotEmpty) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white12),
                ),
                child: Column(
                  children: [
                    const Text('They said:',
                        style:
                        TextStyle(color: Colors.white38, fontSize: 12)),
                    const SizedBox(height: 6),
                    Text(
                      _listenedText!,
                      style: const TextStyle(
                          color: Colors.white70, fontSize: 16),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ],
          ],
        );

      case _LiveCallState.listening:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.mic, color: Colors.white, size: 48),
            const SizedBox(height: 12),
            Text(
              _listenedText?.isNotEmpty == true
                  ? _listenedText!
                  : 'Listening…',
              style: const TextStyle(color: Colors.white70, fontSize: 18),
              textAlign: TextAlign.center,
            ),
          ],
        );
    }
  }

  Widget _buildControls() {
    switch (_state) {
      case _LiveCallState.idle:
      case _LiveCallState.result:
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _TextButton(
              onTap: _startSigning,
              label: 'Start Signing',
              color: Colors.white,
              textColor: Colors.black,
            ),
            const SizedBox(width: 16),
            _TextButton(
              onTap: _startListening,
              label: 'Listen',
              color: Colors.white24,
              textColor: Colors.white,
            ),
          ],
        );

      case _LiveCallState.recording:
        return _TextButton(
          onTap: _stopSigning,
          label: 'Stop',
          color: Colors.red,
          textColor: Colors.white,
        );

      case _LiveCallState.processing:
        return const SizedBox.shrink();

      case _LiveCallState.listening:
        return _TextButton(
          onTap: () async {
            await _stopListening();
            setState(() => _state = _LiveCallState.result);
          },
          label: 'Stop',
          color: Colors.white24,
          textColor: Colors.white,
        );
    }
  }
}

class _TextButton extends StatelessWidget {
  final VoidCallback onTap;
  final String label;
  final Color color;
  final Color textColor;

  const _TextButton({
    required this.onTap,
    required this.label,
    required this.color,
    required this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(40),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: textColor,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
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