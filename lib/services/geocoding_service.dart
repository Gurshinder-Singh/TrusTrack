import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

class GeocodingService {
  Future<LatLng?> geocodeAddress(String query) async {
    try {
      final q = query.trim();
      if (q.isEmpty) return null;

      final uri = Uri.https(
        'nominatim.openstreetmap.org',
        '/search',
        {
          'q': q,
          'format': 'json',
          'limit': '1',
        },
      );

      final res = await http.get(
        uri,
        headers: {
          'User-Agent': 'trusttrack/1.0',
        },
      ).timeout(const Duration(seconds: 10));

      if (res.statusCode != 200) return null;

      final data = jsonDecode(res.body);
      if (data is! List || data.isEmpty) return null;

      final first = data.first;
      final lat = double.tryParse(first['lat']?.toString() ?? '');
      final lon = double.tryParse(first['lon']?.toString() ?? '');

      if (lat == null || lon == null) return null;
      return LatLng(lat, lon);
    } catch (_) {
      return null;
    }
  }
}
