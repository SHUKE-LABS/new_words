# Flutter Vocabulary App - Architecture Documentation

## Overview

This Flutter vocabulary learning application follows a modern, layered architecture designed for scalability, maintainability, and testability. The architecture has been completely modernized with V2 patterns that provide standardized error handling, type safety, and consistent development patterns.

## Architecture Layers

```
┌─────────────────────────────────────────────────┐
│                UI Layer                         │
│  ┌─────────────────┐  ┌─────────────────────┐   │
│  │     Screens     │  │      Widgets        │   │
│  └─────────────────┘  └─────────────────────┘   │
└─────────────────────────────────────────────────┘
                         │
┌─────────────────────────────────────────────────┐
│               Provider Layer                    │
│  ┌─────────────────┐  ┌─────────────────────┐   │
│  │  AuthAware      │  │   State Management  │   │
│  │  Providers      │  │   & Error Handling  │   │
│  └─────────────────┘  └─────────────────────┘   │
└─────────────────────────────────────────────────┘
                         │
┌─────────────────────────────────────────────────┐
│              Service Layer                      │
│  ┌─────────────────┐  ┌─────────────────────┐   │
│  │   Business      │  │   Data Processing   │   │
│  │    Logic        │  │   & Validation      │   │
│  └─────────────────┘  └─────────────────────┘   │
└─────────────────────────────────────────────────┘
                         │
┌─────────────────────────────────────────────────┐
│               API Layer                         │
│  ┌─────────────────┐  ┌─────────────────────┐   │
│  │   HTTP Client   │  │   Request/Response  │   │
│  │   & Networking  │  │     Processing      │   │
│  └─────────────────┘  └─────────────────────┘   │
└─────────────────────────────────────────────────┘
                         │
┌─────────────────────────────────────────────────┐
│            Foundation Layer                     │
│  ┌─────────────────┐  ┌─────────────────────┐   │
│  │   Base Classes  │  │   Common Utilities  │   │
│  │   & Interfaces  │  │   & Constants       │   │
│  └─────────────────┘  └─────────────────────┘   │
└─────────────────────────────────────────────────┘
```

## Key Architectural Principles

### 1. **Separation of Concerns**
- **UI Layer**: Presentation logic and user interactions
- **Provider Layer**: State management and UI-business logic bridge
- **Service Layer**: Business logic and data transformation
- **API Layer**: Network communication and data fetching
- **Foundation Layer**: Shared utilities and base implementations

### 2. **Dependency Injection**
- Uses GetIt service locator pattern
- Clean dependency management with proper registration order
- Testable architecture with easy mocking

### 3. **Error Handling Strategy**
- Standardized exception hierarchy (`ServiceException`, `NetworkException`, `ApiBusinessException`)
- Consistent error propagation from API → Service → Provider → UI
- User-friendly error messages with proper context

### 4. **Type Safety**
- Generic type support throughout the stack (`ApiResponseV2<T>`, `PageData<T>`)
- Null safety compliance
- Compile-time error prevention

## Core Components

### Foundation Layer

#### Base Classes
- **`BaseApi`**: Common HTTP operations with standardized error handling
- **`BaseService`**: Business logic foundation with logging and exception management
- **`AuthAwareProvider`**: Provider base class with auth lifecycle management

#### Response Wrappers
- **`ApiResponseV2<T>`**: Type-safe API response wrapper
- **`PageData<T>`**: Pagination data structure
- **Service Result Types**: Standardized operation result patterns

#### Exception Hierarchy
```dart
abstract class ServiceException
├── NetworkException (connection, timeout, HTTP errors)
├── ApiBusinessException (business logic errors from backend)
├── ValidationException (input validation failures)
└── DataException (data processing errors)
```

### API Layer (V2)

Modern API implementations extending `BaseApi`:

- **`VocabularyApiV2`**: Word management, CRUD operations, memory retrieval
- **`AccountApiV2`**: Authentication, user management, token refresh
- **`StoriesApiV2`**: Story generation, reading progress, favorites
- **`UserSettingsApiV2`**: User preference management
- **`SettingsApiV2`**: Application configuration

**Key Features:**
- Input validation at API boundary
- Standardized request/response handling
- Automatic error conversion to typed exceptions
- Consistent pagination patterns

### Service Layer (V2)

Business logic implementations extending `BaseService`:

- **`VocabularyServiceV2`**: Word learning business logic
- **`AccountServiceV2`**: Authentication and user management
- **`StoriesServiceV2`**: Story management and progress tracking
- **`UserSettingsServiceV2`**: Settings management with session integration
- **`SettingsServiceV2`**: Application configuration management
- **`MemoriesServiceV2`**: Spaced repetition and memory management

**Key Features:**
- Business rule enforcement
- Data transformation and validation
- Session management integration
- Comprehensive operation logging
- Standardized exception handling

### Provider Layer

State management with Provider pattern:

- **`VocabularyProvider`**: Word list management, add/delete operations
- **`AuthProvider`**: Authentication state and token management
- **`StoriesProvider`**: Story lists, generation, and reading progress
- **`MemoriesProvider`**: Spaced repetition words and daily practice
- **`AppStateProvider`**: Global app state coordination

**Key Features:**
- Standardized error handling with `executeWithErrorHandling()`
- Auth-aware lifecycle management
- Consistent loading and error states
- Automatic UI updates with `notifyListeners()`

