import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:provider/provider.dart';
import 'package:new_words/entities/word_explanation.dart';
import 'package:new_words/features/add_word/widgets/add_word_fab.dart';
import 'package:new_words/providers/vocabulary_provider.dart';
import 'package:new_words/generated/app_localizations.dart';
import 'package:new_words/services/tts_service.dart';
import 'package:new_words/features/word_detail/widgets/tts_markdown_builder.dart';
import 'package:new_words/dependency_injection.dart';

class WordDetailScreen extends StatefulWidget {
  final WordExplanation wordExplanation;

  const WordDetailScreen({super.key, required this.wordExplanation});

  static const routeName = '/word-detail';

  @override
  State<WordDetailScreen> createState() => _WordDetailScreenState();
}

class _WordDetailScreenState extends State<WordDetailScreen> {
  late WordExplanation _currentExplanation;
  final TtsService _ttsService = locator<TtsService>();

  // New state for multiple explanations
  List<WordExplanation> _allExplanations = [];
  int _selectedIndex = 0;
  bool _allModelsExhausted = false;
  int? _userDefaultExplanationId;

  @override
  void initState() {
    super.initState();
    _currentExplanation = widget.wordExplanation;
    _userDefaultExplanationId = widget.wordExplanation.id;

    // Initialize with current explanation - show immediately without blocking
    _allExplanations = [_currentExplanation];
    _selectedIndex = 0;

    // Load other explanations asynchronously in background
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadExplanationsInBackground();
    });
  }

  Future<void> _loadExplanationsInBackground() async {
    // Check if wordCollectionId is valid (0 means old data before migration)
    if (_currentExplanation.wordCollectionId <= 0) {
      return;
    }

    try {
      final provider = Provider.of<VocabularyProvider>(context, listen: false);
      final response = await provider.loadExplanationsForWord(_currentExplanation);

      if (!mounted) return;

      setState(() {
        _allExplanations = response.explanations;
        _userDefaultExplanationId = response.userDefaultExplanationId;

        // Always show user's default explanation when entering detail screen
        _selectedIndex = _allExplanations.indexWhere(
          (e) => e.id == _userDefaultExplanationId,
        );
        if (_selectedIndex == -1) _selectedIndex = 0;

        // Update to show default explanation
        if (_allExplanations.isNotEmpty) {
          _currentExplanation = _allExplanations[_selectedIndex];
        }
      });
    } catch (e) {
      // Graceful degradation: keep showing current explanation
      // No need to update UI - user can already see the content
    }
  }

  void _previousExplanation() {
    setState(() {
      // Circular navigation: go to last if at first
      _selectedIndex = _selectedIndex > 0
          ? _selectedIndex - 1
          : _allExplanations.length - 1;
      _currentExplanation = _allExplanations[_selectedIndex];
    });
  }

  void _nextExplanation() {
    setState(() {
      // Circular navigation: go to first if at last
      _selectedIndex = _selectedIndex < _allExplanations.length - 1
          ? _selectedIndex + 1
          : 0;
      _currentExplanation = _allExplanations[_selectedIndex];
    });
  }

  Future<void> _setAsPreferred() async {
    try {
      final provider = Provider.of<VocabularyProvider>(context, listen: false);
      await provider.switchExplanation(
        _currentExplanation.wordCollectionId,
        _currentExplanation.id,
      );

      if (!mounted) return;

      setState(() {
        _userDefaultExplanationId = _currentExplanation.id;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context)!.defaultExplanationUpdated),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${AppLocalizations.of(context)!.failedToUpdateDefault}: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  bool get _canRefresh {
    // Only disable refresh when backend says all models are exhausted
    return !_allModelsExhausted;
  }

  Future<void> _refreshExplanation() async {
    final provider = Provider.of<VocabularyProvider>(context, listen: false);

    final result = await provider.refreshExplanation(_currentExplanation);

    if (!mounted) return;

    if (result.isSuccess) {
      if (result.wasUpdated && result.updatedExplanation != null) {
        final newExplanation = result.updatedExplanation!;

        // Reset exhausted flag - successful refresh means there was an available model
        setState(() {
          _allModelsExhausted = false;
        });

        // Reload all explanations to include the new one
        await _loadExplanationsInBackground();

        // Switch to the newly generated explanation
        final newIndex = _allExplanations.indexWhere((e) => e.id == newExplanation.id);
        if (newIndex != -1) {
          setState(() {
            _selectedIndex = newIndex;
            _currentExplanation = _allExplanations[newIndex];
          });
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context)!.newExplanationGenerated),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result.message),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } else {
      // Check for models exhausted error
      if (result.message.contains('All available models')) {
        setState(() => _allModelsExhausted = true);
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.message),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }

  Future<void> _generateNow() async {
    final provider = Provider.of<VocabularyProvider>(context, listen: false);

    final filled = await provider.generateExplanation(_currentExplanation);

    if (!mounted) return;

    // Backend returns a still-pending row on failure; only treat a Ready
    // result as success. Keep the pending view and action available otherwise.
    if (filled != null && !filled.isPending) {
      setState(() {
        _currentExplanation = filled;
      });
      await _loadExplanationsInBackground();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context)!.generateExplanationFailed),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }

  Widget _buildPendingView(BuildContext context, bool isGenerating) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.hourglass_empty, color: Colors.grey.shade600),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                AppLocalizations.of(context)!.pendingExplanationTitle,
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey.shade700,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (isGenerating)
          Row(
            children: [
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 12),
              Text(AppLocalizations.of(context)!.generatingExplanation),
            ],
          )
        else
          ElevatedButton.icon(
            onPressed: _generateNow,
            icon: const Icon(Icons.auto_awesome),
            label: Text(AppLocalizations.of(context)!.generateNowButton),
          ),
      ],
    );
  }

  Future<void> _speakWord() async {
    if (!_ttsService.isSupported) return;
    await _ttsService.speak(
      _currentExplanation.wordText,
      language: _currentExplanation.learningLanguage,
    );
  }

  Future<void> _speakSentence(String sentence) async {
    if (!_ttsService.isSupported) return;
    await _ttsService.speak(
      sentence,
      language: _currentExplanation.learningLanguage,
    );
  }

  @override
  void dispose() {
    _ttsService.stop();
    super.dispose();
  }

  Widget _buildVersionNavigator() {
    if (_allExplanations.length <= 1) return const SizedBox.shrink();

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: const Icon(Icons.chevron_left),
          onPressed: _previousExplanation,
        ),
        Text(
          '${_selectedIndex + 1}/${_allExplanations.length}',
          style: const TextStyle(fontSize: 14),
        ),
        IconButton(
          icon: const Icon(Icons.chevron_right),
          onPressed: _nextExplanation,
        ),
      ],
    );
  }

  Widget _buildDefaultIndicator() {
    final isDefault = _currentExplanation.id == _userDefaultExplanationId;

    if (isDefault) {
      return Row(
        children: [
          const Icon(Icons.star, color: Colors.amber, size: 16),
          const SizedBox(width: 4),
          Text(
            AppLocalizations.of(context)!.preferred,
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ],
      );
    } else {
      return TextButton.icon(
        onPressed: _setAsPreferred,
        icon: const Icon(Icons.star_border, size: 16),
        label: Text(AppLocalizations.of(context)!.setAsPreferred),
        style: TextButton.styleFrom(
          padding: EdgeInsets.zero,
          minimumSize: const Size(0, 0),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<VocabularyProvider>(
      builder: (context, provider, child) {
        return Scaffold(
          resizeToAvoidBottomInset: true,
          appBar: AppBar(
            title: Row(
              children: [
                Flexible(
                  child: Text(
                    _currentExplanation.wordText,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (_ttsService.isSupported)
                  IconButton(
                    icon: const Icon(Icons.volume_up),
                    onPressed: _speakWord,
                    tooltip: AppLocalizations.of(context)!.pronounceWord,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
              ],
            ),
            actions: [
              _buildVersionNavigator(),
              // Refresh button — hidden while pending, where "Generate now" is
              // the only sensible action (shuffle would fork a new explanation
              // off a placeholder).
              if (_currentExplanation.isPending)
                const SizedBox.shrink()
              else if (provider.isRefreshing)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12),
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              else
                IconButton(
                  icon: const Icon(Icons.shuffle),
                  onPressed: _canRefresh ? _refreshExplanation : null,
                  tooltip: AppLocalizations.of(context)!.refreshButton,
                ),
              const SizedBox(width: 8),
            ],
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                // Default indicator
                if (_allExplanations.length > 1) ...[
                  _buildDefaultIndicator(),
                  const SizedBox(height: 8),
                ],
                const Divider(),
                if (_currentExplanation.isPending) ...[
                  _buildPendingView(context, provider.isGenerating),
                ] else ...[
                  if (_ttsService.isSupported)
                    TtsMarkdownWidget(
                      explanation: _currentExplanation,
                      onSpeak: _speakSentence,
                    )
                  else
                    MarkdownBody(
                      data: _currentExplanation.markdownExplanation,
                      selectable: true,
                    ),
                  const Divider(),
                  Text(
                    '${AppLocalizations.of(context)!.generatedByPrefix} ${_currentExplanation.providerModelName ?? AppLocalizations.of(context)!.unknownModel}',
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ],
            ),
          ),
          floatingActionButton: const AddWordFab(replacePage: true),
          floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
        );
      },
    );
  }
}
