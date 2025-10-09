# api/services/geo.py
from django.contrib.gis.geos import Point
from django.contrib.gis.measure import D
from django.contrib.gis.db.models.functions import Distance
from django.db.models import F
from api.models import Location, Bus

def nearest_stops(lat: float, lon: float, radius_m: int = 600, limit: int = 20):
    p = Point(lon, lat, srid=4326)
    return (
        Location.objects
        .filter(point__distance_lte=(p, D(m=radius_m)))
        .annotate(distance_m=Distance('point', p))
        .order_by('distance_m')[:limit]
    )

def nearby_buses(lat: float, lon: float, radius_m: int = 1500, limit: int = 50):
    p = Point(lon, lat, srid=4326)
    return (
        Bus.objects
        .filter(current_point__distance_lte=(p, D(m=radius_m)))
        .annotate(distance_m=Distance('current_point', p))
        .order_by('distance_m')[:limit]
    )
