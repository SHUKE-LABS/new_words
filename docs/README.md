# Flutter Vocabulary App - Technical Documentation

## Overview

This documentation covers the modern V2 architecture implementation for the Flutter vocabulary learning application. The architecture has been completely modernized to provide consistent patterns, comprehensive error handling, and excellent testability.

## 📚 Documentation Index

### Core Architecture
- **[ARCHITECTURE.md](./ARCHITECTURE.md)** - Complete architecture overview, design principles, and component relationships
- **[V2_PATTERNS.md](./V2_PATTERNS.md)** - Detailed patterns and best practices for V2 implementations
- **[MIGRATION_GUIDE.md](./MIGRATION_GUIDE.md)** - Step-by-step guide for migrating legacy code to V2

### Quick Reference
- **API Layer**: Modern HTTP clients with type-safe responses and validation
- **Service Layer**: Business logic with standardized error handling and logging
- **Provider Layer**: State management with auth-aware lifecycle and consistent patterns
- **Foundation Layer**: Shared utilities, base classes, and exception hierarchy

## 🏗️ Architecture Highlights

### Modern Foundation Classes
```dart
// Type-safe API responses
ApiResponseV2<List<Word>> response = await api.getWords();

// Standardized service operations  
Future<Word> createWord(WordRequest request) async {
  return processResponse(await _api.createWord(request));
}

// Consistent provider error handling
final result = await executeWithErrorHandling<List<Word>>(
  operation: () => _service.getWords(),
  setLoading: (loading) => _isLoading = loading,
  setError: (error) => _error = error,
  operationName: 'load words',
);
```

### Exception Hierarchy
```
ServiceException (abstract)
├── NetworkException (connection, timeout, HTTP errors)
├── ApiBusinessException (business logic errors)
├── ValidationException (input validation failures)
└── DataException (data processing errors)
```

## 🚀 Getting Started

### For New Features
1. Read [V2_PATTERNS.md](./V2_PATTERNS.md) for implementation patterns
2. Follow the base class patterns (BaseApi, BaseService, AuthAwareProvider)
3. Implement comprehensive tests following established patterns
4. Register dependencies in dependency injection

### For Legacy Migration
1. Follow [MIGRATION_GUIDE.md](./MIGRATION_GUIDE.md) step-by-step process
2. Start with API layer, then Service layer, then Provider layer
3. Maintain backward compatibility during transition
4. Validate thoroughly before removing legacy code

### Quick Start Example

#### 1. Create V2 API
```dart
class MyFeatureApiV2 extends BaseApi {
  MyFeatureApiV2([super.customDio]);

  Future<ApiResponseV2<MyData>> getData(int id) async {
    validateNumericField(id, 'id', min: 1);
    
    return await get<MyData>(
      '/my-feature/data/$id',
      fromJson: (json) => MyData.fromJson(json as Map<String, dynamic>),
    );
  }
}
```

#### 2. Create V2 Service
```dart
class MyFeatureServiceV2 extends BaseService {
  final MyFeatureApiV2 _api;
  
  MyFeatureServiceV2({required MyFeatureApiV2 api}) : _api = api;

  Future<MyData> getData(int id) async {
    logOperation('getData', parameters: {'id': id});
    
    try {
      final response = await _api.getData(id);
      return processResponse(response);
    } catch (e) {
      throw ServiceExceptionFactory.fromException(e);
    }
  }
}
```

#### 3. Update Provider
```dart
class MyFeatureProvider extends AuthAwareProvider {
  final MyFeatureServiceV2 _service;
  
  MyFeatureProvider(this._service);

  Future<void> loadData(int id) async {
    final result = await executeWithErrorHandling<MyData>(
      operation: () => _service.getData(id),
      setLoading: (loading) => _isLoading = loading,
      setError: (error) => _error = error,
      operationName: 'load data',
    );
    
    if (result != null) {
      _data = result;
    }
  }

  @override
  void clearAllData() {
    _data = null;
    _isLoading = false;
    _error = null;
    notifyListeners();
  }
}
```

## 🧪 Testing Strategy

### Comprehensive Test Coverage
- **API Layer**: Input validation, response parsing, error scenarios (175+ tests)
- **Service Layer**: Business logic, exception handling, logging verification  
- **Provider Layer**: State management, auth lifecycle, error propagation

### Test Patterns
```dart
// API Testing
@GenerateMocks([Dio])
void main() {
  group('MyApiV2', () {
    test('should handle successful response', () async {
      // Arrange, Act, Assert pattern
    });
    
    test('should validate input parameters', () async {
      // Test validation logic
    });
  });
}

// Service Testing  
@GenerateMocks([MyApiV2, AppLoggerInterface])
void main() {
  group('MyServiceV2', () {
    test('should process API response correctly', () async {
      // Test business logic
    });
  });
}
```

## 📊 Architecture Benefits

### Developer Experience
- **Consistent Patterns**: Same approach across all features
- **Type Safety**: Compile-time error prevention with generics
- **Comprehensive Testing**: High confidence in code reliability
- **Easy Debugging**: Structured logging and clear error messages

### Maintainability
- **DRY Principle**: Shared base classes eliminate code duplication
- **Single Responsibility**: Clear separation between API, Service, Provider layers
- **Extensibility**: Easy to add new features following established patterns
- **Refactoring Safety**: Type system catches breaking changes

### User Experience
- **Reliable Error Handling**: Consistent error messages and recovery
- **Performance**: Efficient state management and data loading
- **Offline Resilience**: Graceful degradation on network issues
- **Consistent Behavior**: Standardized patterns across all features

