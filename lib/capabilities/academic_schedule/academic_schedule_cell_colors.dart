import 'package:flutter/material.dart';
import 'academic_schedule_appearance.dart';
import 'academic_schedule_style.dart';

/// All presets use the same 15 slots so switching never reassigns courses.
const academicScheduleCellPalettes = <(Color, Color)>[
  (Color(0xffd4ecfa), Color(0xff183b51)),
  (Color(0xffcfeee9), Color(0xff163e37)),
  (Color(0xffdcebdd), Color(0xff2a4030)),
  (Color(0xffdce3fa), Color(0xff293858)),
  (Color(0xffcceaf0), Color(0xff18404a)),
  (Color(0xffdaefea), Color(0xff26453c)),
  (Color(0xffd9e9f7), Color(0xff263d53)),
  (Color(0xffd9e3ef), Color(0xff303b4d)),
  (Color(0xffcce4df), Color(0xff204238)),
  (Color(0xffe1eddf), Color(0xff35432f)),
  (Color(0xffcfe3f3), Color(0xff1e3a50)),
  (Color(0xffd1e9ed), Color(0xff1d4247)),
  (Color(0xffdfe8f5), Color(0xff303d56)),
  (Color(0xffcce8e3), Color(0xff21463f)),
  (Color(0xffe2efe9), Color(0xff34483d)),
];

const _oceanForegrounds = <Color>[
  Color(0xff174c6b),
  Color(0xff17584c),
  Color(0xff385a39),
  Color(0xff374d80),
  Color(0xff195b69),
  Color(0xff345d49),
  Color(0xff2e5272),
  Color(0xff3e526e),
  Color(0xff2b5c4c),
  Color(0xff455d39),
  Color(0xff285473),
  Color(0xff2b5a61),
  Color(0xff3f5475),
  Color(0xff2a6054),
  Color(0xff435f4b),
];

const _classicDarkBackgrounds = <Color>[
  Color(0xff26394f),
  Color(0xff233e37),
  Color(0xff443628),
  Color(0xff383047),
  Color(0xff343d29),
  Color(0xff2f354c),
  Color(0xff442f3d),
  Color(0xff233d43),
  Color(0xff46302c),
  Color(0xff403b26),
  Color(0xff2b3a46),
  Color(0xff3e2e44),
  Color(0xff2d3c3c),
  Color(0xff3e352c),
  Color(0xff36323f),
];

const _sunsetBackgrounds = <Color>[
  Color(0xfff8d9c6),
  Color(0xfff3d0d6),
  Color(0xfff6e1bb),
  Color(0xffecd3de),
  Color(0xfff7cebe),
  Color(0xffe9d3cc),
  Color(0xfff4d9cd),
  Color(0xfff5dcbd),
  Color(0xffedccd4),
  Color(0xffeddcc9),
  Color(0xfff6d6be),
  Color(0xffebd4e4),
  Color(0xfff1cfc5),
  Color(0xfff3e0c6),
  Color(0xffe8ced6),
];

const _sunsetForegrounds = <Color>[
  Color(0xff81451f),
  Color(0xff853f53),
  Color(0xff74531a),
  Color(0xff74465e),
  Color(0xff88432b),
  Color(0xff70503d),
  Color(0xff805035),
  Color(0xff7d541c),
  Color(0xff804259),
  Color(0xff71523a),
  Color(0xff864a25),
  Color(0xff704464),
  Color(0xff864a3b),
  Color(0xff72532b),
  Color(0xff764559),
];

/// The eight historical hues, plus matching extensions for the current slots.
const _classicBackgrounds = <Color>[
  Color(0xffe3f2fd),
  Color(0xffe0f2f1),
  Color(0xfffff3e0),
  Color(0xfff3e5f5),
  Color(0xfff1f8e9),
  Color(0xffe8eaf6),
  Color(0xfffce4ec),
  Color(0xffe0f7fa),
  Color(0xffffe8e2),
  Color(0xfffaf2d3),
  Color(0xffe1effa),
  Color(0xfff5e5fa),
  Color(0xffe0f0ee),
  Color(0xfff3e9de),
  Color(0xffede7f6),
];