Cross-cutting services (TTS, in-app update, API timeouts) are documented in [docs/README.md → Cross-cutting services](./README.md#-cross-cutting-services).

## Data Flow

### Typical Request Flow
```
UI Widget
    │ User Action
    ▼
Provider
    │ Business Operation
    ▼
Service
    │ API Call
    ▼
API
    │ HTTP Request
    ▼
Backend
    │ HTTP Response
    ▼
API (Response Processing)
    │ Typed Data
    ▼
Service (Business Logic)
    │ Processed Data
    ▼
Provider (State Update)
    │ UI Notification
    ▼
UI Widget (Re-render)
```

### Error Flow
```
Backend Error
    │
    ▼
API Layer (Exception Creation)
    │ NetworkException/ApiBusinessException
    ▼
Service Layer (Exception Handling)
    │ ServiceException
    ▼
Provider Layer (Error State)
    │ User-friendly Message
    ▼
UI Layer (Error Display)
```

## State Management Strategy

### Authentication State
- **Global Auth State**: Managed by `AuthProvider`
- **Auth-Aware Providers**: Extend `AuthAwareProvider` for automatic lifecycle management
- **Session Management**: Centralized in `UserSession` singleton
- **Token Management**: Automatic refresh and validation

### Data State
- **Local State**: Provider-managed with loading/error/success states
- **Pagination State**: Consistent patterns across list-based features
- **Cache Management**: Provider-level caching with auth-aware clearing

### Error State
- **Consistent Error Handling**: Standardized across all providers
- **User-Friendly Messages**: Context-aware error formatting
- **Error Recovery**: Retry mechanisms and graceful degradation

## Testing Strategy

### Unit Testing
- **API Layer**: Mock HTTP client, test validation and response parsing
- **Service Layer**: Mock API dependencies, test business logic
- **Provider Layer**: Mock service dependencies, test state management

### Integration Testing
- **Cross-Layer Testing**: Verify proper data flow
- **Auth Integration**: Test authentication lifecycle
- **Error Propagation**: Verify error handling across layers

### Test Coverage Goals
- **API Layer**: 100% - Critical for data integrity
- **Service Layer**: 95% - Business logic validation
- **Provider Layer**: 90% - State management verification

## Performance Considerations

### Network Optimization
- **Request Batching**: Combine related API calls where possible
- **Pagination**: Efficient large dataset handling
- **Caching**: Provider-level data caching with TTL

### Memory Management
- **Auth-Aware Cleanup**: Automatic data clearing on logout
- **Lifecycle Management**: Proper resource disposal
- **Lazy Loading**: Services registered as lazy singletons

### UI Performance
- **Efficient State Updates**: Minimize unnecessary rebuilds
- **Loading States**: Immediate feedback for long operations
- **Error Boundaries**: Prevent cascading failures

## Security Considerations

### Authentication Security
- **Token Management**: Secure storage and automatic refresh
- **Session Validation**: Token expiry checking
- **Auth State Isolation**: Clean separation between user sessions

### Data Security
- **Input Validation**: Comprehensive validation at API boundaries
- **Error Information**: No sensitive data in error messages
- **Secure Communications**: HTTPS enforcement

## Development Guidelines

### Adding New Features

1. **Create API V2 class** extending `BaseApi`
2. **Implement Service V2 class** extending `BaseService`
3. **Update Provider** to use new service with standardized error handling
4. **Register dependencies** in `dependency_injection.dart`
5. **Write comprehensive tests** for all layers

### Error Handling Best Practices

1. **Use typed exceptions** from the ServiceException hierarchy
2. **Provide context** with operation names in error messages
3. **Handle errors at the right level** - don't catch and re-throw unnecessarily
4. **Use `executeWithErrorHandling()`** in providers for consistency

### Code Review Checklist

- [ ] Uses V2 architecture patterns
- [ ] Includes comprehensive error handling
- [ ] Has proper input validation
- [ ] Follows typing conventions (`ApiResponseV2<T>`)
- [ ] Includes unit tests with >90% coverage
- [ ] Uses dependency injection properly
- [ ] Handles authentication state correctly

## Migration from Legacy

### V1 to V2 Migration
1. **Keep V1 classes** during transition period
2. **Create V2 implementations** following new patterns
3. **Update providers** to use V2 services
4. **Verify functionality** with comprehensive testing
5. **Remove V1 classes** after successful migration

### Breaking Changes
- Error handling patterns changed from try-catch to standardized exceptions
- Response types changed from dynamic to typed `ApiResponseV2<T>`
- Provider patterns changed to use `executeWithErrorHandling()`

## Future Enhancements

### Planned Improvements
- **Offline Support**: Add local database layer
- **Real-time Updates**: WebSocket integration
- **Analytics Integration**: Structured logging and metrics
- **Performance Monitoring**: API call timing and error rates
- **A/B Testing**: Feature flag support

### Scalability Considerations
- **Microservice Support**: Modular API layer for service decomposition
- **Multi-tenant Support**: User isolation and data partitioning
- **Internationalization**: Localized error messages and content
- **Platform Expansion**: Shared business logic for web/desktop versions

This architecture provides a solid foundation for the vocabulary learning application with modern patterns, comprehensive error handling, and excellent testability. The V2 migration establishes consistent development practices that will accelerate future feature development while maintaining high code quality and user experience.