import 'dart:convert';
import 'dart:io';

import 'package:mychu/models/release_notes.dart';

final _releaseHeading = RegExp(
  r'^##[ \t]+\[v?(\d+\.\d+\.\d+)\][ \t]+-[ \t]+(\d{4}-\d{2}-\d{2})$',
);
final _sectionHeading = RegExp(r'^###[ \t]+(.+)$');
final _entryMarker = RegExp(r'^(?:[-+*]|\d+[.)]|>)[ \t]+');
final _inlineCode = RegExp(r'\x60([^\x60]+)\x60');
final _inlineLink = RegExp(r'\[([^\]]+)\]\([^)]+\)');

String _displayText(String text) => text
    .replaceAllMapped(_inlineLink, (match) => match[1]!)
    .replaceAllMapped(_inlineCode, (match) => match[1]!);

List<AppRelease> parseChangelog(String markdown) {
  final releases = <AppRelease>[];
  final versions = <String>{};
  List<ReleaseNoteSection>? sections;
  ReleaseNoteSection? section;
  var hasPendingEntry = false;

  for (final rawLine in const LineSplitter().convert(markdown)) {
    final line = rawLine.trimRight();
    if (line.startsWith('## ') || line.startsWith('##\t')) {
      sections = null;
      section = null;
      hasPendingEntry = false;
      final heading = _releaseHeading.firstMatch(line);
      if (heading == null) continue;

      final version = heading[1]!;
      if (!versions.add(version)) {
        throw FormatException('Duplicate CHANGELOG version: $version');
      }
      sections = [];
      releases.add(
        AppRelease(version: version, date: heading[2]!, sections: sections),
      );
      continue;
    }
    if (sections == null) continue;
    if (line.isEmpty) {
      hasPendingEntry = false;
      continue;
    }

    final heading = _sectionHeading.firstMatch(line);
    if (heading != null) {
      section = ReleaseNoteSection(
        title: _displayText(heading[1]!),
        entries: [],
      );
      sections.add(section);
      hasPendingEntry = false;
      continue;
    }

    if (section == null) {
      final entries = <String>[];
      section = ReleaseNoteSection(entries: entries);
      sections.add(section);
    }
    final content = line.trimLeft();
    final marker = _entryMarker.matchAsPrefix(content);
    final text = _displayText(content.substring(marker?.end ?? 0));
    if (hasPendingEntry && marker == null) {
      final entries = section.entries;
      entries[entries.length - 1] = '${entries.last} $text';
    } else {
      section.entries.add(text);
    }
    hasPendingEntry = true;
  }

  if (releases.isEmpty) {
    throw const FormatException(
      'CHANGELOG.md contains no dated release sections.',
    );
  }
  return releases;
}

void main(List<String> arguments) {
  const checkPrefix = '--check-version=';
  if (arguments.length == 1 && arguments.single.startsWith(checkPrefix)) {
    final version = arguments.single.substring(checkPrefix.length);
    try {
      final releases = parseChangelog(File('CHANGELOG.md').readAsStringSync());
      final hasNotes = releases.any(
        (release) => release.version == version && release.sections.isNotEmpty,
      );
      if (!hasNotes) {
        throw FormatException(
          'CHANGELOG.md has no notes for version $version.',
        );
      }
    } on FormatException catch (error) {
      stderr.writeln(error.message);
      exitCode = 65;
    }
    return;
  }
  if (arguments.length != 2 ||
      !arguments[0].startsWith('--input=') ||
      !arguments[1].startsWith('--output=')) {
    stderr.writeln(
      'Usage: dart run mychu:release_notes --input=FILE --output=FILE',
    );
    exitCode = 64;
    return;
  }
  try {
    final input = File(arguments[0].substring('--input='.length));
    final output = File(arguments[1].substring('--output='.length));
    output.writeAsStringSync(
      jsonEncode(parseChangelog(input.readAsStringSync())),
    );
  } on FormatException catch (error) {
    stderr.writeln(error.message);
    exitCode = 65;
  }
}
