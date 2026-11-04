import 'package:flutter/material.dart';

/// The picture of each month on the Início and the Extrato.
class BannerImageService {
  BannerImageService._();

  static String monthAssetName(int monthIndex) {
    final fileName = (monthIndex > 0 && monthIndex <= 12)
        ? monthIndex.toString()
        : 'default';
    return 'assets/images/bkg-$fileName.png';
  }

  /// Shifted by 6 months: the pictures follow the seasons of the Northern
  /// Hemisphere, and the app is used in Brazil.
  static int displayMonth(int monthIndex) {
    if (monthIndex < 1 || monthIndex > 12) return monthIndex;
    return ((monthIndex + 5) % 12) + 1;
  }

  /// The picture for the given month (1-12).
  static ImageProvider getBannerImage(int monthIndex) =>
      AssetImage(monthAssetName(displayMonth(monthIndex)));
}
