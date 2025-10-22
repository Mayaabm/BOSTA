from django.contrib.gis.geos import Point
from django.utils import timezone
from rest_framework.decorators import api_view
from rest_framework.response import Response
from .models import VehiclePosition, Trip, Route, Bus
from datetime import timedelta
from django.contrib.gis.measure import D  
from django.contrib.gis.db.models.functions import Distance
from django.db.models import OuterRef, Subquery
from django.db.models.functions import Coalesce
from .serializers import BusNearbySerializer


def compute_eta(bus_pos, target_point, avg_speed_m_per_s=10.0):
    """
    Compute ETA (minutes) between a bus's VehiclePosition and a target point.
    This function can be safely called from anywhere (no HTTP required).
    """
    if not bus_pos or not bus_pos.location:
        return None

    # Since bus_pos.location is a geography field, .distance() returns meters.
    distance_m = bus_pos.location.distance(target_point)
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

    # Since bus_point is a geography field, .distance() correctly returns meters.
    distance_m = bus_point.distance(target_point)

    # Estimate average speed (e.g., 10 m/s ~ 36 km/h)
    # Use the bus's last reported speed, with a fallback.
    avg_speed_m_per_s = bus_pos.speed_mps if bus_pos.speed_mps and bus_pos.speed_mps > 0 else 10.0
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
    """
    Returns a list of buses near the given latitude and longitude.
    This is now optimized to query the Bus model directly, which is updated
    by the simulation script.
    """
    lat = float(request.query_params.get('lat'))
    lon = float(request.query_params.get('lon'))
    radius = float(request.query_params.get('radius', 10000))  # meters

    user_location = Point(lon, lat, srid=4326)

    # Query the Bus model directly for current locations within the radius.
    # This is more efficient than iterating through all historical VehiclePosition records.
    active_buses = Bus.objects.filter(
        current_location__isnull=False,
        last_reported_at__gte=timezone.now() - timedelta(hours=2) # Only show recently updated buses
    ).annotate(
        distance_m=Distance('current_location', user_location)
    ).filter(
        distance_m__lte=radius
    ).order_by('distance_m')

    # Annotate the route name for each bus from its most recent trip
    latest_trip_subquery = Trip.objects.filter(
        bus=OuterRef('pk'),
        departure_time__lte=timezone.now()  # Only consider trips that have already departed
    ).order_by('-departure_time').values('route__name')[:1]
    buses_with_route = active_buses.annotate(route_name=Coalesce(Subquery(latest_trip_subquery), None))

    serializer = BusNearbySerializer(buses_with_route, many=True)
    return Response(serializer.data)



@api_view(['GET'])
def buses_to_destination(request):
    target_lat = float(request.query_params.get('lat'))
    target_lon = float(request.query_params.get('lon'))
    target_point = Point(target_lon, target_lat, srid=4326)

    # Find routes that pass near the destination
    routes = Route.objects.filter(geometry__dwithin=(target_point, D(m=200)))
    # Find active trips on these routes
    trips = Trip.objects.filter(route__in=routes).select_related('bus', 'route')

    data = []
    for trip in trips:
        try:
            # Get the latest position for the bus on this trip
            bus_pos = VehiclePosition.objects.filter(bus=trip.bus).latest('recorded_at')
            eta_minutes = compute_eta(bus_pos, target_point)
            data.append({
                "bus_id": str(trip.bus.id),
                "route": trip.route.name,
                "eta_min": eta_minutes,
                "current_lat": bus_pos.location.y,
                "current_lon": bus_pos.location.x,
            })
        except VehiclePosition.DoesNotExist:
            continue # Skip if this bus has no position data
    return Response(data)