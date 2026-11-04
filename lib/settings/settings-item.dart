import 'package:flutter/material.dart';
import 'package:aupp/settings/style.dart';

class SettingsItem extends StatelessWidget {
  final Icon icon;
  final String title;
  final Function? onPressed;

  final String? subtitle;

  /// Shown under [subtitle], for what doesn't fit in a line of text.
  final Widget? details;
  final Widget? trailing;
  final Color? iconBackgroundColor;

  SettingsItem(
      {this.iconBackgroundColor,
      required this.icon,
      required this.title,
      required this.onPressed,
      this.subtitle,
      this.details,
      this.trailing});

  @override
  Widget build(BuildContext context) {
    final subtitleText =
        subtitle == null ? null : Text(subtitle!, style: subtitleTextStyle);
    return RawMaterialButton(
      child: ListTile(
        leading: CircleAvatar(
            backgroundColor:
                iconBackgroundColor == null ? Colors.blue : iconBackgroundColor,
            child: icon),
        title: Text(title, style: titleTextStyle),
        subtitle: details == null
            ? subtitleText
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [if (subtitleText != null) subtitleText, details!],
              ),
        trailing: trailing,
      ),
      onPressed: onPressed as void Function()?,
    );
  }
}

/// A [SettingsItem] with a switch: tapping anywhere on the row toggles it.
class SettingsSwitchItem extends StatelessWidget {
  final Icon icon;
  final Color iconBackgroundColor;
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const SettingsSwitchItem(
      {super.key,
      required this.icon,
      required this.iconBackgroundColor,
      required this.title,
      this.subtitle,
      required this.value,
      required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return SettingsItem(
      icon: icon,
      iconBackgroundColor: iconBackgroundColor,
      title: title,
      subtitle: subtitle,
      trailing: Switch(value: value, onChanged: onChanged),
      onPressed: () => onChanged(!value),
    );
  }
}