const _classicForegrounds = <Color>[
  Color(0xff1555a0),
  Color(0xff00695c),
  Color(0xff995000),
  Color(0xff7b1fa2),
  Color(0xff456b23),
  Color(0xff283593),
  Color(0xffad1457),
  Color(0xff006775),
  Color(0xff873f30),
  Color(0xff6b5717),
  Color(0xff285b7c),
  Color(0xff743583),
  Color(0xff285e55),
  Color(0xff70502c),
  Color(0xff65448a),
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
  AcademicScheduleAppearance appearance = const AcademicScheduleAppearance(),
}) {
  final slot = index % academicScheduleCellPalettes.length;
  final palette = academicScheduleCellPalettes[slot];
  final style = appearance.style;
  final canvas =
      (dark ? appearance.darkBackground : appearance.lightBackground) ??
      (dark ? const Color(0xff181a1c) : const Color(0xfff7f6fa));
  AcademicScheduleCellColors finish(Color fill, Color text, Color outline) {
    final opacity =
        style.cellOpacity * (nonCurrent ? style.nonCurrentOpacity : 1);
    final composite = Color.alphaBlend(fill.withValues(alpha: opacity), canvas);
    final background =
        appearance.backgroundImage(dark) == null
            ? composite
            : fill.withValues(alpha: opacity);
    final ink = style.ink(ScheduleInk.course, dark);
    final a = composite.computeLuminance();
    final b = text.computeLuminance();
    final contrast = ((a > b ? a : b) + .05) / ((a > b ? b : a) + .05);
    final foreground =
        ink == null
            ? (contrast >= 4.5 ? text : readableScheduleForeground(composite))
            : style.tintCourseText
            ? Color.alphaBlend(ink, fill)
            : ink;
    final border =
        style.borderUsesCourseColor
            ? outline
            : style.ink(ScheduleInk.border, dark) ?? outline;
    return AcademicScheduleCellColors(background, foreground, border);
  }

  if (nonCurrent) {
    return dark
        ? finish(
          const Color(0xff252a32),
          const Color(0xffa2abb8),
          const Color(0xff343b46),
        )
        : finish(
          const Color(0xffe4e7ec),
          const Color(0xff5e6875),
          const Color(0xffd5dae1),
        );
  }
  final custom = (dark ? appearance.darkColors : appearance.lightColors)[slot];
  final classic = appearance.palette == AcademicSchedulePalette.classic;
  final sunset = appearance.palette == AcademicSchedulePalette.sunset;
  final background =
      custom ??
      (dark
          ? (classic
              ? Color.lerp(
                _classicDarkBackgrounds[slot],
                _classicForegrounds[slot],
                .15,
              )!
              : sunset
              ? Color.lerp(
                const Color(0xff191518),
                _sunsetForegrounds[slot],
                .42,
              )!
              : palette.$2)
          : (classic
              ? _classicBackgrounds[slot]
              : sunset
              ? _sunsetBackgrounds[slot]
              : palette.$1));
  final foreground =
      custom != null
          ? readableScheduleForeground(background)
          : dark
          ? Color.lerp(
            classic
                ? _classicBackgrounds[slot]
                : sunset
                ? _sunsetBackgrounds[slot]
                : palette.$1,
            Colors.white,
            .1,
          )!
          : (classic
              ? _classicForegrounds[slot]
              : sunset
              ? _sunsetForegrounds[slot]
              : _oceanForegrounds[slot]);
  final border = Color.lerp(background, foreground, dark ? .24 : .16)!;
  return finish(background, foreground, border);
}

/// Opaque custom fills always receive the more readable black/white foreground.
Color readableScheduleForeground(Color background) =>
    background.computeLuminance() > .179 ? Colors.black : Colors.white;
