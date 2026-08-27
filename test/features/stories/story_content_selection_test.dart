import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Guards the rendering decision behind story read-aloud: story content moved
/// from `SelectableText.rich` to `SelectionArea` + `Text.rich` because the
/// former never dispatches span tap recognizers, which per-sentence playback
/// depends on.
void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  testWidgets('SelectionArea + Text.rich dispatches span tap recognizers',
      (tester) async {
    var taps = 0;
    final recognizer = TapGestureRecognizer()..onTap = () => taps++;
    addTearDown(recognizer.dispose);

    await tester.pumpWidget(
      wrap(
        SelectionArea(
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(text: 'First sentence. ', recognizer: recognizer),
                const TextSpan(text: 'Second sentence.'),
              ],
            ),
          ),
        ),
      ),
    );

    await tester.tapAt(
      tester.getTopLeft(find.byType(RichText)) + const Offset(4, 8),
    );
    await tester.pumpAndSettle();

    expect(taps, 1);
  });
}
