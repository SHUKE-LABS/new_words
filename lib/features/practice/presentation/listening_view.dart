import 'package:flutter/material.dart';
import 'package:new_words/entities/story.dart';
import 'package:new_words/features/practice/controllers/listening_session_controller.dart';
import 'package:new_words/features/practice/models/listening_item.dart';
import 'package:new_words/features/practice/utils/listening_scorer.dart';
import 'package:new_words/features/stories/controllers/story_audio_controller.dart';
import 'package:new_words/generated/app_localizations.dart';

/// Listening practice over one story: hear a sentence, type what you heard.
///
/// Audio is entirely [StoryAudioController]'s — this view only asks it to play
/// the current item's sentence index, so rapid Replay inherits the controller's
/// generation guard and never overlaps.
///
/// The controller and the exercise set are the host screen's, built once per
/// story and shared with the other practice modes: switching modes therefore
/// re-segments nothing, and this view stops the controller but never disposes
/// it.
class ListeningView extends StatefulWidget {
  final Story story;

  /// The host's playback controller, over the same segmentation [items] index
  /// into.
  final StoryAudioController audio;

  /// The host's exercise set, built once for the story.
  final List<ListeningItem> items;

  /// Whether this mode is the visible one as the view is built.
  ///
  /// The view stays mounted behind Read and Speak, so it must not start the
  /// first item there: the host's probe can settle long after the user has
  /// moved on. The host also calls [ListeningViewState.releasePlayback] on the
  /// way out, because the lazy stack does not rebuild a child that stops being
  /// visible — this flag alone would stay stale at `true`.
  final bool isActive;

  const ListeningView({
    super.key,
    required this.story,
    required this.audio,
    required this.items,
    this.isActive = true,
  });

  @override
  State<ListeningView> createState() => ListeningViewState();
}

/// Public so the host can tell this mode it is no longer the visible one.
class ListeningViewState extends State<ListeningView> {
  late final ListeningSessionController _session;
  final TextEditingController _input = TextEditingController();

  /// Sentence indices already played, so the button reads Play the first time
  /// and Replay afterwards.
  final Set<int> _played = {};

  /// Set once the first item has been played, so returning to this mode does
  /// not start over.
  bool _autoPlayed = false;

  /// Whether this mode is the visible one. Driven from both directions: the
  /// host calls [releasePlayback] when it stops being visible, and the widget's
  /// own `isActive` covers a host that rebuilds this child.
  late bool _active;

  StoryAudioController get _audio => widget.audio;

  @override
  void initState() {
    super.initState();

    _active = widget.isActive;
    _session = ListeningSessionController(
      items: widget.items,
      metric: ListeningScorer.metricForLanguage(widget.story.learningLanguage),
    );

    // The host prepares the controller; this view may well be mounted before
    // that probe has settled, so it waits for it rather than probing again.
    _audio.addListener(_autoPlayWhenReady);
    WidgetsBinding.instance.addPostFrameCallback((_) => _autoPlayWhenReady());
  }

