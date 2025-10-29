# api/utils.py
import math
from typing import List, Tuple, Optional
from .models import Stop, Route, Bus

EARTH_R_KM = 6371.0

def haversine(lat1, lon1, lat2, lon2):
    phi1 = math.radians(lat1); phi2 = math.radians(lat2)
    dphi = math.radians(lat2 - lat1); dlmb = math.radians(lon2 - lon1)
    a = math.sin(dphi/2)**2 + math.cos(phi1)*math.cos(phi2)*math.sin(dlmb/2)**2
    return 2 * EARTH_R_KM * math.asin(math.sqrt(a))

def compute_cumulative_km(route: Route):
    stops = list(route.stops.order_by('order'))
    total = 0.0
    prev = None
    for s in stops:
        if prev:
            total += haversine(prev.latitude, prev.longitude, s.latitude, s.longitude)
        s.cum_km = round(total, 5)
        s.save(update_fields=['cum_km'])
        prev = s

def nearest_stop(route: Route, lat: float, lon: float) -> Tuple[Stop, float]:
    best = None; best_d = 1e9
    for s in route.stops.all():
        d = haversine(lat, lon, s.latitude, s.longitude)
        if d < best_d:
            best, best_d = s, d
    return best, best_d  # km

def eta_minutes(distance_km: float, kmh: Optional[float]) -> int:
    speed = kmh if kmh and kmh > 3 else 18.0  # fall back to ~18 km/h
    minutes = (distance_km / speed) * 60.0
    return max(1, int(round(minutes)))

def segment_km_between(route: Route, a: Stop, b: Stop) -> float:
    # assumes forward direction (a.order <= b.order). If reversed, swap.
    if a.order > b.order:
        a, b = b, a
    return max(0.0, b.cum_km - a.cum_km)
