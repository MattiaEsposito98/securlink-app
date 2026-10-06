import 'package:flutter/material.dart';

/// Address of the Securlink 2.0 server. For tests on the dev server:
/// `flutter run --dart-define=SECURLINK_URL=http://192.168.1.50:5174`
const String kBaseUrl = String.fromEnvironment('SECURLINK_URL', defaultValue: 'https://securlink.securlav.it');
const String kAppVersion = '1.0.0';

// Securlink logo colours.
const Color kBrand = Color(0xFF014488);
const Color kArancio = Color(0xFFF07D00);
const Color kBrandSoft = Color(0xFFE8EFF7);
const Color kOk = Color(0xFF047857);
const Color kErrore = Color(0xFFB91C1C);
const Color kAmbra = Color(0xFFB45309);

/// Target bitrate for recorded video: the same the web dashboard uses, so a
/// clip of about a minute fits within the server upload limit.
const int kVideoBitrate = 1200000;
const int kAudioBitrate = 64000;
