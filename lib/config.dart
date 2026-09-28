import 'package:flutter/material.dart';

const String kBaseUrl = 'https://securlink.securlav.it';
const String kAppVersion = '1.0.0';

const Color kBrand = Color(0xFF1E40AF);
const Color kBrandSoft = Color(0xFFEEF4FF);
const Color kOk = Color(0xFF047857);
const Color kErrore = Color(0xFFB91C1C);
const Color kAmbra = Color(0xFFB45309);

/// Target bitrate for recorded video: the same the web dashboard uses, so a
/// clip of about a minute fits within the server upload limit.
const int kVideoBitrate = 1200000;
const int kAudioBitrate = 64000;
