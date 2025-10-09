# api/views.py
from rest_framework.decorators import api_view
from rest_framework.response import Response
from rest_framework.exceptions import ValidationError
from .services.geo import nearest_stops, nearby_buses
from .serializers import LocationNearbySerializer, BusNearbySerializer

def _parse_ll(request):
    try:
        lat = float(request.query_params.get("lat"))
        lon = float(request.query_params.get("lon"))
    except (TypeError, ValueError):
        raise ValidationError("lat and lon are required floats")
    radius_m = int(request.query_params.get("r", 600))
    return lat, lon, radius_m

@api_view(["GET"])
def stops_nearby_view(request):
    lat, lon, r = _parse_ll(request)
    qs = nearest_stops(lat, lon, radius_m=r)
    data = LocationNearbySerializer(qs, many=True).data
    return Response(data)

@api_view(["GET"])
def buses_nearby_view(request):
    lat, lon, r = _parse_ll(request)
    qs = nearby_buses(lat, lon, radius_m=r)
    data = BusNearbySerializer(qs, many=True).data
    return Response(data)
