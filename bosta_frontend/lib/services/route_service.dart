import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/app_route.dart';
import 'api_endpoints.dart';

class RouteService {
  static Future<List<AppRoute>> getRoutes() async {
    final url = Uri.parse(ApiEndpoints.allRoutes);
    final response = await http.get(url);

    if (response.statusCode == 200) {
      List<dynamic> data = json.decode(response.body);
      return data.map((json) => AppRoute.fromJson(json)).toList();
    } else {
      throw Exception('Failed to load routes');
    }
  }

  static Future<AppRoute> getRouteById(String id) async {
    // The backend endpoint for a single route is typically /api/routes/{id}/
    final url = Uri.parse(ApiEndpoints.routeDetails(id));
    final response = await http.get(url);

    if (response.statusCode == 200) {
      // The response for a single item might not be a list.
      // It's safer to decode and let the fromJson handle the map.
      final data = json.decode(response.body);
      // Ensure data is a Map before passing to fromJson
      return AppRoute.fromJson(Map<String, dynamic>.from(data as Map));
    } else {
      throw Exception('Failed to load route with id $id');
    }
  }
}