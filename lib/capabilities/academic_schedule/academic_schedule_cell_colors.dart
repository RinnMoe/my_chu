import 'package:flutter/material.dart';

/// Separate course hues with opaque fills; course identity keeps its stable index.
const academicScheduleCellPalettes = <(Color, Color)>[
  (Color(0xff3f78ac), Color(0xff29445d)),
  (Color(0xff287c60), Color(0xff285047)),
  (Color(0xffb05a22), Color(0xff624333)),
  (Color(0xff7650ad), Color(0xff493d65)),
  (Color(0xff567e32), Color(0xff38513c)),
  (Color(0xff5269a7), Color(0xff37446b)),
  (Color(0xffac4774), Color(0xff60384c)),
  (Color(0xff287d87), Color(0xff2f4e55)),
  (Color(0xffb14e46), Color(0xff623c39)),
  (Color(0xff737923), Color(0xff485238)),
  (Color(0xff327999), Color(0xff304c61)),
  (Color(0xff914699), Color(0xff4c3d5a)),
  (Color(0xff487b81), Color(0xff394c55)),
  (Color(0xff946237), Color(0xff51443e)),
  (Color(0xff77608b), Color(0xff43474c)),
];

class AcademicScheduleCellColors {
  const AcademicScheduleCellColors(
    this.background,
    this.foreground,
    this.border,
  );
  final Color background;
  final Color foreground;
  final Color border;
}

AcademicScheduleCellColors academicScheduleCellColors(
  int index, {
  required bool dark,
  bool nonCurrent = false,
}) {
  final palette =
      academicScheduleCellPalettes[index % academicScheduleCellPalettes.length];
  if (nonCurrent) {
    return dark
        ? const AcademicScheduleCellColors(
          Color(0xff252a32),
          Color(0xffa2abb8),
          Color(0xff343b46),
        )
        : const AcademicScheduleCellColors(
          Color(0xffe4e7ec),
          Color(0xff5e6875),
          Color(0xffd5dae1),
        );
  }
  final background = dark ? palette.$2 : palette.$1;
  final border = Color.lerp(background, Colors.white, dark ? .14 : .5)!;
  return AcademicScheduleCellColors(background, Colors.white, border);
}
