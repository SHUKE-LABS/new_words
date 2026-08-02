import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:new_words/entities/word_explanation.dart';
import 'package:new_words/utils/util.dart';

class WordListItem extends StatelessWidget {
  final WordExplanation word;
  final VoidCallback onTap;
  final Function(WordExplanation)? onDelete;
  final String? dateLabel;
  final int maxPreviewLength;

  const WordListItem({
    super.key,
    required this.word,
    required this.onTap,
    this.onDelete,
    this.dateLabel,
    this.maxPreviewLength = 80,
  });

  @override
  Widget build(BuildContext context) {
    final timeString = _formatTime(word.updatedAt);

    Widget child = InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  '- $timeString - ${word.wordText} ',
                  style: const TextStyle(
                    fontWeight: FontWeight.w300,
                    color: Colors.blue,
                    fontSize: 13,
                  ),
                ),
                Expanded(
                  child: Divider(color: Colors.grey.shade300, thickness: 1),
                ),
                if (dateLabel != null)
                  Text(
                    '-$dateLabel-',
                    style: TextStyle(
                      fontWeight: FontWeight.w300,
                      color: Colors.grey.shade500,
                      fontSize: 12,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            MarkdownBody(
              data: _truncateMarkdownPreview(word.markdownExplanation),
              styleSheet: MarkdownStyleSheet(
                p: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          ],
        ),
      ),
    );

    if (onDelete == null) {
      return child;
    }

    return Dismissible(
      key: Key(word.id.toString()),
      direction: DismissDirection.endToStart,
      confirmDismiss: (direction) async {
        final confirmed = await showDialog(
          context: context,
          builder:
              (context) => AlertDialog(
                title: const Text('Delete Word'),
                content: const Text(
                  'Are you sure you want to delete this word?',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Cancel'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Delete'),
                  ),
                ],
              ),
        );
        return confirmed == true;
      },
      onDismissed: (direction) {
        onDelete!(word);
        Util.showInfo(
          ScaffoldMessenger.of(context),
          'Word deleted successfully',
        );
      },
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20.0),
        color: Colors.red,
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      child: child,
    );
  }

  String _formatTime(int timestamp) {
    final dateTime = DateTime.fromMillisecondsSinceEpoch(timestamp * 1000);
    final localTime = dateTime.toLocal();
    return '${localTime.hour}:${localTime.minute.toString().padLeft(2, '0')}';
  }

  String _truncateMarkdownPreview(String markdown) {
    // Remove newlines and truncate preview
    return markdown.length > maxPreviewLength
        ? '${markdown.substring(0, maxPreviewLength)}...'
        : markdown;
  }
}
