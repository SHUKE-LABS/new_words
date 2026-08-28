import 'package:flutter/material.dart';
import 'package:new_words/generated/app_localizations.dart';
import 'package:new_words/services/tts_service.dart';

/// Lets the learner pick the voice their stories are read in.
///
/// Automatic comes first and is what an untouched install uses: the service
/// then chooses the best offline voice for the locale. Voices that need
/// connectivity are offered but marked, because picking one deliberately is
/// reasonable while having one chosen silently is not.
///
/// Pops with the chosen [TtsVoice], or with null for automatic. The caller
/// distinguishes a choice from a dismissal by [popped] — dismissing the dialog
/// returns nothing at all.
class TtsVoiceSelectionDialog extends StatelessWidget {
  final List<TtsVoice> voices;
  final TtsVoice? selected;

  const TtsVoiceSelectionDialog({
    super.key,
    required this.voices,
    required this.selected,
  });

  /// Wrapper for the pop value, so "chose automatic" and "dismissed the
  /// dialog" stay distinguishable — both would otherwise be a bare null.
  static Future<TtsVoiceChoice?> show(
    BuildContext context, {
    required List<TtsVoice> voices,
    required TtsVoice? selected,
  }) {
    return showDialog<TtsVoiceChoice>(
      context: context,
      builder:
          (_) => TtsVoiceSelectionDialog(voices: voices, selected: selected),
    );
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context)!;

    return AlertDialog(
      title: Text(localizations.readAloudVoice),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView(
          shrinkWrap: true,
          children: [
            _option(
              context,
              label: localizations.readAloudVoiceAutomatic,
              detail: null,
              isSelected: selected == null,
              choice: const TtsVoiceChoice(null),
            ),
            for (final voice in voices)
              _option(
                context,
                label: voice.name,
                detail:
                    voice.networkRequired
                        ? localizations.readAloudVoiceNeedsConnection
                        : null,
                isSelected: selected == voice,
                choice: TtsVoiceChoice(voice),
              ),
          ],
        ),
      ),
    );
  }

  /// One row: the current selection is ticked rather than carrying a radio,
  /// which keeps the list to a single tap and needs no group state.
  Widget _option(
    BuildContext context, {
    required String label,
    required String? detail,
    required bool isSelected,
    required TtsVoiceChoice choice,
  }) {
    return ListTile(
      title: Text(label),
      subtitle: detail == null ? null : Text(detail),
      trailing:
          isSelected
              ? Icon(Icons.check, color: Theme.of(context).colorScheme.primary)
              : null,
      selected: isSelected,
      onTap: () => Navigator.of(context).pop(choice),
    );
  }
}

/// What the learner picked: a voice, or automatic when [voice] is null.
@immutable
class TtsVoiceChoice {
  final TtsVoice? voice;

  const TtsVoiceChoice(this.voice);
}
