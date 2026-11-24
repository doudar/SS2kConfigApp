import 'dart:convert';

import 'package:http/http.dart' as http;
import '../utils/workout/ride_map.dart';

/// Photon place search is only called when a rider submits a city or town.
Future<List<MapCenter>> searchRideMapPlaces(String query) async {
  final url = Uri.https('photon.komoot.io', '/api/', {
    'q': query,
    'layer': 'city',
    'limit': '5',
  });
  // Photon rejects the generic dart:io user agent. Identify the app and
  // provide its public project URL so the service can contact the maintainer.
  final response = await http
      .get(
        url,
        headers: {
          'User-Agent':
              'SmartSpin2k/2.0 (+https://github.com/doudar/SS2kConfigApp)',
        },
      )
      .timeout(const Duration(seconds: 10));
  if (response.statusCode != 200) {
    throw const FormatException('Place search unavailable');
  }
  final json = jsonDecode(utf8.decode(response.bodyBytes)) as Map;
  final results = <MapCenter>[];
  for (final feature in json['features'] as List) {
    final props = feature['properties'];
    final coords = feature['geometry']?['coordinates'];
    if (props is! Map ||
        props['name'] is! String ||
        coords is! List ||
        coords.length < 2) {
      continue;
    }
    final label = [
      props['name'],
      props['state'],
      props['country'],
    ].whereType<String>().where((s) => s.isNotEmpty).toSet().join(', ');
    final center = RideMapSettings.parseCenter(label, coords[1], coords[0]);
    if (center != null && !results.contains(center)) results.add(center);
  }
  return results;
}
