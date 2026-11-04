import 'dart:core';

import 'package:flutter/material.dart';

class CategoryIconCircle extends StatelessWidget {
  final String? iconEmoji;
  final IconData? iconDataFromDefaultIconSet;
  final Color? backgroundColor;
  final IconData? overlayIcon;
  final IconData? topOverlayIcon;
  final String? topOverlayEmoji;
  final Color? topOverlayBackgroundColor;

  /// Small badge on the top-left corner (e.g. records entered by hand).
  final IconData? badgeIcon;
  final Color? badgeColor;
  final double mainIconSize;
  final double overlayIconSize;
  final double circleSize;

  CategoryIconCircle({
    this.iconEmoji,
    this.iconDataFromDefaultIconSet,
    this.backgroundColor,
    this.overlayIcon = null,
    this.topOverlayIcon = null,
    this.topOverlayEmoji,
    this.topOverlayBackgroundColor,
    this.badgeIcon,
    this.badgeColor,
    this.mainIconSize = 20.0,
    this.overlayIconSize = 15.0,
    this.circleSize = 40.0,
  });

  // Helper function to build the main icon container
  Widget _buildMainIcon(
      BuildContext context, Color? iconColor, Color backgroundColor) {
    return Container(
      width: circleSize,
      height: circleSize,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: backgroundColor,
      ),
      child: iconEmoji != null
            ?
            Center(
              child: Text(
                iconEmoji!, // Display the emoji
                style: TextStyle(
                  fontSize: mainIconSize, // Adjust the emoji size
                ),
              ),
            )
            : Icon(
          iconDataFromDefaultIconSet, // Fallback to the icon
          size: mainIconSize,
          color: iconColor ?? Theme.of(context).colorScheme.onSurface,
        ),
    );
  }

  // Helper function to build the bottom-right overlay icon container
  Widget _buildOverlayIcon(
      BuildContext context, IconData overlayIcon, bool iconBackground) {
    return Transform.translate(
      offset: Offset(circleSize - 10, circleSize - 16),
      child: Container(
        width: circleSize / 2,
        height: circleSize / 2,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: iconBackground
              ? Theme.of(context).colorScheme.surface
              : Theme.of(context).colorScheme.surfaceContainer.withValues(alpha: 0.8),
        ),
        child: Icon(
          overlayIcon,
          size: overlayIconSize,
          color: Theme.of(context).colorScheme.onSurface,
        ),
      ),
    );
  }

  // Helper function to build the top-right overlay icon container (symmetric to bottom)
  Widget _buildTopOverlayIcon(
      BuildContext context, IconData? overlayIcon, String? overlayEmoji,
      bool iconBackground) {
    final hasCustomBackground = topOverlayBackgroundColor != null;
    return Transform.translate(
      offset: Offset(circleSize - 10, -(circleSize / 2 - 16)),
      child: Container(
        width: circleSize / 2,
        height: circleSize / 2,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: topOverlayBackgroundColor ??
              (iconBackground
                  ? Theme.of(context).colorScheme.surface
                  : Theme.of(context)
                      .colorScheme
                      .surfaceContainer
                      .withValues(alpha: 0.8)),
        ),
        child: overlayEmoji != null
            ? Center(
                child: Text(overlayEmoji,
                    style: TextStyle(fontSize: overlayIconSize)),
              )
            : Icon(
                overlayIcon,
                size: overlayIconSize,
                color: hasCustomBackground
                    ? Colors.white
                    : Theme.of(context).colorScheme.onSurface,
              ),
      ),
    );
  }

  // Main function for building icons with or without overlays
  Widget _buildLeadingIcon(BuildContext context,
      {IconData? overlayIcon, IconData? topOverlayIcon}) {
    var iconColor = iconEmoji == null
        ? (backgroundColor != null
            ? Colors.white
            : Theme.of(context).colorScheme.onSurface)
        : Theme.of(context).colorScheme.onSurface;
    return Stack(
      children: [
        _buildMainIcon(
          context,
          iconColor,
          backgroundColor ?? Theme.of(context).colorScheme.surface,
        ),
        if (overlayIcon != null)
          _buildOverlayIcon(context, overlayIcon, backgroundColor != null),
        if (topOverlayIcon != null || topOverlayEmoji != null)
          _buildTopOverlayIcon(context, topOverlayIcon, topOverlayEmoji,
              backgroundColor != null),
        if (badgeIcon != null) _buildBadge(context),
      ],
    );
  }

  Widget _buildBadge(BuildContext context) {
    final size = circleSize * 0.42;
    return Transform.translate(
      offset: Offset(-size / 4, -size / 4),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: badgeColor ?? Theme.of(context).colorScheme.tertiary,
          border: Border.all(
              color: Theme.of(context).colorScheme.surface, width: 1.5),
        ),
        child: Icon(badgeIcon,
            size: size * 0.6,
            color: badgeColor != null
                ? Colors.white
                : Theme.of(context).colorScheme.onTertiary),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return _buildLeadingIcon(context,
        overlayIcon: overlayIcon, topOverlayIcon: topOverlayIcon);
  }
}
