# api/utils.py
import math
import json
import os
import threading
from typing import List, Tuple, Optional, Dict, Any
from django.conf import settings
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


# --- GeoJSON-based nearest-stop lookup (cached) ---
_GEOJSON_STOPS: Optional[List[Dict[str, Any]]] = None
_GEOJSON_LOCK = threading.Lock()

def _load_geojson_stops() -> List[Dict[str, Any]]:
    global _GEOJSON_STOPS
    if _GEOJSON_STOPS is not None:
        return _GEOJSON_STOPS
    with _GEOJSON_LOCK:
        if _GEOJSON_STOPS is not None:
            return _GEOJSON_STOPS
        # Try to find the bus_stops.geojson in the repository routes/ folder
        geojson_path = os.path.join(getattr(settings, 'BASE_DIR', '.'), 'routes', 'bus_stops.geojson')
        if not os.path.exists(geojson_path):
            _GEOJSON_STOPS = []
            return _GEOJSON_STOPS
        with open(geojson_path, 'r', encoding='utf-8') as fh:
            data = json.load(fh)
        features = data.get('features', []) if isinstance(data, dict) else []
        out = []
        for feat in features:
            try:
                coords = feat.get('geometry', {}).get('coordinates', [])
                # GeoJSON coordinate order may be [lon, lat] or [x, y]; this dataset appears [lon, lat]
                lon, lat = float(coords[0]), float(coords[1])
                out.append({'lat': lat, 'lon': lon, 'properties': feat.get('properties', {}), 'feature': feat})
            except Exception:
                continue
        _GEOJSON_STOPS = out
        return _GEOJSON_STOPS


def nearest_geojson_stop(lat: float, lon: float, max_km: Optional[float] = None) -> Optional[Dict[str, Any]]:
    """
    Find the nearest stop from `routes/bus_stops.geojson` to the given lat/lon.
    Returns a dict with keys: 'lat','lon','properties','distance_km' or None if no stops available.
    """
    stops = _load_geojson_stops()
    if not stops:
        return None
    best = None
    best_d = float('inf')
    for s in stops:
        d = haversine(lat, lon, s['lat'], s['lon'])
        if d < best_d:
            best = s; best_d = d
    if best is None:
        return None
    if max_km is not None and best_d > max_km:
        return None
    res = dict(best)
    res['distance_km'] = best_d
    return res

def eta_minutes(distance_km: float, kmh: Optional[float]) -> int:
    speed = kmh if kmh and kmh > 3 else 18.0  # fall back to ~18 km/h
    minutes = (distance_km / speed) * 60.0
    return max(1, int(round(minutes)))

def segment_km_between(route: Route, a: Stop, b: Stop) -> float:
    # assumes forward direction (a.order <= b.order). If reversed, swap.
    if a.order > b.order:
        a, b = b, a
    return max(0.0, b.cum_km - a.cum_km)
