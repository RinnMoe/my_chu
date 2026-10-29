import 'dart:convert';

import 'package:crypto/crypto.dart';

class PrivacyPolicySection {
  const PrivacyPolicySection({
    required this.id,
    required this.title,
    required this.paragraphs,
  });
  final String id;
  final String title;
  final List<String> paragraphs;
}

/// A validated, immutable copy of the exact bytes presented for acceptance.
class PrivacyPolicyDocument {
  PrivacyPolicyDocument._(
    this.version,
    this.revision,
    this.title,
    this.updatedDate,
    this.summary,
    this.sections,
    this.encoded,
    this.hash,
  );

  factory PrivacyPolicyDocument.decode(String encoded, {String? expectedHash}) {
    final hash = sha256.convert(utf8.encode(encoded)).toString();
    if (expectedHash != null && hash != expectedHash) {
      throw const FormatException('Policy hash mismatch');
    }
    final json = jsonDecode(encoded) as Map<String, dynamic>;
    final version = json['version'];
    if (json['schemaVersion'] != 1 || version is! int || version < 3) {
      throw const FormatException('Unsupported policy');
    }
    String field(Map<String, dynamic> value, String key) {
      final text = value[key];
      if (text is! String || text.trim().isEmpty) {
        throw const FormatException('Missing policy field');
      }
      return text;
    }

    final updated = field(json, 'updatedDate');
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(updated) ||
        DateTime.tryParse(updated)?.toIso8601String().substring(0, 10) !=
            updated) {
      throw const FormatException('Invalid policy date');
    }
    final sections = (json['sections'] as List)
        .map((raw) {
          final value = raw as Map<String, dynamic>;
          final paragraphs = (value['paragraphs'] as List)
              .map((text) {
                if (text is! String || text.trim().isEmpty) {
                  throw const FormatException('Invalid paragraph');
                }
                return text;
              })
              .toList(growable: false);
          if (paragraphs.isEmpty) throw const FormatException('Empty section');
          return PrivacyPolicySection(
            id: field(value, 'id'),
            title: field(value, 'title'),
            paragraphs: List.unmodifiable(paragraphs),
          );
        })
        .toList(growable: false);
    if (sections.isEmpty ||
        sections.map((s) => s.id).toSet().length != sections.length) {
      throw const FormatException('Invalid sections');
    }
    return PrivacyPolicyDocument._(
      version,
      field(json, 'revision'),
      field(json, 'title'),
      updated,
      field(json, 'summary'),
      List.unmodifiable(sections),
      encoded,
      hash,
    );
  }

  final int version;
  final String revision;
  final String title;
  final String updatedDate;
  final String summary;
  final List<PrivacyPolicySection> sections;
  final String encoded;
  final String hash;
}
