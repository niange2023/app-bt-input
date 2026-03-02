import 'package:flutter/material.dart';

String tr(BuildContext context, {required String zh, required String en}) {
  final languageCode = Localizations.localeOf(context).languageCode.toLowerCase();
  return languageCode.startsWith('zh') ? zh : en;
}