## 🔌 Cross-cutting services

The V2 layers above are domain-bounded; the services below span multiple features and are documented here so they aren't lost between feature-specific docs.

### Text-to-Speech (TTS)

- **Implementation**: `lib/services/tts_service.dart`
- **Platform plugin**: `flutter_tts` (see `pubspec.yaml`)
- **Consumer**: `lib/features/word_detail/presentation/word_detail_screen.dart` and `lib/common/widgets/tts_markdown_builder.dart` for sentence-level playback
- **Support check** (`tts_service.dart:103-110`): the `isSupported` getter short-circuits to `false` on Linux by catching `UnsupportedError` from `Platform.isLinux`, so the UI can hide TTS affordances on platforms where `flutter_tts` is unavailable.
- **Scope**: ships in `1c2352a` / `dcb77e2`; intentionally not wired into vocabulary-list playback yet.

### In-app update

- **Implementation**: `lib/services/update_service.dart` + `lib/providers/update_provider.dart`
- **UX**: `lib/features/app_update/presentation/app_update_dialog.dart` (release notes, version comparison, download progress, install handoff via `open_filex`)
- **Source**: `GitHubApi` polls `repos/shukebeta/new_words/releases/latest` (`lib/apis/github_api.dart`); APK assets are surfaced through `entities/github_release.dart`. The `github_releases` API surface is read-only — there is no upload flow from the app.
- **Gating**: user-triggered from a Settings entry point — there is no auto-prompt on launch.
- **First-release behavior**: when the running app version equals the latest GitHub release, `UpdateService.checkForUpdate` returns `null` and the dialog is not offered. Documented in `docs/release.md`.

### API timeout configuration

- **File**: `lib/dio_client.dart:15-16`
- **Values**: `connectTimeout = 30s`, `receiveTimeout = 60s` (raised from the previous defaults in `2aca86e`).
- **Effect**: long-running endpoints (story generation, memory warm-ups) no longer fail with `DioExceptionType.receiveTimeout` under normal network conditions. `sendTimeout` remains commented out; the comment is intentional.

## 📈 Current Implementation Status (snapshot of 2026-01-09 / Plan 7)

> Snapshot as of Plan 7; live services are tracked in the "Cross-cutting services" section above.

### ✅ Completed Migrations
- **VocabularyApi + VocabularyService** → V2 (Plan 3)
- **AccountApi + AccountService** → V2 (Plan 4)
- **StoriesApi + StoriesService** → V2 (Plan 5)
- **UserSettingsApi + UserSettingsService** → V2 (Plan 6)
- **SettingsApi + SettingsService** → V2 (Plan 6)
- **MemoriesService** → V2 (Plan 6)
- **All Providers** → V2 service integration (Plan 7)

### 📊 Metrics
- **175+ Tests** across all V2 implementations
- **100% Test Coverage** for API and Service layers
- **Zero Regressions** in application functionality  
- **60% Code Reduction** in provider boilerplate
- **Standardized Error Handling** across all features

## 🔧 Development Tools

### Code Generation
```bash
# Generate mocks for testing
dart run build_runner build

# Clean and rebuild
dart run build_runner clean
dart run build_runner build --delete-conflicting-outputs
```

### Quality Assurance
```bash
# Static analysis
flutter analyze

# Run all tests
flutter test

# Format code
dart format .

# Check dependencies
flutter pub deps
```

### Debugging
```bash
# Run with debug logging
flutter run --debug

# Profile performance
flutter run --profile

# Check app performance
flutter run --trace-startup
```

## 🚦 Development Workflow

### Adding New Features
1. **Design Phase**: Review architecture docs and plan implementation
2. **API Layer**: Create V2 API with comprehensive validation
3. **Service Layer**: Implement business logic with proper error handling
4. **Provider Layer**: Use standardized patterns for state management
5. **Testing**: Write comprehensive tests for all layers
6. **Integration**: Register dependencies and test end-to-end
7. **Documentation**: Update relevant docs and examples

### Code Review Checklist
- [ ] Follows V2 architecture patterns
- [ ] Includes comprehensive error handling
- [ ] Has proper input validation
- [ ] Uses dependency injection correctly
- [ ] Includes unit tests with >90% coverage
- [ ] Handles authentication state properly
- [ ] No performance regressions

## 🔮 Future Roadmap

### Planned Enhancements
- **Offline Support**: Local database integration
- **Real-time Features**: WebSocket implementation
- **Analytics**: Structured logging and metrics
- **Performance Monitoring**: API timing and error tracking
- **Internationalization**: Multi-language error messages

### Architecture Evolution
- **Microservice Support**: Modular API architecture
- **State Management**: Consider moving to Riverpod for complex state
- **Code Generation**: Automated model and API generation
- **CI/CD Integration**: Automated testing and deployment

## 📞 Support and Contribution

### Getting Help
- Review documentation files for detailed guidance
- Check existing V2 implementations for patterns
- Run tests to validate changes: `flutter test`
- Use `flutter analyze` to catch potential issues

### Contributing
- Follow established V2 patterns for consistency
- Add comprehensive tests for new functionality
- Update documentation for significant changes
- Validate changes don't break existing functionality

### Best Practices
- **Start with tests** to define expected behavior
- **Use type safety** throughout the implementation
- **Handle errors gracefully** with user-friendly messages
- **Log operations** for debugging and monitoring
- **Validate inputs** at appropriate boundaries

This modern architecture provides a solid foundation for scalable, maintainable, and reliable Flutter application development. The comprehensive documentation, consistent patterns, and thorough testing ensure that the codebase remains high-quality and developer-friendly as the application grows.