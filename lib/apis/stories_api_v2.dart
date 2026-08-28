import 'package:new_words/common/foundation/foundation.dart';
import 'package:new_words/entities/generate_story_request.dart';
import 'package:new_words/entities/story.dart';
import 'package:new_words/entities/page_data.dart';

/// Modern stories API implementation using BaseApi foundation
/// 
/// This class replaces the old StoriesApi with standardized error handling,
/// validation patterns, and centralized constants usage.
class StoriesApiV2 extends BaseApi {
  StoriesApiV2([super.customDio]);
  
  /// Get current user's generated stories with pagination
  Future<ApiResponseV2<PageData<Story>>> getMyStories(int pageNumber, int pageSize) async {
    validateInput({
      'pageNumber': pageNumber,
      'pageSize': pageSize,
    });
    
    final paginationParams = processPaginationParams(pageNumber, pageSize);
    
    return await get<PageData<Story>>(
      '/stories/MyStories',
      queryParameters: paginationParams,
      fromJson: (json) => PageData<Story>.fromJson(
        json as Map<String, dynamic>,
        (storyJson) => Story.fromJson(storyJson as Map<String, dynamic>),
      ),
    );
  }

  /// Browse popular stories from other users for discovery
  Future<ApiResponseV2<PageData<Story>>> getStorySquare(int pageNumber, int pageSize) async {
    validateInput({
      'pageNumber': pageNumber,
      'pageSize': pageSize,
    });
    
    final paginationParams = processPaginationParams(pageNumber, pageSize);
    
    return await get<PageData<Story>>(
      '/stories/StorySquare',
      queryParameters: paginationParams,
      fromJson: (json) => PageData<Story>.fromJson(
        json as Map<String, dynamic>,
        (storyJson) => Story.fromJson(storyJson as Map<String, dynamic>),
      ),
    );
  }

  /// Get stories the current user has favorited
  Future<ApiResponseV2<PageData<Story>>> getMyFavoriteStories(int pageNumber, int pageSize) async {
    validateInput({
      'pageNumber': pageNumber,
      'pageSize': pageSize,
    });
    
    final paginationParams = processPaginationParams(pageNumber, pageSize);
    
    return await get<PageData<Story>>(
      '/stories/MyFavorite',
      queryParameters: paginationParams,
      fromJson: (json) => PageData<Story>.fromJson(
        json as Map<String, dynamic>,
        (storyJson) => Story.fromJson(storyJson as Map<String, dynamic>),
      ),
    );
  }

  /// Generate one or more stories for the current user
  Future<ApiResponseV2<List<Story>>> generateStories(GenerateStoryRequest? request) async {
    // Note: request can be null for generating from recent vocabulary
    final requestData = request?.toJson() ?? {};
    
    return await post<List<Story>>(
      '/stories/Generate',
      data: requestData,
      options: createLongRunningOptions(
        receiveTimeout: const Duration(minutes: 5), // Story generation takes time
        sendTimeout: const Duration(minutes: 1),
      ),
      fromJson: (json) => (json as List<dynamic>)
          .map((storyJson) => Story.fromJson(storyJson as Map<String, dynamic>))
          .toList(),
    );
  }

  /// Mark a story as read by the current user
  Future<ApiResponseV2<void>> markStoryAsRead(int storyId) async {
    validateNumericField(storyId, 'storyId', min: 1);
    
    return await requestVoid(
      'POST',
      '/stories/MarkRead/$storyId',
    );
  }

  /// Add or remove a story from the current user's favorites
  Future<ApiResponseV2<void>> toggleFavorite(int storyId) async {
    validateNumericField(storyId, 'storyId', min: 1);
    
    return await requestVoid(
      'POST',
      '/stories/ToggleFavorite/$storyId',
    );
  }
}