import 'package:flutter/material.dart';
import 'package:new_words/dependency_injection.dart';
import 'package:new_words/entities/story.dart';
import 'package:new_words/features/practice/controllers/speaking_session_controller.dart';
import 'package:new_words/features/practice/models/listening_item.dart';
import 'package:new_words/features/practice/utils/listening_scorer.dart';
import 'package:new_words/features/practice/utils/listening_set_builder.dart';
import 'package:new_words/features/stories/controllers/story_audio_controller.dart';
import 'package:new_words/generated/app_localizations.dart';
import 'package:new_words/services/mic_permission_service.dart';
import 'package:new_words/services/stt_service.dart';
import 'package:new_words/services/tts_service.dart';
import 'package:new_words/utils/platform_info.dart';

/// Why speaking practice cannot run at all here.
enum _Blocker { platform, recognizer, noVoice, locale, emptySet }

/// Speaking practice over one story: hear a sentence, say it back, see how many
/// of its words came through.
///
/// Audio is [StoryAudioController]'s and scoring is [ListeningScorer]'s — this
/// screen owns neither. What it does own is the mutual exclusion between
/// speaking and listening: the reference is never played while the microphone
/// is open, and the microphone is never left open when the screen goes away.
class SpeakingScreen extends StatefulWidget {
  final Story story;

  /// Injection seams for tests; production resolves the shared singletons.
  final TtsService? ttsService;
  final SttService? sttService;
  final MicPermissionService? permissions;

  /// Which platform to behave as. Production reads the real one.
  final PlatformInfo platform;

  const SpeakingScreen({
    super.key,
    required this.story,
    this.ttsService,
    this.sttService,
    this.permissions,
    this.platform = PlatformInfo.current,
  });

  @override
  State<SpeakingScreen> createState() => _SpeakingScreenState();
}

