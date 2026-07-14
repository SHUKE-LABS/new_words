import 'package:new_words/app_config.dart';
import 'package:new_words/entities/add_word_request.dart';
import 'package:new_words/entities/word_explanation.dart';
import 'package:new_words/entities/explanations_response.dart';
import 'package:new_words/common/foundation/foundation.dart';
import 'package:new_words/services/vocabulary_service_v2.dart';
import 'package:new_words/user_session.dart'; // To get language preferences
import 'package:new_words/providers/provider_base.dart';

class VocabularyProvider extends AuthAwareProvider {
  final VocabularyServiceV2 _vocabularyService;

  VocabularyProvider(this._vocabularyService);

  List<WordExplanation> _words = [];

  bool _shouldScrollToTop = false;
  bool get shouldScrollToTop => _shouldScrollToTop;

  void resetScrollFlag() {
    _shouldScrollToTop = false;
  }
  List<WordExplanation> get words => _words;

  bool _isLoadingList = false;
  bool get isLoadingList => _isLoadingList;

  bool _isLoadingAdd = false;
  bool get isLoadingAdd => _isLoadingAdd;

  bool _isRefreshing = false;
  bool get isRefreshing => _isRefreshing;

  bool _isGenerating = false;
  bool get isGenerating => _isGenerating;

  String? _listError;
  String? get listError => _listError;

  String? _addError;
  String? get addError => _addError;

  int _currentPage = 1;
  int _totalWords = 0;
  final int _pageSize = AppConfig.pageSize; // Get page size from AppConfig

  bool get canLoadMore => _words.length < _totalWords;

  Future<void> fetchWords({bool loadMore = false}) async {
    if (_isLoadingList) return;
    if (loadMore && !canLoadMore) return;

    _isLoadingList = true;
    _listError = null;
    if (!loadMore) {
      _currentPage = 1;
      _words = [];
    }
    notifyListeners();

    try {
      final pageData = await _vocabularyService.listWords(
        _currentPage,
        _pageSize,
      );
      if (loadMore) {
        _words.addAll(pageData.dataList);
      } else {
        _words = pageData.dataList;
      }
      _totalWords = pageData.totalCount;
      if (pageData.dataList.isNotEmpty) {
        _currentPage++; // Increment current page if data was fetched
      }
    } on ServiceException catch (e) {
      _listError = e.toString();
    } catch (e) {
      _listError = e.toString();
    } finally {
      _isLoadingList = false;
      notifyListeners();
    }
  }



  Future<void> refreshWords() async {
    _currentPage = 1;
    _words = [];
    await fetchWords();
  }

  Future<WordExplanation?> addNewWord(String wordText) async {
    if (_isLoadingAdd) return null;

    _isLoadingAdd = true;
    _addError = null;
    notifyListeners();

    final session = UserSession();
    final learningLanguage = session.currentLearningLanguage;
    final nativeLanguage = session.nativeLanguage;

    if (learningLanguage == null || learningLanguage.isEmpty) {
      _addError = "Learning language not set.";
      _isLoadingAdd = false;
      notifyListeners();
      return null;
    }
    if (nativeLanguage == null || nativeLanguage.isEmpty) {
      _addError = "Native language not set.";
      _isLoadingAdd = false;
      notifyListeners();
      return null;
    }

    final request = AddWordRequest(
      wordText: wordText,
      learningLanguage: learningLanguage,
      explanationLanguage: nativeLanguage,
    );
    try {
      final newWord = await _vocabularyService.addWord(request);

      if (_words.isNotEmpty) {
        // Check if this WordExplanation already exists in the list (by ID)
        final existingIndex = _words.indexWhere(
          (w) => w.id == newWord.id
        );

        if (existingIndex != -1) {
          // WordExplanation exists - remove from old position and re-insert at beginning
          _words.removeAt(existingIndex);
          _words.insert(0, newWord);
          
          // Set flag to trigger scroll to top
          _shouldScrollToTop = true;
        } else {
          // New WordExplanation - add to beginning and increment total
          _words.insert(0, newWord);
          _totalWords++;
        }
      }
      _isLoadingAdd = false;
      notifyListeners();
      if (_words.isEmpty) {
        await fetchWords(loadMore: false);
      }
      return newWord;
    } on ServiceException catch (e) {
      _addError = e.toString();
    } catch (e) {
      _addError = e.toString();
    } finally {
      _isLoadingAdd = false;
      notifyListeners();
    }
    return null;
  }

  Future<bool> deleteWord(int wordId) async {
    try {
      await _vocabularyService.deleteWord(wordId);
      // Remove the word from the list
      _words.removeWhere((word) => word.id == wordId);
      _totalWords--; // Decrement total words
      notifyListeners();
      return true;
    } catch (e) {
      return false;
    }
  }

  // Cache for explanations
  final Map<int, ExplanationsResponse> _explanationsCache = {};

