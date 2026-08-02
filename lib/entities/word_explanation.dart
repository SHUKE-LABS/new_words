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
  });

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
        other.providerModelName == providerModelName;
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
      );
}
