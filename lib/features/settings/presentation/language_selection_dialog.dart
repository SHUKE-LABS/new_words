import 'package:flutter/material.dart';
import 'package:new_words/common/constants/language_constants.dart';
import 'package:new_words/entities/language.dart';
import 'package:new_words/services/settings_service_v2.dart';
import 'package:new_words/dependency_injection.dart';

class LanguageSelectionDialog extends StatefulWidget {
  final String? currentNativeLanguage;
  final String? currentLearningLanguage;
  final Function(String nativeLanguage, String learningLanguage)
  onLanguagesSelected;

  const LanguageSelectionDialog({
    super.key,
    required this.currentNativeLanguage,
    required this.currentLearningLanguage,
    required this.onLanguagesSelected,
  });

  @override
  State<LanguageSelectionDialog> createState() =>
      _LanguageSelectionDialogState();
}

class _LanguageSelectionDialogState extends State<LanguageSelectionDialog> {
  late String _selectedNativeLanguage;
  late String _selectedLearningLanguage;
  bool _isLoading = false;
  bool _isLoadingLanguages = true;
  List<Language> _availableLanguages = [];
  final SettingsServiceV2 _settingsService = locator<SettingsServiceV2>();

  @override
  void initState() {
    super.initState();
    _selectedNativeLanguage = widget.currentNativeLanguage ?? 'en';
    _selectedLearningLanguage = widget.currentLearningLanguage ?? 'en';
    _loadLanguages();
  }

  Future<void> _loadLanguages() async {
    try {
      final languages = await _settingsService.getSupportedLanguages();
      if (!mounted) return;
      if (languages.isNotEmpty) {
        setState(() {
          _availableLanguages = languages;
          _validateSelectedLanguages();
          _isLoadingLanguages = false;
        });
      } else {
        _useFallbackLanguages();
      }
    } catch (e) {
      debugPrint('Failed to load languages from API: $e');
      _useFallbackLanguages();
    }
  }

  void _validateSelectedLanguages() {
    final availableCodes =
        _availableLanguages.map((lang) => lang.code).toList();

    // If current native language is not in the available list, default to 'en'
    if (!availableCodes.contains(_selectedNativeLanguage)) {
      _selectedNativeLanguage =
          availableCodes.contains('en') ? 'en' : availableCodes.first;
    }

    // If current learning language is not in the available list, default to 'en' or first available
    if (!availableCodes.contains(_selectedLearningLanguage)) {
      _selectedLearningLanguage =
          availableCodes.contains('en') ? 'en' : availableCodes.first;
    }

    // Ensure they are different
    if (_selectedNativeLanguage == _selectedLearningLanguage &&
        availableCodes.length > 1) {
      _selectedLearningLanguage = availableCodes.firstWhere(
        (code) => code != _selectedNativeLanguage,
        orElse: () => availableCodes.first,
      );
    }
  }

  void _useFallbackLanguages() {
    if (!mounted) return;
    setState(() {
      _availableLanguages = LanguageConstants.supportedLanguages;
      _validateSelectedLanguages();
      _isLoadingLanguages = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Using offline language list'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  bool _isValidSelection() {
    return _selectedNativeLanguage != _selectedLearningLanguage;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Change Languages'),
      content:
          _isLoadingLanguages
              ? const Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Loading languages...'),
                ],
              )
              : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    value: _selectedNativeLanguage,
                    decoration: const InputDecoration(
                      labelText: 'Native Language',
                      border: OutlineInputBorder(),
                    ),
                    items:
                        _availableLanguages.map((language) {
                          return DropdownMenuItem<String>(
                            value: language.code,
                            child: Text(language.name),
                          );
                        }).toList(),
                    onChanged:
                        _isLoading || _isLoadingLanguages
                            ? null
                            : (String? newValue) {
                              if (newValue != null) {
                                setState(() {
                                  _selectedNativeLanguage = newValue;
                                });
                              }
                            },
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    value: _selectedLearningLanguage,
                    decoration: const InputDecoration(
                      labelText: 'Learning Language',
                      border: OutlineInputBorder(),
                    ),
                    items:
                        _availableLanguages.map((language) {
                          return DropdownMenuItem<String>(
                            value: language.code,
                            child: Text(language.name),
                          );
                        }).toList(),
                    onChanged:
                        _isLoading || _isLoadingLanguages
                            ? null
                            : (String? newValue) {
                              if (newValue != null) {
                                setState(() {
                                  _selectedLearningLanguage = newValue;
                                });
                              }
                            },
                  ),
                  if (!_isValidSelection())
                    const Padding(
                      padding: EdgeInsets.only(top: 8.0),
                      child: Text(
                        'Native language and learning language must be different',
                        style: TextStyle(color: Colors.red, fontSize: 12),
                      ),
                    ),
                ],
              ),
      actions: [
        TextButton(
          onPressed:
              _isLoading || _isLoadingLanguages
                  ? null
                  : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed:
              _isLoading || _isLoadingLanguages || !_isValidSelection()
                  ? null
                  : () async {
                    setState(() {
                      _isLoading = true;
                    });

                    try {
                      await widget.onLanguagesSelected(
                        _selectedNativeLanguage,
                        _selectedLearningLanguage,
                      );
                      if (context.mounted) {
                        Navigator.of(context).pop();
                      }
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'Failed to update languages: ${e.toString()}',
                            ),
                            backgroundColor: Colors.red,
                          ),
                        );
                      }
                    } finally {
                      if (mounted) {
                        setState(() {
                          _isLoading = false;
                        });
                      }
                    }
                  },
          child:
              _isLoading
                  ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                  : const Text('Save'),
        ),
      ],
    );
  }
}
