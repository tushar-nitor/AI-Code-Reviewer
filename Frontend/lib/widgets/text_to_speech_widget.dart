import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:google_fonts/google_fonts.dart';

// An enum to manage the TTS player state for cleaner code
enum TtsState { playing, stopped, paused }

/// A utility class to display a sleek, floating Text-to-Speech player.
class FloatingAudioPlayer {
  static OverlayEntry? _currentEntry;

  /// Displays the floating player at the bottom of the screen.
  static void show(BuildContext context, {required String textToSpeak}) {
    // Dismiss any existing player before showing a new one
    if (_currentEntry != null) {
      _currentEntry?.remove();
      _currentEntry = null;
    }

    _currentEntry = OverlayEntry(
      builder: (context) {
        // This function is passed to the UI to allow it to dismiss itself.
        void removeOverlay() {
          if (_currentEntry != null) {
            _currentEntry?.remove();
            _currentEntry = null;
          }
        }

        return _FloatingAudioPlayerUI(textToSpeak: textToSpeak, onDismiss: removeOverlay);
      },
    );

    Overlay.of(context).insert(_currentEntry!);
  }
}

/// The actual UI for the floating player.
class _FloatingAudioPlayerUI extends StatefulWidget {
  final String textToSpeak;
  final VoidCallback onDismiss;

  const _FloatingAudioPlayerUI({required this.textToSpeak, required this.onDismiss});

  @override
  State<_FloatingAudioPlayerUI> createState() => _FloatingAudioPlayerUIState();
}

class _FloatingAudioPlayerUIState extends State<_FloatingAudioPlayerUI> with SingleTickerProviderStateMixin {
  late FlutterTts _flutterTts;
  TtsState _ttsState = TtsState.stopped;

  late AnimationController _animationController;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _initializeTts();
    _initializeAnimation();
  }

  void _initializeAnimation() {
    _animationController = AnimationController(vsync: this, duration: const Duration(milliseconds: 300));
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 2),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _animationController, curve: Curves.easeOut));
    _animationController.forward();
  }

  void _initializeTts() async {
    _flutterTts = FlutterTts();

    // Set up the state handlers
    _flutterTts
      ..setStartHandler(() {
        if (mounted) setState(() => _ttsState = TtsState.playing);
      })
      ..setCompletionHandler(() {
        if (mounted) setState(() => _ttsState = TtsState.stopped);
      })
      ..setErrorHandler((msg) {
        if (mounted) setState(() => _ttsState = TtsState.stopped);
      })
      ..setPauseHandler(() {
        if (mounted) setState(() => _ttsState = TtsState.paused);
      });

    // --- FIX 1: ROBUST VOICE SELECTION ---
    // Get the list of available voices.
    var voices = await _flutterTts.getVoices;
    // The voices are returned as a List<Map<String, String>>, so we cast it.
    var castedVoices = List<Map<String, String>>.from(voices.map((v) => Map<String, String>.from(v)));

    // Find a suitable US English voice.
    Map<String, String>? selectedVoice = castedVoices.firstWhere(
      (voice) => voice['locale'] == 'en-US' && voice['name']!.toLowerCase().contains('female'),
      orElse: () => castedVoices.firstWhere(
        // Fallback 1: Any US English voice
        (voice) => voice['locale'] == 'en-US',
        orElse: () => castedVoices.firstWhere(
          // Fallback 2: Any English voice
          (voice) => voice['locale']?.startsWith('en-') ?? false,
          orElse: () => {}, // Fallback 3: No voice found
        ),
      ),
    );
    print("Selected voice ==== >> ${selectedVoice}");

    if (selectedVoice.isNotEmpty) {
      await _flutterTts.setVoice(selectedVoice);
    }
    // --- END OF FIX 1 ---

    // Automatically start speaking after initialization.
    _speak(widget.textToSpeak);
  }

  // --- FIX 2: RELIABLE PLAY/RESTART LOGIC ---
  Future<void> _speak(String text) async {
    if (_ttsState == TtsState.stopped) {
      // If the audio was stopped (or completed), we must call stop() first
      // to reset the engine before speaking again.
      await _flutterTts.stop();
    }
    // Now, calling speak will work correctly whether it's the first time,
    // resuming from pause, or restarting from a stopped state.
    await _flutterTts.speak(text);
  }

  Future<void> _pause() async {
    await _flutterTts.pause();
  }

  Future<void> _stop() async {
    await _flutterTts.stop();
  }
  // --- END OF FIX 2 ---

  void _dismissPlayer() {
    // Stop any speech before dismissing
    _flutterTts.stop();
    _animationController.reverse().whenComplete(widget.onDismiss);
  }

  @override
  void dispose() {
    // It's crucial to stop the TTS engine when the widget is disposed
    // to prevent memory leaks and background audio.
    _flutterTts.stop();
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      left: 20,
      right: 20,
      child: SlideTransition(
        position: _slideAnimation,
        child: Dismissible(
          key: UniqueKey(),
          direction: DismissDirection.down,
          onDismissed: (_) => _dismissPlayer(),
          child: Material(
            elevation: 0,
            color: Colors.transparent,
            child: Container(
              padding: const EdgeInsets.all(2.0),
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [Colors.purple, Colors.blue, Colors.cyan]),
                borderRadius: BorderRadius.circular(18),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(color: Theme.of(context).colorScheme.secondaryContainer.withOpacity(0.6)),
                    child: Row(
                      children: [
                        Icon(Icons.speaker_notes_rounded, color: Theme.of(context).colorScheme.onSecondaryContainer),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Expert Advice...',
                            style: GoogleFonts.poppins(
                              fontWeight: FontWeight.w500,
                              color: Theme.of(context).colorScheme.onSecondaryContainer,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        _buildTtsControls(widget.textToSpeak),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTtsControls(String textToSpeak) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      transitionBuilder: (child, animation) {
        return ScaleTransition(scale: animation, child: child);
      },
      child: switch (_ttsState) {
        TtsState.playing => Row(
          key: const ValueKey('playing'),
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.pause_rounded),
              onPressed: _pause,
              tooltip: 'Pause',
              color: Theme.of(context).colorScheme.onSecondaryContainer,
            ),
            IconButton(
              icon: const Icon(Icons.stop_rounded),
              onPressed: _stop,
              tooltip: 'Stop',
              color: Theme.of(context).colorScheme.onSecondaryContainer,
            ),
          ],
        ),
        TtsState.paused || TtsState.stopped => IconButton(
          key: const ValueKey('paused_stopped'),
          icon: const Icon(Icons.play_arrow_rounded),
          onPressed: () => _speak(textToSpeak),
          tooltip: _ttsState == TtsState.paused ? 'Resume' : 'Play',
          color: Theme.of(context).colorScheme.onSecondaryContainer,
        ),
      },
    );
  }
}
