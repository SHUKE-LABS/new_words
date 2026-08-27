/// Foundation classes for the new architecture
/// 
/// This barrel file exports all foundation classes to make importing easier.
/// Import this file to get access to all foundation components:
/// 
/// ```dart
/// import 'package:new_words/common/foundation/foundation.dart';
/// ```
library;

// Core response and exception handling
export 'api_response_v2.dart';
export 'service_exceptions.dart';

// Shared behaviour mixed into the base classes
export 'input_validator.dart';

// Base classes for API and Service layers
export 'base_api.dart';
export 'base_service.dart';