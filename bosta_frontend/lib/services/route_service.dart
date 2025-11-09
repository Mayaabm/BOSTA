import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/route_model.dart';
import 'api_endpoints.dart';

class RouteService {
  static Future<List<AppRoute>> getRoutes() async {
    final url = Uri.parse(ApiEndpoints.routes);
    final response = await http.get(url);

    if (response.statusCode == 200) {
      List<dynamic> data = json.decode(response.body);
      return data.map((json) => AppRoute.fromJson(json)).toList();
    } else {
      throw Exception('Failed to load routes');
    }
  }

  static Future<AppRoute> getRouteById(String id) async {
    // The backend endpoint for a single route is the same as the list, with an ID query param.
    final url = Uri.parse('${ApiEndpoints.routes}?id=$id');
    final response = await http.get(url);

    if (response.statusCode == 200) {
      dynamic data = json.decode(response.body);
      return AppRoute.fromJson(data);
    } else {
      throw Exception('Failed to load route with id $id');
    }
  }
}