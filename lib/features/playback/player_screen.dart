import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

import '../../core/api/api_exception.dart';
import '../auth/session.dart';
import '../../core/theme.dart';
import '../../core/widgets/common.dart';
import '../catalog/models.dart';
import 'playback.dart';

class StreamSource {
  const StreamSource({required this.provider, required this.name, required this.url});

  factory StreamSource.fromJson(Map<String, dynamic> json) => StreamSource(
    provider: json['provider'] as String? ?? '',
    name: json['name'] as String? ?? '',
    url: json['url'] as String? ?? '',
  );

  final String provider;
  final String name;
  final String url;
}

/// A provider the sources panel offers, as declared by the API.
class SourceProvider {
  const SourceProvider({required this.id, required this.name});

  factory SourceProvider.fromJson(Map<String, dynamic> json) =>
      SourceProvider(id: json['id'] as String? ?? '', name: json['name'] as String? ?? '');

  final String id;
  final String name;
}

/// Shown while the API's provider list is still loading, so the panel is never empty.
const kSourceProvidersFallback = <SourceProvider>[
  SourceProvider(id: 'tmdb-fr', name: 'TMDB Français (Onyx)'),
  SourceProvider(id: 'coflix', name: 'Coflix'),
  SourceProvider(id: 'aplouf', name: 'Aplouf'),
  SourceProvider(id: 'frenchstream', name: 'FrenchStream'),
  SourceProvider(id: 'frembed', name: 'Frembed'),
  SourceProvider(id: '1jour1film', name: '1Jour1Film'),
];
