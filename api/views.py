from django.contrib.gis.geos import Point
from django.contrib.gis.db.models.functions import Distance
from django.utils import timezone
from rest_framework.decorators import api_view
from rest_framework.response import Response
from .models import VehiclePosition, Trip, Location,Route,User
from datetime import timedelta
from django.contrib.gis.measure import D  
from django.contrib.gis.db.models import GeometryField
from django.contrib.gis.db.models.functions import Distance, Cast


def compute_eta(bus_pos, target_point, avg_speed_m_per_s=10.0):
    """
    Compute ETA (minutes) between a bus position and a target point.
    This function can be safely called from anywhere (no HTTP required).
    """
    if not bus_pos or not bus_pos.location:
        return None

    # distance() returns degrees for SRID=4326 — convert roughly to meters
    distance_m = bus_pos.location.distance(target_point) * 100000
    eta_seconds = distance_m / avg_speed_m_per_s
    return round(eta_seconds / 60, 1)

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

    bus_point = bus_pos.location
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

@api_view(['GET'])
def buses_nearby(request):
    lat = float(request.query_params.get('lat'))
    lon = float(request.query_params.get('lon'))
    radius = float(request.query_params.get('radius', 1000))  # meters

    user_location = Point(lon, lat, srid=4326)
    print("🧭 USER LOCATION:", user_location)

    total_positions = VehiclePosition.objects.count()
    print("🚍 TOTAL VEHICLE POSITIONS:", total_positions)

    # ✅ Cast to GeographyField to match database column type
    latest_positions = (
        VehiclePosition.objects
        .annotate(geo=Cast('location', GeometryField()))
        .filter(recorded_at__gte=timezone.now() - timedelta(hours=2))
        .filter(geo__distance_lte=(user_location, D(m=radius)))  # compare as geography
        # Use `dwithin` for efficient, meter-based distance filtering
        .filter(location__dwithin=(user_location, D(m=radius)))
        .annotate(distance=Distance('location', user_location))
        .order_by('distance')
    )

    print("🎯 MATCHING POSITIONS COUNT:", latest_positions.count())

    data = []
    for pos in latest_positions:
        print("🚌 FOUND BUS:", pos.bus.plate_number, pos.location)
        # Match the structure expected by the Flutter Bus.fromJson factory
        data.append({
            "id": pos.bus.id,
            "plate_number": pos.bus.plate_number,
            "current_point": {
                "type": "Point",
                "coordinates": [pos.location.x, pos.location.y]
            },
            "speed_mps": pos.speed,
            "distance_m": round(pos.distance.m, 2),
            "route": pos.bus.route.name if hasattr(pos.bus, 'route') and pos.bus.route else None,
        })
    return Response(data)



@api_view(['GET'])
def buses_to_destination(request):
    target_lat = float(request.query_params.get('lat'))
    target_lon = float(request.query_params.get('lon'))
    target_point = Point(target_lon, target_lat, srid=4326)

    # Find routes near the destination
    routes = Route.objects.filter(geometry__distance_lte=(target_point, 200))
    trips = Trip.objects.filter(route__in=routes)
    buses = VehiclePosition.objects.filter(bus__in=trips.values('bus'))

    data = []
    for bus in buses:
        eta_minutes = compute_eta(bus, target_point)
        data.append({
            "bus_id": bus.bus_id,
            "route": bus.bus.trips.first().route.name if bus.bus.trips.exists() else None,
            "eta_min": eta_minutes,
            "current_lat": bus.location.y,
            "current_lon": bus.location.x,
        })
    return Response(data)