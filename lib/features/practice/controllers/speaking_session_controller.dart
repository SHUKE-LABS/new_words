import 'package:flutter/foundation.dart';
import 'package:new_words/features/practice/models/listening_item.dart';
import 'package:new_words/features/practice/utils/listening_scorer.dart';

/// What the user has done with the current sentence.
enum SpeakingItemStatus {
  /// Not attempted yet, or cleared by a retry.
  pending,

  /// Recording; a partial transcript may already be arriving.
  recording,

  /// Recorded and scored; [SpeakingSessionController.lastScore] holds the
  /// result.
  scored,
}

/// One sentence's outcome, recorded as the session moves past it.
class SpeakingResult {
  final ListeningItem item;
  final ListeningOutcome? outcome;

  const SpeakingResult({required this.item, required this.outcome});

  bool get isPass => outcome == ListeningOutcome.pass;
}

/// Drives one speaking session: which sentence is current, whether it is being
/// recorded, and how the last attempt scored.
///
/// Knows nothing about audio, the microphone or permissions — the screen owns
/// `StoryAudioController` and `SttService` and feeds transcripts in here, so
/// there is exactly one scoring path in the app and it is #36's.
class SpeakingSessionController extends ChangeNotifier {
  final List<ListeningItem> items;
  final ScoringMetric metric;

  SpeakingSessionController({required this.items, required this.metric});

  int _index = 0;
  SpeakingItemStatus _status = SpeakingItemStatus.pending;
  ListeningScore? _lastScore;
  String _transcript = '';
  bool _complete = false;
  final List<SpeakingResult> _results = [];

  int get index => _index;
  SpeakingItemStatus get status => _status;
  ListeningScore? get lastScore => _lastScore;

  /// The latest transcript for the current sentence, partial or final.
  String get transcript => _transcript;

  bool get isComplete => _complete;
  bool get isEmpty => items.isEmpty;
  int get total => items.length;

  /// 1-based position for the `n/m` counter.
  int get position => _index + 1;

  bool get isRecording => _status == SpeakingItemStatus.recording;

  List<SpeakingResult> get results => List.unmodifiable(_results);

  int get passCount => _results.where((r) => r.isPass).length;

  ListeningItem? get currentItem =>
      items.isEmpty || _complete ? null : items[_index];

  /// Marks the current sentence as being recorded and clears the last attempt.
  void startRecording() {
    if (currentItem == null) return;
    _transcript = '';
    _lastScore = null;
    _status = SpeakingItemStatus.recording;
    notifyListeners();
  }

  /// Records a partial transcript without scoring it.
  void updateTranscript(String transcript) {
    if (_status != SpeakingItemStatus.recording) return;
    _transcript = transcript;
    notifyListeners();
  }

  /// Scores [transcript] against the current sentence.
  ///
  /// Always the whole sentence: a cloze item from the shared set builder is
  /// still a sentence to say aloud, so its blanked span is not the reference
  /// here.
  void score(String transcript) {
    final item = currentItem;
    if (item == null) return;

    _transcript = transcript;
    _lastScore = ListeningScorer.scoreDictation(
      item.sentence,
      transcript,
      metric,
    );
    _status = SpeakingItemStatus.scored;
    notifyListeners();
  }

  /// Ends recording with nothing recognized, leaving the item unscored so the
  /// screen can explain and offer another attempt.
  void abandonRecording() {
    if (_status != SpeakingItemStatus.recording) return;
    _status = SpeakingItemStatus.pending;
    _transcript = '';
    notifyListeners();
  }

  /// Clears the attempt so the sentence can be heard and said again.
  void retry() {
    if (currentItem == null) return;
    _transcript = '';
    _lastScore = null;
    _status = SpeakingItemStatus.pending;
    notifyListeners();
  }

  /// Records the current sentence's outcome and advances, completing after the
  /// last one.
  void next() {
    final item = currentItem;
    if (item == null) return;

    _results.add(SpeakingResult(item: item, outcome: _lastScore?.outcome));

    _transcript = '';
    _lastScore = null;
    _status = SpeakingItemStatus.pending;

    if (_index + 1 >= items.length) {
      _complete = true;
    } else {
      _index++;
    }
    notifyListeners();
  }

  /// Starts the set over. Results are in-session only, so nothing is persisted
  /// or lost.
  void restart() {
    _index = 0;
    _status = SpeakingItemStatus.pending;
    _transcript = '';
    _lastScore = null;
    _complete = false;
    _results.clear();
    notifyListeners();
  }
}
