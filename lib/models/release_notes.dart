class AppRelease {
  const AppRelease({
    required this.version,
    required this.date,
    required this.sections,
  });

  final String version;
  final String date;
  final List<ReleaseNoteSection> sections;

  factory AppRelease.fromJson(Map<String, dynamic> json) => AppRelease(
    version: json['version'] as String,
    date: json['date'] as String,
    sections: [
      for (final section in json['sections'] as List<dynamic>)
        ReleaseNoteSection.fromJson(section as Map<String, dynamic>),
    ],
  );

  Map<String, Object> toJson() => {
    'version': version,
    'date': date,
    'sections': sections,
  };
}

class ReleaseNoteSection {
  const ReleaseNoteSection({this.title, required this.entries});

  final String? title;
  final List<String> entries;

  factory ReleaseNoteSection.fromJson(Map<String, dynamic> json) =>
      ReleaseNoteSection(
        title: json['title'] as String?,
        entries: List<String>.from(json['entries'] as List<dynamic>),
      );

  Map<String, Object?> toJson() => {'title': title, 'entries': entries};
}