  @override
  void didUpdateWidget(ListeningView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.isActive) {
      _active = false;
      return;
    }
    // Becoming the visible mode again is the other moment the first item can
    // start: the probe may have settled while another mode was showing, and
    // that settlement was deliberately ignored then.
    if (!_active) {
      _active = true;
      // After the frame: this runs during the host's build, and starting
      // playback notifies the controller's listeners.
      WidgetsBinding.instance.addPostFrameCallback((_) => _autoPlayWhenReady());
    }
  }

  /// Tells this mode it is no longer the visible one, so a probe settling
  /// later starts nothing. Playback already in flight is the host's to stop.
  void releasePlayback() => _active = false;

  @override
  void dispose() {
    // The controller belongs to the host and is shared with the other modes:
    // stop it, never dispose it.
    _audio.removeListener(_autoPlayWhenReady);
    _audio.stop();
    _session.dispose();
    _input.dispose();
    super.dispose();
  }

  /// Plays the first item as soon as the host's probe has settled, once — and
  /// only while this mode is the visible one.
  ///
  /// The probe is the host's and can settle at any time, including after the
  /// user has switched to Read or Speak. Speaking then would talk over the
  /// mode they are actually looking at, so a settlement arriving off-mode is
  /// ignored and reconsidered when Listen comes back.
  void _autoPlayWhenReady() {
    if (_autoPlayed || !mounted || !_active || !_audio.isPrepared) return;
    _autoPlayed = true;
    if (_canPractise) _playCurrent();
  }

  /// True when audio works, a voice exists for the story language, and the set
  /// is non-empty.
  bool get _canPractise =>
      _audio.isAvailable && !_audio.languageMissing && !_session.isEmpty;

  /// Why practice cannot run, or null when it can.
  ///
  /// A missing voice for the story's language disables the mode here, unlike
  /// story read-aloud where it is only a warning: dictating against the wrong
  /// voice is not an exercise.
  String? _blockedMessage(AppLocalizations l10n) {
    if (!_audio.isAvailable) {
      switch (_audio.unavailableReason) {
        case StoryAudioUnavailableReason.noVoices:
          return l10n.listeningUnavailableNoVoices;
        case StoryAudioUnavailableReason.emptyStory:
          return l10n.listeningEmptySet;
        case StoryAudioUnavailableReason.platformUnsupported:
        case null:
          return l10n.listeningUnavailableUnsupported;
      }
    }
    if (_audio.languageMissing) {
      return l10n.listeningUnavailableLanguageMissing;
    }
    if (_session.isEmpty) return l10n.listeningEmptySet;
    return null;
  }

  void _playCurrent() {
    final item = _session.currentItem;
    if (item == null) return;
    _played.add(item.sentenceIndex);
    _audio.playSentence(item.sentenceIndex);
  }

  void _check() {
    _session.check(_input.text);
  }

  void _retry() {
    _input.clear();
    _audio.stop();
    _session.retry();
  }

  void _next() {
    _input.clear();
    _session.next();
    // No stop() first: _playCurrent supersedes the previous utterance through
    // the controller's generation guard, and TtsService.speakAndWait stops the
    // engine itself. A stop() here would still be in flight when the new
    // utterance starts and could cancel it.
    if (_session.isComplete) {
      _audio.stop();
    } else {
      _playCurrent();
    }
  }

  void _restart() {
    _input.clear();
    _played.clear();
    _session.restart();
    _playCurrent();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return ListenableBuilder(
      listenable: Listenable.merge([_audio, _session]),
      builder: (context, _) {
        if (!_audio.isPrepared) {
          return const Center(child: CircularProgressIndicator());
        }

        final blocked = _blockedMessage(l10n);
        if (blocked != null) return _buildBlocked(theme, blocked);
        if (_session.isComplete) return _buildSummary(theme, l10n);
        return _buildExercise(theme, l10n);
      },
    );
  }

  Widget _buildBlocked(ThemeData theme, String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.hearing_disabled,
              size: 48,
              color: theme.colorScheme.outline,
            ),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExercise(ThemeData theme, AppLocalizations l10n) {
    final item = _session.currentItem!;
    final hidden = _session.isAnswerHidden;
    final score = _session.lastScore;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '${_session.position} / ${_session.total}',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              _buildSpeedMenu(l10n),
            ],
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(value: _session.position / _session.total),
          const SizedBox(height: 24),
          Text(
            item.isCloze
                ? l10n.listeningClozePrompt
                : l10n.listeningDictationPrompt,
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: 12),
          _buildSentencePanel(theme, item, hidden),
          const SizedBox(height: 16),
          _buildPlayRow(theme, l10n, item),
          const SizedBox(height: 16),
          TextField(
            controller: _input,
            enabled: hidden,
            maxLines: item.isCloze ? 1 : 3,
            minLines: 1,
            textInputAction: TextInputAction.done,
            // Scoring happens only here and on the Check button, never in
            // onChanged: an in-flight CJK IME composition must not be scored.
            onSubmitted: hidden ? (_) => _check() : null,
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              hintText: l10n.listeningInputHint,
            ),
          ),
          const SizedBox(height: 16),
          _buildActionRow(l10n, hidden),
          if (score != null || !hidden) ...[
            const SizedBox(height: 24),
            _buildResultPanel(theme, l10n, item, score),
          ],
        ],
      ),
    );
  }

  /// The sentence under practice: hidden, blanked, or fully shown.
  Widget _buildSentencePanel(ThemeData theme, ListeningItem item, bool hidden) {
    final boxed = BoxDecoration(
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
      borderRadius: BorderRadius.circular(12),
    );
    final body = theme.textTheme.bodyLarge?.copyWith(height: 1.6, fontSize: 16);

    Widget content;
    if (item.isCloze) {
      // Cloze always shows its sentence; only the marked span is withheld.
      content = Text.rich(
        TextSpan(
          style: body,
          children: [
            TextSpan(text: item.promptBefore),
            TextSpan(
              text: hidden ? '_____' : item.reference,
              style: body?.copyWith(
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.primary,
              ),
            ),
            TextSpan(text: item.promptAfter),
          ],
        ),
      );
    } else if (hidden) {
      content = Row(
        children: [
          Icon(Icons.hearing, color: theme.colorScheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              '• • • • •',
              style: body?.copyWith(color: theme.colorScheme.outline),
            ),
          ),
        ],
      );
    } else {
      content = Text(item.sentence, style: body);
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: boxed,
      child: content,
    );
  }

  Widget _buildPlayRow(
    ThemeData theme,
    AppLocalizations l10n,
    ListeningItem item,
  ) {
    final replay = _played.contains(item.sentenceIndex);
    final label = replay ? l10n.listeningReplay : l10n.listeningPlay;

    return Row(
      children: [
        Semantics(
          button: true,
          label: label,
          child: FilledButton.tonalIcon(
            onPressed: _playCurrent,
            icon: Icon(replay ? Icons.replay : Icons.play_arrow),
            // The Semantics above supplies the label for this button's node;
            // excluding the Text's own keeps it from being announced twice.
            label: ExcludeSemantics(child: Text(label)),
          ),
        ),
        const SizedBox(width: 16),
        if (_audio.isPlaying)
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: theme.colorScheme.primary,
            ),
          ),
      ],
    );
  }

  Widget _buildSpeedMenu(AppLocalizations l10n) {
    return PopupMenuButton<double>(
      tooltip: l10n.storyPlaybackSpeed,
      initialValue: _audio.rate,
      onSelected: _audio.setRate,
      itemBuilder:
          (context) =>
              StoryAudioController.rateOptions
                  .map(
                    (rate) => PopupMenuItem<double>(
                      value: rate,
                      child: Text(_formatRate(rate)),
                    ),
                  )
                  .toList(),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            const Icon(Icons.speed, size: 20),
            const SizedBox(width: 4),
            Text(_formatRate(_audio.rate)),
          ],
        ),
      ),
    );
  }

  static String _formatRate(double rate) =>
      '${rate.toStringAsFixed(rate == rate.roundToDouble() ? 1 : 2)}x';

  Widget _buildActionRow(AppLocalizations l10n, bool hidden) {
    return Wrap(
      spacing: 12,
      runSpacing: 8,
      children: [
        Semantics(
          button: true,
          label: l10n.listeningCheck,
          child: FilledButton(
            onPressed: hidden ? _check : null,
            child: ExcludeSemantics(child: Text(l10n.listeningCheck)),
          ),
        ),
        TextButton(
          onPressed: hidden ? _session.reveal : null,
          child: Text(l10n.listeningShowAnswer),
        ),
      ],
    );
  }

  Widget _buildResultPanel(
    ThemeData theme,
    AppLocalizations l10n,
    ListeningItem item,
    ListeningScore? score,
  ) {
    final revealed = _session.status == ListeningItemStatus.revealed;
    final isLast = _session.position >= _session.total;

    final (String headline, Color color) = switch (score?.outcome) {
      ListeningOutcome.pass => (l10n.listeningOutcomePass, Colors.green),
      ListeningOutcome.nearMiss => (
        l10n.listeningOutcomeNearMiss,
        Colors.orange,
      ),
      ListeningOutcome.fail => (
        l10n.listeningOutcomeFail,
        theme.colorScheme.error,
      ),
      null => (l10n.listeningAnswerShown, theme.colorScheme.outline),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              score?.isPass == true ? Icons.check_circle : Icons.info_outline,
              color: color,
              size: 20,
            ),
            const SizedBox(width: 8),
            Text(
              headline,
              style: theme.textTheme.titleSmall?.copyWith(color: color),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(l10n.listeningReferenceLabel, style: theme.textTheme.labelLarge),
        const SizedBox(height: 4),
        Text(
          item.isCloze ? item.reference : item.sentence,
          style: theme.textTheme.bodyLarge,
        ),
        if (score != null && !revealed) ...[
          const SizedBox(height: 12),
          Text(l10n.listeningDiffLabel, style: theme.textTheme.labelLarge),
          const SizedBox(height: 4),
          _buildDiff(theme, score.diff),
          const SizedBox(height: 8),
          _buildDiffLegend(theme, l10n),
        ],
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: _retry,
              icon: const Icon(Icons.refresh),
              label: Text(l10n.listeningRetry),
            ),
            FilledButton.icon(
              onPressed: _next,
              icon: const Icon(Icons.arrow_forward),
              label: Text(isLast ? l10n.listeningFinish : l10n.listeningNext),
            ),
          ],
        ),
      ],
    );
  }

  /// Renders the diff: agreeing runs plain, missing runs underlined, invented
  /// runs struck through.
  Widget _buildDiff(ThemeData theme, List<DiffSegment> diff) {
    final separator = _session.metric == ScoringMetric.character ? '' : ' ';
    final base = theme.textTheme.bodyLarge;

    return Text.rich(
      TextSpan(
        children: [
          for (final (i, segment) in diff.indexed) ...[
            if (i > 0 && separator.isNotEmpty) TextSpan(text: separator),
            TextSpan(
              text: segment.text,
              style: switch (segment.kind) {
                DiffKind.same => base,
                DiffKind.missing => base?.copyWith(
                  color: theme.colorScheme.error,
                  decoration: TextDecoration.underline,
                  decorationColor: theme.colorScheme.error,
                ),
                DiffKind.extra => base?.copyWith(
                  color: theme.colorScheme.outline,
                  decoration: TextDecoration.lineThrough,
                ),
              },
            ),
          ],
        ],
      ),
    );
  }

  /// Legend for the diff, each label carrying the decoration it explains.
  Widget _buildDiffLegend(ThemeData theme, AppLocalizations l10n) {
    final small = theme.textTheme.bodySmall;
    return Wrap(
      spacing: 16,
      children: [
        Text(
          l10n.listeningDiffMissing,
          style: small?.copyWith(
            color: theme.colorScheme.error,
            decoration: TextDecoration.underline,
            decorationColor: theme.colorScheme.error,
          ),
        ),
        Text(
          l10n.listeningDiffExtra,
          style: small?.copyWith(
            color: theme.colorScheme.outline,
            decoration: TextDecoration.lineThrough,
          ),
        ),
      ],
    );
  }

  Widget _buildSummary(ThemeData theme, AppLocalizations l10n) {
    final results = _session.results;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.listeningSummaryTitle,
            style: theme.textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          Text(
            '${l10n.listeningSummaryScoreLabel}: '
            '${_session.passCount} / ${results.length}',
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 24),
          for (final result in results) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  result.isPass ? Icons.check_circle : Icons.cancel_outlined,
                  size: 18,
                  color:
                      result.isPass ? Colors.green : theme.colorScheme.outline,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    result.item.isCloze
                        ? result.item.reference
                        : result.item.sentence,
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: _restart,
                icon: const Icon(Icons.refresh),
                label: Text(l10n.listeningRestart),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
