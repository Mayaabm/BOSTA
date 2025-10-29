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
}