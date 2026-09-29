import 'package:flutter/material.dart';

import '../apps/app.dart';
import '../capabilities/dev_visibility.dart';

const featureIconTileIconSize = 52.0;
const featureCatalogIconSize = 40.0;
const featureCatalogTileMinHeight = 68.0;
const featureIconTileRadius = 12.0;
const featureIconTileLabelGap = 8.0;
const featureIconTileVerticalPadding = 10.0;
const featureIconTileLayoutSafety = 2.0;

double featureIconTileDevBadgeSlotHeight(BuildContext context) {
  final textScale = MediaQuery.textScalerOf(context).scale(1);
  return (16 * textScale).clamp(20.0, 32.0).toDouble();
}

/// Shared compact launcher tile used by 首页常用功能 and the 功能 catalog.
///
/// The visual treatment intentionally stays independent from the surrounding
/// layout: callers may use a Wrap, GridView, or a responsive tablet grid while
/// the icon, label, and DEV marker remain consistent.
class FeatureIconTile extends StatelessWidget {
  final AppMetadata metadata;

  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final int maxLines;
  final bool reserveDevBadgeSpace;

  const FeatureIconTile({
    super.key,
    required this.metadata,

    required this.onTap,
    this.onLongPress,
    this.maxLines = 2,
    this.reserveDevBadgeSpace = false,
  });

  @override
  Widget build(BuildContext context) {
    final materialTheme = Theme.of(context);
    final iconBackground = materialTheme.colorScheme.secondaryContainer;
    final iconForeground = materialTheme.colorScheme.onSecondaryContainer;
    final labelStyle = materialTheme.textTheme.bodyMedium?.copyWith(
      fontWeight: FontWeight.w600,
      height: 1.25,
    );
    final badgeSlotVisible = reserveDevBadgeSpace || metadata.requiresDev;
    final badgeSlotHeight = featureIconTileDevBadgeSlotHeight(context);
    final content = Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: 2,
          vertical: featureIconTileVerticalPadding,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: iconBackground,
                borderRadius: BorderRadius.circular(featureIconTileRadius),
              ),
              child: SizedBox(
                width: featureIconTileIconSize,
                height: featureIconTileIconSize,
                child: Icon(metadata.icon, size: 26, color: iconForeground),
              ),
            ),
            const SizedBox(height: featureIconTileLabelGap),
            Text(
              metadata.name,
              maxLines: maxLines,
              overflow: TextOverflow.ellipsis,
              softWrap: true,
              textAlign: TextAlign.center,
              style: labelStyle,
            ),
            if (badgeSlotVisible)
              SizedBox(
                height: badgeSlotHeight,
                child:
                    metadata.requiresDev
                        ? const Align(
                          alignment: Alignment.topCenter,
                          child: DevBadge(),
                        )
                        : const SizedBox.shrink(),
              ),
          ],
        ),
      ),
    );

    final semanticLabel =
        metadata.requiresDev ? '${metadata.name}，开发功能' : metadata.name;

    final colors = materialTheme.colorScheme;
    return Semantics(
      container: true,
      excludeSemantics: true,
      button: true,
      label: semanticLabel,
      onTap: onTap,
      onLongPress: onLongPress,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          borderRadius: BorderRadius.circular(featureIconTileRadius),
          overlayColor: WidgetStateProperty.resolveWith<Color?>((states) {
            if (states.contains(WidgetState.pressed)) {
              return colors.primary.withValues(alpha: 0.12);
            }
            if (states.contains(WidgetState.hovered) ||
                states.contains(WidgetState.focused)) {
              return colors.primary.withValues(alpha: 0.08);
            }
            return Colors.transparent;
          }),
          child: content,
        ),
      ),
    );
  }
}

const featureCatalogCardRadius = featureIconTileRadius;

/// Compact catalog card used by the 功能 page.
///
/// It intentionally omits development badges: DEV entries are grouped under
/// the dedicated DEV section, while the homepage and management surfaces keep
/// their existing development markers.
class FeatureCatalogCard extends StatelessWidget {
  final AppMetadata metadata;

  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final int maxLines;

  const FeatureCatalogCard({
    super.key,
    required this.metadata,

    required this.onTap,
    this.onLongPress,
    this.maxLines = 2,
  });

  @override
  Widget build(BuildContext context) {
    return _buildMaterial(context);
  }

  Widget _buildMaterial(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(featureCatalogCardRadius),
      side: BorderSide(color: colors.outlineVariant.withValues(alpha: 0.36)),
    );
    return Semantics(
      container: true,
      excludeSemantics: true,
      button: true,
      label: metadata.name,
      hint: onLongPress == null ? null : '长按查看功能详情',
      onTap: onTap,
      onLongPress: onLongPress,
      child: Card(
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        elevation: 0,
        color: colors.surfaceContainerLowest,
        surfaceTintColor: Colors.transparent,
        shape: shape,
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          borderRadius: BorderRadius.circular(featureCatalogCardRadius),
          overlayColor: WidgetStateProperty.resolveWith<Color?>((states) {
            if (states.contains(WidgetState.pressed)) {
              return colors.primary.withValues(alpha: 0.12);
            }
            if (states.contains(WidgetState.hovered) ||
                states.contains(WidgetState.focused)) {
              return colors.primary.withValues(alpha: 0.08);
            }
            return Colors.transparent;
          }),
          child: _content(
            context,
            iconBackground: colors.secondaryContainer,
            iconForeground: colors.onSecondaryContainer,
            labelStyle: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
              height: 1.25,
            ),
          ),
        ),
      ),
    );
  }

  Widget _content(
    BuildContext context, {
    required Color iconBackground,
    required Color iconForeground,
    required TextStyle? labelStyle,
  }) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: featureCatalogTileMinHeight),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: iconBackground,
                borderRadius: BorderRadius.circular(featureIconTileRadius),
              ),
              child: SizedBox(
                width: featureCatalogIconSize,
                height: featureCatalogIconSize,
                child: Icon(metadata.icon, size: 21, color: iconForeground),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                metadata.name,
                maxLines: maxLines,
                overflow: TextOverflow.ellipsis,
                softWrap: true,
                style: labelStyle,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
