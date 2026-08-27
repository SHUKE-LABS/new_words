import 'package:flutter/foundation.dart';
import 'package:new_words/features/practice/models/listening_item.dart';
import 'package:new_words/features/practice/utils/listening_scorer.dart';

/// What the user has done with the current item.
enum ListeningItemStatus {
  /// Not checked yet; the answer is still hidden.
  pending,

  /// Checked, with [ListeningSessionController.lastScore] holding the result.
  checked,

  /// The user asked for the answer without passing.
  revealed,
}

/// The outcome recorded for one item at the moment the session moved past it.
class ListeningResult {
  final ListeningItem item;
  final ListeningOutcome? outcome;

  /// True when the user revealed the answer instead of passing it.
  final bool revealed;

  const ListeningResult({
    required this.item,
    required this.outcome,
    required this.revealed,
  });

  bool get isPass => outcome == ListeningOutcome.pass && !revealed;
}

/// Drives one listening session: which item is current, whether its text is
/// visible, and the score of the latest attempt.
///
/// Knows nothing about audio. The screen owns the `StoryAudioController` and
/// asks it to play `currentItem.sentenceIndex`, so there is exactly one TTS
/// path in the app.
class ListeningSessionController extends ChangeNotifier {
  final List<ListeningItem> items;
  final ScoringMetric metric;

  ListeningSessionController({required this.items, required this.metric});

  int _index = 0;
  ListeningItemStatus _status = ListeningItemStatus.pending;
  ListeningScore? _lastScore;
  bool _complete = false;
  final List<ListeningResult> _results = [];

  int get index => _index;
  ListeningItemStatus get status => _status;
  ListeningScore? get lastScore => _lastScore;

  /// True once the last item has been left behind; the screen shows the
  /// summary.
  bool get isComplete => _complete;

  List<ListeningResult> get results => List.unmodifiable(_results);

  bool get isEmpty => items.isEmpty;
  int get total => items.length;

  /// 1-based position for the `n/m` counter.
  int get position => _index + 1;

  ListeningItem? get currentItem =>
      items.isEmpty || _complete ? null : items[_index];

  /// True while the reference text must stay hidden: before the first check of
  /// this item, and again after a retry.
  bool get isAnswerHidden => _status == ListeningItemStatus.pending;

  int get passCount => _results.where((r) => r.isPass).length;

  /// Scores [input] against the current item and records the result.
  ///
  /// Called only from the explicit `Check` action, never from `onChanged`, so
  /// an in-progress CJK IME composition is never scored.
  void check(String input) {
    final item = currentItem;
    if (item == null) return;

    _lastScore =
        item.isCloze
            ? ListeningScorer.scoreCloze(item.reference, input, metric)
            : ListeningScorer.scoreDictation(item.reference, input, metric);
    _status = ListeningItemStatus.checked;
    notifyListeners();
  }

  /// Shows the answer without passing the item.
  void reveal() {
    if (currentItem == null) return;
    _status = ListeningItemStatus.revealed;
    notifyListeners();
  }

  /// Clears the last attempt so the item can be heard and typed again.
  ///
  /// Re-hides the text: a retry the user can read is not a listening exercise.
  void retry() {
    if (currentItem == null) return;
    _lastScore = null;
    _status = ListeningItemStatus.pending;
    notifyListeners();
  }

  /// Records the current item and advances, completing the session after the
  /// last one.
  void next() {
    final item = currentItem;
    if (item == null) return;

    _results.add(
      ListeningResult(
        item: item,
        outcome: _lastScore?.outcome,
        revealed: _status == ListeningItemStatus.revealed,
      ),
    );

    _lastScore = null;
    _status = ListeningItemStatus.pending;

    if (_index + 1 >= items.length) {
      _complete = true;
    } else {
      _index++;
    }
    notifyListeners();
  }

  /// Starts the whole set over. Results are in-session only, so nothing is
  /// persisted or lost.
  void restart() {
    _index = 0;
    _status = ListeningItemStatus.pending;
    _lastScore = null;
    _complete = false;
    _results.clear();
    notifyListeners();
  }
}
