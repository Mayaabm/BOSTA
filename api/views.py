from django.contrib.gis.geos import Point
from django.contrib.gis.db.models.functions import Distance
from django.utils import timezone
from rest_framework.decorators import api_view
from rest_framework.response import Response
from .models import VehiclePosition, Trip, Location
from datetime import timedelta

@api_view(['GET'])
def eta(request):
    """
    Estimate time (in minutes) for a bus to reach a target location.
    Query params: bus_id, target_lat, target_lon
    """
    bus_id = request.query_params.get('bus_id')
    target_lat = request.query_params.get('target_lat')
    target_lon = request.query_params.get('target_lon')

    if not (bus_id and target_lat and target_lon):
        return Response({"error": "bus_id, target_lat, and target_lon are required"}, status=400)

    try:
        bus_pos = VehiclePosition.objects.filter(bus_id=bus_id).latest('recorded_at')
    except VehiclePosition.DoesNotExist:
        return Response({"error": "No recent position for this bus"}, status=404)

    bus_point = bus_pos.position
    target_point = Point(float(target_lon), float(target_lat), srid=4326)

    # Estimate direct distance in meters
    distance_m = bus_point.distance(target_point) * 100000  # roughly meters

    # Estimate average speed (e.g., 10 m/s ~ 36 km/h)
    avg_speed_m_per_s = 10.0

    eta_seconds = distance_m / avg_speed_m_per_s
    eta_minutes = round(eta_seconds / 60, 1)

    data = {
        "bus_id": bus_id,
        "distance_m": round(distance_m, 1),
        "estimated_arrival_minutes": eta_minutes,
        "last_reported": bus_pos.recorded_at,
    }

    return Response(data)