  Future<RefreshResult> refreshExplanation(WordExplanation explanation) async {
    if (_isRefreshing) return RefreshResult.error('Already refreshing');

    _isRefreshing = true;
    notifyListeners();

    try {
      final result = await _vocabularyService.refreshExplanation(explanation);

      if (!result.wasUpdated) {
        // No refresh was needed - use backend message
        _isRefreshing = false;
        notifyListeners();
        return RefreshResult.noUpdate(result.message ?? 'No update needed');
      }

      // Invalidate cache to force reload
      _explanationsCache.remove(explanation.wordCollectionId);

      // Note: We don't update _words list here because:
      // 1. Refresh creates a NEW explanation with a NEW id
      // 2. User's default explanation remains unchanged (still the old id)
      // 3. The detail screen will reload and show all explanations including the new one

      _isRefreshing = false;
      notifyListeners();
      return RefreshResult.success(result.explanation!);
    } on ServiceException catch (e) {
      _isRefreshing = false;
      notifyListeners();
      return RefreshResult.error(e.toString());
    } catch (e) {
      _isRefreshing = false;
      notifyListeners();
      return RefreshResult.error(
        'Failed to refresh explanation: ${e.toString()}',
      );
    }
  }

  Future<ExplanationsResponse> loadExplanationsForWord(
    WordExplanation word,
  ) async {
    // Serve from cache only when it holds no pending explanation. A cached
    // pending entry may have been filled in place by the background worker
    // since, so we refetch to surface the fill without any user action.
    final cached = _explanationsCache[word.wordCollectionId];
    if (cached != null && !cached.explanations.any((e) => e.isPending)) {
      return cached;
    }

    try {
      final response = await _vocabularyService.getExplanationsForWord(
        word.wordCollectionId,
        word.learningLanguage,
        word.explanationLanguage,
      );

      // Overwrite any stale (pending) cached copy so the refetched result is
      // authoritative, not just skipped past.
      _explanationsCache[word.wordCollectionId] = response;
      notifyListeners();

      return response;
    } catch (e) {
      rethrow;
    }
  }

  /// Fill a pending word's explanation on demand ("Generate now").
  ///
  /// Re-POSTs the existing add endpoint using the pending word's own languages;
  /// the backend detects the pending row and runs one synchronous in-place fill.
  /// On backend failure the still-pending row is returned as an HTTP success, so
  /// the caller keeps the pending state and leaves the action available.
  Future<WordExplanation?> generateExplanation(WordExplanation pending) async {
    if (_isGenerating) return null;

    _isGenerating = true;
    _addError = null;
    notifyListeners();

    final request = AddWordRequest(
      wordText: pending.wordText,
      learningLanguage: pending.learningLanguage,
      explanationLanguage: pending.explanationLanguage,
    );

    try {
      final filled = await _vocabularyService.addWord(request);

      // Invalidate the cache so the detail screen reload picks up the fill.
      _explanationsCache.remove(pending.wordCollectionId);

      // Replace the matching list entry in place. The backend fill returns the
      // same explanation id; fall back to wordCollectionId for a merge repoint.
      final index = _words.indexWhere(
        (w) => w.id == pending.id || w.wordCollectionId == pending.wordCollectionId,
      );
      if (index != -1) {
        _words[index] = filled;
      }

      return filled;
    } on ServiceException catch (e) {
      _addError = e.toString();
      return null;
    } catch (e) {
      _addError = e.toString();
      return null;
    } finally {
      _isGenerating = false;
      notifyListeners();
    }
  }

  Future<void> switchExplanation(
    int wordCollectionId,
    int newExplanationId,
  ) async {
    try {
      await _vocabularyService.switchDefaultExplanation(
        wordCollectionId,
        newExplanationId,
      );

      // Update cache - this is enough for detail screen to show correct default
      if (_explanationsCache.containsKey(wordCollectionId)) {
        _explanationsCache[wordCollectionId]!.userDefaultExplanationId = newExplanationId;
      }

      // Note: We intentionally DON'T update _words list here because:
      // 1. Different explanations have different updatedAt timestamps
      // 2. Replacing would change the date grouping and make word "disappear"
      // 3. The word list shows user's interaction history, not explanation history
      // 4. Next time user refreshes the list, backend will return correct data

      notifyListeners();
    } catch (e) {
      rethrow;
    }
  }

  /// Clear all cached data when user logs out
  @override
  void clearAllData() {
    _words = [];
    _explanationsCache.clear();
    _isLoadingList = false;
    _isLoadingAdd = false;
    _isRefreshing = false;
    _listError = null;
    _addError = null;
    _currentPage = 1;
    _totalWords = 0;
    // Force immediate UI update
    notifyListeners();
  }

  /// Load initial data when user logs in
  @override
  Future<void> onLogin() async {
    await fetchWords();
  }
}

// Result class for refresh operations
class RefreshResult {
  final bool isSuccess;
  final bool wasUpdated;
  final String message;
  final WordExplanation? updatedExplanation;

  RefreshResult._(
    this.isSuccess,
    this.wasUpdated,
    this.message,
    this.updatedExplanation,
  );

  factory RefreshResult.success(WordExplanation explanation) {
    return RefreshResult._(
      true,
      true,
      'Explanation refreshed successfully',
      explanation,
    );
  }

  factory RefreshResult.noUpdate(String message) {
    return RefreshResult._(true, false, message, null);
  }

  factory RefreshResult.error(String message) {
    return RefreshResult._(false, false, message, null);
  }
}