class _SpeakingScreenState extends State<SpeakingScreen>
    with WidgetsBindingObserver
    implements SttListener {
  /// Null on an unsupported platform: the controller is never constructed
  /// there, so nothing reaches the TTS channel.
  StoryAudioController? _audio;
  SpeakingSessionController? _session;

  SttService? _stt;
  MicPermissionService? _permissions;

  /// Sentence indices already played, so the button reads Play the first time
  /// and Replay afterwards.
  final Set<int> _played = {};

  bool _prepared = false;
  _Blocker? _blocker;

  /// Whether this state registered itself as a lifecycle observer, which only
  /// the supported path does.
  bool _observing = false;

  /// Set while microphone access is still missing; null once practice may run.
  MicPermission? _micBlocked;
  bool _requesting = false;

  /// The recognizer locale for the story language, resolved once ready.
  String? _localeId;

  /// The transient explanation under the controls: no speech, busy, no mic.
  String? _message;

  /// Set across a start attempt. Record stays on screen until the session turns
  /// recording, which is a frame away, so a second tap is otherwise reachable.
  bool _starting = false;

  @override
  void initState() {
    super.initState();

    // The support decision comes first and touches nothing: on an unsupported
    // platform neither the audio controller nor either service is constructed,
    // so no plugin call is made at all.
    if (classifySpeechPlatform(widget.platform) == SpeechPlatform.unsupported) {
      _blocker = _Blocker.platform;
      _prepared = true;
      return;
    }

    WidgetsBinding.instance.addObserver(this);
    _observing = true;

    _stt = widget.sttService ?? locator<SttService>();
    _permissions = widget.permissions ?? locator<MicPermissionService>();
    _stt!.attach(this);

    _audio = StoryAudioController.forContent(
      ttsService: widget.ttsService ?? locator<TtsService>(),
      languageCode: widget.story.learningLanguage,
      content: widget.story.content,
    );
    // Same segmentation instance the audio controller plays from, so every
    // item's sentenceIndex addresses the sentence that will be spoken.
    _session = SpeakingSessionController(
      items: ListeningSetBuilder.build(
        languageCode: widget.story.learningLanguage,
        sentences: _audio!.sentences,
      ),
      metric: ListeningScorer.metricForLanguage(widget.story.learningLanguage),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) => _prepare());
  }

  @override
  void dispose() {
    // Detaching cancels recognition for the active listener, so the microphone
    // is released on pop and on unmount alike.
    _stt?.detach(this);
    if (_observing) {
      WidgetsBinding.instance.removeObserver(this);
    }
    _audio?.dispose();
    _session?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      // Never hold the microphone in the background, and never keep speaking
      // into it either: a reference utterance outliving the foreground is the
      // same lifecycle leak as an open recognizer.
      _stt?.cancel();
      _audio?.stop();
      _session?.abandonRecording();
    }
  }

  Future<void> _prepare() async {
    final audio = _audio!;
    await audio.prepare();
    if (!mounted) return;

    final blocker = _audioBlocker(audio);
    if (blocker != null) {
      setState(() {
        _blocker = blocker;
        _prepared = true;
      });
      return;
    }

    final status = await _permissions!.status();
    if (!mounted) return;

    if (status == MicPermission.granted) {
      // Already granted: request() prompts nothing here and gives the
      // recognizer its chance to initialize, which is what resolving a locale
      // needs.
      await _applyOutcome(await _permissions!.request());
    } else {
      setState(() => _micBlocked = status);
    }
    if (!mounted) return;
    setState(() => _prepared = true);
  }

  /// The blocker coming from playback rather than recognition, or null.
  _Blocker? _audioBlocker(StoryAudioController audio) {
    if (_session!.isEmpty) return _Blocker.emptySet;
    if (!audio.isAvailable) {
      return audio.unavailableReason == StoryAudioUnavailableReason.emptyStory
          ? _Blocker.emptySet
          : _Blocker.noVoice;
    }
    // A voice for the story's language is required, not advisory: there is
    // nothing to say back if the reference is spoken in the wrong language.
    if (audio.languageMissing) return _Blocker.noVoice;
    return null;
  }

  /// Asks for microphone access behind a rationale, then applies the outcome.
  Future<void> _requestPermission() async {
    final l10n = AppLocalizations.of(context)!;
    final accepted = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Text(l10n.speakingPermissionTitle),
            content: Text(l10n.speakingPermissionRationale),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text(l10n.speakingPermissionCancel),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: Text(l10n.speakingPermissionAllow),
              ),
            ],
          ),
    );
    if (accepted != true || !mounted) return;

    setState(() => _requesting = true);
    final outcome = await _permissions!.request();
    if (!mounted) return;
    setState(() => _requesting = false);
    await _applyOutcome(outcome);
  }

  /// Maps a request outcome onto the screen's state, resolving the recognizer
  /// locale once access is in hand.
  Future<void> _applyOutcome(MicRequestOutcome outcome) async {
    switch (outcome) {
      case MicRequestOutcome.granted:
        if (!mounted) return;
        setState(() => _micBlocked = null);
        await _resolveLocale();
        return;
      case MicRequestOutcome.denied:
        if (!mounted) return;
        setState(() => _micBlocked = MicPermission.denied);
        return;
      case MicRequestOutcome.permanentlyDenied:
        if (!mounted) return;
        setState(() => _micBlocked = MicPermission.permanentlyDenied);
        return;
      case MicRequestOutcome.recognizerUnavailable:
        if (!mounted) return;
        setState(() => _blocker = _Blocker.recognizer);
        return;
      case MicRequestOutcome.unsupported:
        if (!mounted) return;
        setState(() => _blocker = _Blocker.platform);
        return;
    }
  }

  /// Locales are only queryable after a successful initialization, which
  /// [_applyOutcome] has just had, so this runs there and nowhere earlier.
  Future<void> _resolveLocale() async {
    final localeId = await _stt!.resolveLocaleId(widget.story.learningLanguage);
    if (!mounted) return;
    setState(() {
      _localeId = localeId;
      if (localeId == null) _blocker = _Blocker.locale;
    });
  }

  /// Retries an initialization that failed for a reason the user may have
  /// fixed — a recognizer that was unavailable, most often after installing
  /// one. Permitted because [SttService] caches only success.
  Future<void> _retryRecognizer() async {
    setState(() {
      _blocker = null;
      _requesting = true;
    });
    final outcome = await _permissions!.request();
    if (!mounted) return;
    setState(() => _requesting = false);
    await _applyOutcome(outcome);
  }

  /// Plays the reference sentence, closing the recognizer first.
  ///
  /// The session's recording flag is not enough on its own: a final result
  /// scores the attempt while the platform recognizer can still be running
  /// until its own terminal status, and that window is long enough for a tap.
  /// Cancelling here — and awaiting it — is what actually makes playback and
  /// recognition exclusive.
  Future<void> _playCurrent() async {
    final item = _session!.currentItem;
    if (item == null) return;
    await _stt!.cancel();
    if (!mounted) return;
    setState(() => _played.add(item.sentenceIndex));
    _audio!.playSentence(item.sentenceIndex);
  }

  Future<void> _startRecording() async {
    final localeId = _localeId;
    if (localeId == null || _starting) return;
    _starting = true;

    // Playback and recognition never overlap: the reference is stopped and the
    // stop awaited before the microphone opens.
    await _audio!.stop();
    if (!mounted) {
      _starting = false;
      return;
    }

    // Closes any session the previous attempt left open, and awaiting it is
    // what makes the boundary real: the platform channel is ordered, so every
    // event the old session had in flight has already been delivered — and
    // dropped, this attempt not being recording yet — by the time the cancel
    // returns. Without this an error'd attempt's late final result would score
    // the next one.
    await _stt!.cancel();
    if (!mounted) {
      _starting = false;
      return;
    }

    setState(() => _message = null);
    _session!.startRecording();

    final started = await _stt!.listen(localeId: localeId);
    _starting = false;
    if (!mounted || started) return;
    _session!.abandonRecording();
    setState(() => _message = AppLocalizations.of(context)!.speakingErrorOther);
  }

  Future<void> _stopRecording() async {
    // Keeps whatever was recognized; the final result arrives on the callback.
    await _stt!.stop();
  }

  void _retry() {
    _audio!.stop();
    setState(() => _message = null);
    _session!.retry();
  }

  void _next() {
    setState(() => _message = null);
    _audio!.stop();
    _session!.next();
  }

  void _restart() {
    _played.clear();
    setState(() => _message = null);
    _session!.restart();
  }

  // --- SttListener -------------------------------------------------------

  @override
  void onSttResult(String transcript, {required bool isFinal}) {
    if (!mounted) return;
    // A result arriving after the attempt was abandoned — a late transcript
    // behind an error, say — must not contradict the message on screen.
    if (!_session!.isRecording) return;
    if (isFinal) {
      if (transcript.trim().isEmpty) {
        _session!.abandonRecording();
        setState(
          () => _message = AppLocalizations.of(context)!.speakingErrorNoSpeech,
        );
        return;
      }
      _session!.score(transcript);
    } else {
      _session!.updateTranscript(transcript);
    }
  }

  @override
  void onSttDone() {
    if (!mounted) return;
    final session = _session!;
    if (!session.isRecording) return;

    // The platform ended the session without a final result: score whatever
    // partial text arrived, and explain the silence when none did.
    final partial = session.transcript.trim();
    if (partial.isEmpty) {
      session.abandonRecording();
      setState(
        () => _message = AppLocalizations.of(context)!.speakingErrorNoSpeech,
      );
    } else {
      session.score(partial);
    }
  }

  @override
  void onSttError(SttErrorKind kind) {
    if (!mounted) return;
    final l10n = AppLocalizations.of(context)!;
    _session!.abandonRecording();
    setState(() {
      _message = switch (kind) {
        SttErrorKind.noSpeech => l10n.speakingErrorNoSpeech,
        SttErrorKind.busy => l10n.speakingErrorBusy,
        SttErrorKind.noMic => l10n.speakingErrorNoMic,
        SttErrorKind.network => l10n.speakingErrorNetwork,
        SttErrorKind.permission => l10n.speakingPermissionDenied,
        SttErrorKind.languageUnavailable => l10n.speakingErrorLanguage,
        SttErrorKind.other => l10n.speakingErrorOther,
      };
      if (kind == SttErrorKind.permission) {
        _micBlocked = MicPermission.denied;
      }
    });
  }

  // --- Build -------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.speakingTitle)),
      body: _buildBody(theme, l10n),
    );
  }

  Widget _buildBody(ThemeData theme, AppLocalizations l10n) {
    if (_blocker != null) return _buildBlocked(theme, l10n, _blocker!);
    if (!_prepared) return const Center(child: CircularProgressIndicator());

    return ListenableBuilder(
      listenable: Listenable.merge([_audio, _session]),
      builder: (context, _) {
        if (_blocker != null) return _buildBlocked(theme, l10n, _blocker!);
        if (_micBlocked != null) return _buildPermission(theme, l10n);
        if (_session!.isComplete) return _buildSummary(theme, l10n);
        return _buildExercise(theme, l10n);
      },
    );
  }

  Widget _buildBlocked(
    ThemeData theme,
    AppLocalizations l10n,
    _Blocker blocker,
  ) {
    final message = switch (blocker) {
      _Blocker.platform => l10n.speakingUnavailablePlatform,
      _Blocker.recognizer => l10n.speakingUnavailableRecognizer,
      _Blocker.noVoice => l10n.speakingUnavailableNoVoice,
      _Blocker.locale => l10n.speakingUnavailableLocale,
      _Blocker.emptySet => l10n.speakingEmptySet,
    };

    return _buildNotice(
      theme,
      icon: Icons.mic_off,
      message: message,
      // Only a missing recognizer is worth retrying: the user may have
      // installed one, and a failed initialization is never cached.
      action:
          blocker == _Blocker.recognizer
              ? OutlinedButton.icon(
                onPressed: _requesting ? null : _retryRecognizer,
                icon: const Icon(Icons.refresh),
                label: Text(l10n.speakingTryAgain),
              )
              : null,
    );
  }

  Widget _buildPermission(ThemeData theme, AppLocalizations l10n) {
    final permanent = _micBlocked == MicPermission.permanentlyDenied;

    return _buildNotice(
      theme,
      icon: Icons.mic_off,
      message:
          permanent
              ? l10n.speakingPermissionPermanentlyDenied
              : l10n.speakingPermissionDenied,
      action:
          permanent
              ? FilledButton.icon(
                onPressed: () => _permissions!.openSettings(),
                icon: const Icon(Icons.settings),
                label: Text(l10n.speakingOpenSettings),
              )
              : FilledButton.icon(
                onPressed: _requesting ? null : _requestPermission,
                icon: const Icon(Icons.mic),
                label: Text(l10n.speakingPermissionAllow),
              ),
    );
  }

  Widget _buildNotice(
    ThemeData theme, {
    required IconData icon,
    required String message,
    Widget? action,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 48, color: theme.colorScheme.outline),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge,
            ),
            if (action != null) ...[const SizedBox(height: 24), action],
          ],
        ),
      ),
    );
  }

  Widget _buildExercise(ThemeData theme, AppLocalizations l10n) {
    final session = _session!;
    final item = session.currentItem!;
    final score = session.lastScore;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '${session.position} / ${session.total}',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              _buildSpeedMenu(l10n),
            ],
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(value: session.position / session.total),
          const SizedBox(height: 24),
          Text(l10n.speakingPrompt, style: theme.textTheme.titleSmall),
          const SizedBox(height: 12),
          _buildSentencePanel(theme, item),
          const SizedBox(height: 16),
          _buildControls(theme, l10n, item),
          if (_message != null) ...[
            const SizedBox(height: 16),
            Text(
              _message!,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ],
          if (session.transcript.isNotEmpty) ...[
            const SizedBox(height: 24),
            Text(
              l10n.speakingTranscriptLabel,
              style: theme.textTheme.labelLarge,
            ),
            const SizedBox(height: 4),
            Text(session.transcript, style: theme.textTheme.bodyLarge),
          ],
          if (score != null) ...[
            const SizedBox(height: 24),
            _buildResultPanel(theme, l10n, score),
          ],
          const SizedBox(height: 24),
          Text(
            l10n.speakingWordAccuracyNote,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
        ],
      ),
    );
  }

  /// The sentence to say. Always visible: this is shadowing, not dictation.
  Widget _buildSentencePanel(ThemeData theme, ListeningItem item) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        item.sentence,
        style: theme.textTheme.bodyLarge?.copyWith(height: 1.6, fontSize: 16),
      ),
    );
  }

  Widget _buildControls(
    ThemeData theme,
    AppLocalizations l10n,
    ListeningItem item,
  ) {
    final recording = _session!.isRecording;
    final replay = _played.contains(item.sentenceIndex);
    final playLabel = replay ? l10n.speakingReplay : l10n.speakingPlay;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Semantics(
              button: true,
              label: playLabel,
              child: FilledButton.tonalIcon(
                // Playing into an open microphone would record the reference
                // instead of the user.
                onPressed: recording ? null : _playCurrent,
                icon: Icon(replay ? Icons.replay : Icons.play_arrow),
                // The Semantics above supplies this node's label; excluding
                // the Text's own keeps it from being announced twice.
                label: ExcludeSemantics(child: Text(playLabel)),
              ),
            ),
            if (recording)
              Semantics(
                button: true,
                label: l10n.speakingStop,
                child: FilledButton.icon(
                  onPressed: _stopRecording,
                  icon: const Icon(Icons.stop),
                  label: ExcludeSemantics(child: Text(l10n.speakingStop)),
                ),
              )
            else
              Semantics(
                button: true,
                label: l10n.speakingRecord,
                child: FilledButton.icon(
                  onPressed: _audio!.isPlaying ? null : _startRecording,
                  icon: const Icon(Icons.mic),
                  label: ExcludeSemantics(child: Text(l10n.speakingRecord)),
                ),
              ),
            if (_audio!.isPlaying)
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: theme.colorScheme.primary,
                ),
              ),
          ],
        ),
        if (recording) ...[
          const SizedBox(height: 16),
          Row(
            children: [
              _PulsingMic(color: theme.colorScheme.error),
              const SizedBox(width: 12),
              Text(
                l10n.speakingRecording,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildSpeedMenu(AppLocalizations l10n) {
    return PopupMenuButton<double>(
      tooltip: l10n.storyPlaybackSpeed,
      initialValue: _audio!.rate,
      onSelected: _audio!.setRate,
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
            Text(_formatRate(_audio!.rate)),
          ],
        ),
      ),
    );
  }

  static String _formatRate(double rate) =>
      '${rate.toStringAsFixed(rate == rate.roundToDouble() ? 1 : 2)}x';

  Widget _buildResultPanel(
    ThemeData theme,
    AppLocalizations l10n,
    ListeningScore score,
  ) {
    final isLast = _session!.position >= _session!.total;
    final (String headline, Color color) = switch (score.outcome) {
      ListeningOutcome.pass => (l10n.speakingOutcomePass, Colors.green),
      ListeningOutcome.nearMiss => (
        l10n.speakingOutcomeNearMiss,
        Colors.orange,
      ),
      ListeningOutcome.fail => (
        l10n.speakingOutcomeFail,
        theme.colorScheme.error,
      ),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              score.isPass ? Icons.check_circle : Icons.info_outline,
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
        const SizedBox(height: 8),
        Text(
          '${l10n.speakingAccuracyLabel}: ${(score.ratio * 100).round()}%',
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 12),
        Text(l10n.speakingDiffLabel, style: theme.textTheme.labelLarge),
        const SizedBox(height: 4),
        _buildDiff(theme, score.diff),
        const SizedBox(height: 8),
        _buildDiffLegend(theme, l10n),
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          children: [
            Semantics(
              button: true,
              label: l10n.speakingRetry,
              child: OutlinedButton.icon(
                onPressed: _retry,
                icon: const Icon(Icons.refresh),
                label: ExcludeSemantics(child: Text(l10n.speakingRetry)),
              ),
            ),
            FilledButton.icon(
              onPressed: _next,
              icon: const Icon(Icons.arrow_forward),
              label: Text(isLast ? l10n.speakingFinish : l10n.speakingNext),
            ),
          ],
        ),
      ],
    );
  }

  /// Renders the diff: agreeing runs plain, words the sentence had and the
  /// attempt missed underlined, words the attempt added struck through.
  Widget _buildDiff(ThemeData theme, List<DiffSegment> diff) {
    final separator = _session!.metric == ScoringMetric.character ? '' : ' ';
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
          l10n.speakingDiffMissing,
          style: small?.copyWith(
            color: theme.colorScheme.error,
            decoration: TextDecoration.underline,
            decorationColor: theme.colorScheme.error,
          ),
        ),
        Text(
          l10n.speakingDiffExtra,
          style: small?.copyWith(
            color: theme.colorScheme.outline,
            decoration: TextDecoration.lineThrough,
          ),
        ),
      ],
    );
  }

  Widget _buildSummary(ThemeData theme, AppLocalizations l10n) {
    final results = _session!.results;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.speakingSummaryTitle, style: theme.textTheme.headlineSmall),
          const SizedBox(height: 8),
          Text(
            '${l10n.speakingSummaryScoreLabel}: '
            '${_session!.passCount} / ${results.length}',
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
                    result.item.sentence,
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
              OutlinedButton.icon(
                onPressed: _restart,
                icon: const Icon(Icons.refresh),
                label: Text(l10n.speakingRestart),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(l10n.speakingDone),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A microphone that breathes while recording, so an open microphone is
/// visible without reading the label.
class _PulsingMic extends StatefulWidget {
  final Color color;

  const _PulsingMic({required this.color});

  @override
  State<_PulsingMic> createState() => _PulsingMicState();
}

class _PulsingMicState extends State<_PulsingMic>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    duration: const Duration(milliseconds: 900),
    vsync: this,
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween<double>(
        begin: 0.35,
        end: 1.0,
      ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut)),
      child: Icon(Icons.mic, color: widget.color),
    );
  }
}
