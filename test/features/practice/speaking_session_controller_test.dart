import 'package:flutter_test/flutter_test.dart';
import 'package:new_words/features/practice/controllers/speaking_session_controller.dart';
import 'package:new_words/features/practice/models/listening_item.dart';
import 'package:new_words/features/practice/utils/listening_scorer.dart';

void main() {
  ListeningItem itemFor(String sentence, {int index = 0}) => ListeningItem(
    sentenceIndex: index,
    variant: ListeningVariant.dictation,
    reference: sentence,
    sentence: sentence,
  );

  SpeakingSessionController controllerFor(
    List<String> sentences, {
    ScoringMetric metric = ScoringMetric.token,
  }) => SpeakingSessionController(
    items: [for (final (i, s) in sentences.indexed) itemFor(s, index: i)],
    metric: metric,
  );

  group('recording', () {
    test('starts empty and pending', () {
      final controller = controllerFor(['The morning air was cold.']);

      expect(controller.status, SpeakingItemStatus.pending);
      expect(controller.isRecording, isFalse);
      expect(controller.transcript, isEmpty);
      expect(controller.position, 1);
      expect(controller.total, 1);
    });

    test('partial transcripts accumulate without scoring', () {
      final controller = controllerFor(['The morning air was cold.']);
      controller.startRecording();

      controller.updateTranscript('the morning');
      expect(controller.transcript, 'the morning');
      expect(controller.lastScore, isNull);
      expect(controller.isRecording, isTrue);
    });

    test('a partial arriving outside a recording is ignored', () {
      final controller = controllerFor(['The morning air was cold.']);

      controller.updateTranscript('stray callback');

      expect(controller.transcript, isEmpty);
    });

    test('abandoning leaves the item unscored and retryable', () {
      final controller = controllerFor(['The morning air was cold.']);
      controller.startRecording();
      controller.updateTranscript('the');

      controller.abandonRecording();

      expect(controller.status, SpeakingItemStatus.pending);
      expect(controller.transcript, isEmpty);
      expect(controller.lastScore, isNull);
    });

    test('starting again clears the previous attempt', () {
      final controller = controllerFor(['The morning air was cold.']);
      controller.score('something else entirely');
      expect(controller.lastScore, isNotNull);

      controller.startRecording();

      expect(controller.lastScore, isNull);
      expect(controller.transcript, isEmpty);
    });
  });

  group('scoring', () {
    test('an accurate reading passes', () {
      final controller = controllerFor(['The morning air was cold and clean.']);

      controller.score('the morning air was cold and clean');

      expect(controller.lastScore!.outcome, ListeningOutcome.pass);
      expect(controller.status, SpeakingItemStatus.scored);
    });

    test('a dropped article still passes on token overlap', () {
      final controller = controllerFor(['The morning air was cold and clean.']);

      controller.score('morning air was cold and clean');

      expect(controller.lastScore!.outcome, ListeningOutcome.pass);
      expect(
        controller.lastScore!.tokenOverlap,
        greaterThanOrEqualTo(ListeningScorer.passTokenOverlap),
      );
    });

    test('half the sentence is a near miss', () {
      final controller = controllerFor([
        'She walked to the river without speaking at all.',
      ]);

      controller.score('she walked to the river without singing or anything');

      expect(controller.lastScore!.outcome, ListeningOutcome.nearMiss);
    });

    test('an unrelated reading fails', () {
      final controller = controllerFor(['The morning air was cold and clean.']);

      controller.score('completely different words here');

      expect(controller.lastScore!.outcome, ListeningOutcome.fail);
    });

    test('CJK is scored by character', () {
      final controller = controllerFor([
        '今天早上的空气又冷又干净。',
      ], metric: ScoringMetric.character);

      controller.score('今天早上的空气又冷又干净');

      expect(controller.lastScore!.outcome, ListeningOutcome.pass);
      // Character scoring never uses token overlap.
      expect(controller.lastScore!.tokenOverlap, 0.0);
    });

    test('the whole sentence is the reference even for a cloze item', () {
      final controller = SpeakingSessionController(
        items: const [
          ListeningItem(
            sentenceIndex: 0,
            variant: ListeningVariant.cloze,
            reference: 'running',
            sentence: 'He was running through the park at dawn.',
            promptBefore: 'He was ',
            promptAfter: ' through the park at dawn.',
          ),
        ],
        metric: ScoringMetric.token,
      );

      // Saying only the blanked word is not saying the sentence.
      controller.score('running');
      expect(controller.lastScore!.outcome, ListeningOutcome.fail);

      controller.retry();
      controller.score('he was running through the park at dawn');
      expect(controller.lastScore!.outcome, ListeningOutcome.pass);
    });

    test('scoring is refused once the set is complete', () {
      final controller = controllerFor(['The morning air was cold.']);
      controller.next();
      expect(controller.isComplete, isTrue);

      controller.score('anything');

      expect(controller.lastScore, isNull);
    });
  });

  group('progression', () {
    test('retry clears the attempt but keeps the item', () {
      final controller = controllerFor(['One sentence here.', 'Another one.']);
      controller.score('one sentence here');

      controller.retry();

      expect(controller.status, SpeakingItemStatus.pending);
      expect(controller.lastScore, isNull);
      expect(controller.transcript, isEmpty);
      expect(controller.position, 1);
    });

    test('next records the outcome and advances', () {
      final controller = controllerFor([
        'The morning air was cold and clean.',
        'She walked to the river without speaking.',
      ]);
      controller.score('the morning air was cold and clean');

      controller.next();

      expect(controller.position, 2);
      expect(controller.results, hasLength(1));
      expect(controller.results.single.isPass, isTrue);
      expect(controller.passCount, 1);
      expect(controller.status, SpeakingItemStatus.pending);
    });

    test('skipping without an attempt records no outcome', () {
      final controller = controllerFor(['One sentence here.', 'Another one.']);

      controller.next();

      expect(controller.results.single.outcome, isNull);
      expect(controller.results.single.isPass, isFalse);
      expect(controller.passCount, 0);
    });

    test('the last next completes the set', () {
      final controller = controllerFor(['Only sentence here.']);
      controller.score('only sentence here');

      controller.next();

      expect(controller.isComplete, isTrue);
      expect(controller.currentItem, isNull);
      expect(controller.results, hasLength(1));
    });

    test('restart clears results and returns to the first item', () {
      final controller = controllerFor(['One sentence here.', 'Another one.']);
      controller.score('one sentence here');
      controller.next();
      controller.next();
      expect(controller.isComplete, isTrue);

      controller.restart();

      expect(controller.isComplete, isFalse);
      expect(controller.position, 1);
      expect(controller.results, isEmpty);
      expect(controller.passCount, 0);
      expect(controller.status, SpeakingItemStatus.pending);
    });

    test('an empty set is empty and has no current item', () {
      final controller = controllerFor([]);

      expect(controller.isEmpty, isTrue);
      expect(controller.currentItem, isNull);
      controller.startRecording();
      expect(controller.isRecording, isFalse);
    });
  });

  test('every state change notifies listeners', () {
    final controller = controllerFor(['One sentence here.', 'Another one.']);
    var notifications = 0;
    controller.addListener(() => notifications++);

    controller.startRecording();
    controller.updateTranscript('one');
    controller.score('one sentence here');
    controller.retry();
    controller.next();
    controller.restart();

    expect(notifications, 6);
  });
}
