/// Explanation generation status as returned by the backend.
///
/// The backend enum has only these two values: a word is persisted at add time
/// and, when the LLM is unavailable, saved as [pending] with placeholder markdown
/// to be filled in place later.
class ExplanationStatus {
  static const int ready = 0;
  static const int pending = 1;
}

class WordExplanation {
  final int id;
  final int wordCollectionId;
  final String wordText;
  final String learningLanguage;
  final String explanationLanguage;
  final String markdownExplanation;
  final String? pronunciation;
  final String? definitions;
  final String? examples;
  final int createdAt; // Unix timestamp
  final int updatedAt; // Unix timestamp for last interaction
  final String? providerModelName;
  final int status; // ExplanationStatus: 0 = Ready, 1 = Pending

  WordExplanation({
    required this.id,
    required this.wordCollectionId,
    required this.wordText,
    required this.learningLanguage,
    required this.explanationLanguage,
    required this.markdownExplanation,
    this.pronunciation,
    this.definitions,
    this.examples,
    required this.createdAt,
    required this.updatedAt,
    this.providerModelName,
    this.status = ExplanationStatus.ready,
  });

  /// True when the AI explanation has not been generated yet and the stored
  /// markdown is a placeholder rather than a final answer.
  bool get isPending => status == ExplanationStatus.pending;

  factory WordExplanation.fromJson(Map<String, dynamic> json) {
    return WordExplanation(
      id: json['id'] as int? ?? 0,
      wordCollectionId: json['wordCollectionId'] as int? ?? 0,
      wordText: json['wordText'] as String? ?? '',
      learningLanguage: json['learningLanguage'] as String? ?? '',
      explanationLanguage: json['explanationLanguage'] as String? ?? '',
      markdownExplanation: json['markdownExplanation'] as String? ?? '',
      pronunciation: json['pronunciation'] as String?,
      definitions: json['definitions'] as String?,
      examples: json['examples'] as String?,
      createdAt: json['createdAt'] as int? ?? 0,
      updatedAt: json['updatedAt'] as int? ?? json['createdAt'] as int? ?? 0,
      providerModelName: json['providerModelName'] as String?,
      // Absent status means a legacy/non-status endpoint; treat as Ready so
      // real explanations are never shown as pending.
      status: json['status'] as int? ?? ExplanationStatus.ready,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'wordCollectionId': wordCollectionId,
      'wordText': wordText,
      'learningLanguage': learningLanguage,
      'explanationLanguage': explanationLanguage,
      'markdownExplanation': markdownExplanation,
      'pronunciation': pronunciation,
      'definitions': definitions,
      'examples': examples,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
      'providerModelName': providerModelName,
      'status': status,
    };
  }

  /// Helper method to get user-friendly date when the word was learned
  DateTime get learnedDate =>
      DateTime.fromMillisecondsSinceEpoch(createdAt * 1000);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is WordExplanation &&
        other.id == id &&
        other.wordCollectionId == wordCollectionId &&
        other.wordText == wordText &&
        other.learningLanguage == learningLanguage &&
        other.explanationLanguage == explanationLanguage &&
        other.markdownExplanation == markdownExplanation &&
        other.pronunciation == pronunciation &&
        other.definitions == definitions &&
        other.examples == examples &&
        other.createdAt == createdAt &&
        other.updatedAt == updatedAt &&
        other.providerModelName == providerModelName &&
        other.status == status;
  }

  @override
  int get hashCode => Object.hash(
        id,
        wordCollectionId,
        wordText,
        learningLanguage,
        explanationLanguage,
        markdownExplanation,
        pronunciation,
        definitions,
        examples,
        createdAt,
        updatedAt,
        providerModelName,
        status,
      );
}
