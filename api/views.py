from django.contrib.gis.geos import Point
from django.utils import timezone
from rest_framework.decorators import api_view, permission_classes
from rest_framework import generics, status
from rest_framework.response import Response
from rest_framework.views import APIView
from .models import VehiclePosition, Trip, Route, Bus, CustomUserProfile, Stop
from .utils import nearest_geojson_stop
from datetime import timedelta
import datetime
from django.contrib.auth.models import User
from django.contrib.gis.measure import D  
from django.contrib.gis.db.models.functions import Distance
from django.db.models import OuterRef, Subquery, Q
from django.db.models.functions import Coalesce, Cast
from .serializers import BusNearbySerializer, RouteSerializer, TripSerializer
from django.contrib.auth import authenticate
from rest_framework.permissions import IsAuthenticated
import logging
from django.conf import settings
import threading
import time
import math
import json
import os
from django.utils import timezone as dj_timezone
from .models import Stop
 
logger = logging.getLogger(__name__)


def _masked_token_from_request(req):
    auth = req.META.get('HTTP_AUTHORIZATION') or req.META.get('Authorization')
    if not auth:
        return None
    try:
        parts = auth.split()
        if len(parts) >= 2:
            tok = parts[1]
            return tok[:8] + '...' if len(tok) > 8 else tok
    except Exception:
        return None
    return None


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
    
    if distance_m <= 10: # If bus is very close, consider it arrived.
        return 0
        
    # Return total minutes, ensuring it's at least a small fraction to avoid 0.
    # This is useful for sorting or simple displays.
    eta_minutes = max(0.1, eta_seconds / 60)
    return round(eta_minutes, 1)


@api_view(['GET'])
def eta(request):
    """
    Compute ETA from driver's current position to rider's location.
    Query params: bus_id (required), target_lat (rider lat), target_lon (rider lon)
    Returns ETA in minutes and structured format (hours/minutes/seconds).
    """
    bus_id = request.query_params.get('bus_id')
    target_lat = request.query_params.get('target_lat')
    target_lon = request.query_params.get('target_lon')

    token_mask = _masked_token_from_request(request)
    logger.info(f"[ETA] Request: bus_id={bus_id}, token={token_mask}")

    if not (bus_id and target_lat and target_lon):
        logger.warning("[ETA] Missing required params")
        return Response({"error": "bus_id, target_lat, and target_lon are required"}, status=400)

    try:
        bus_pos = VehiclePosition.objects.filter(bus_id=bus_id).latest('recorded_at')
        logger.info(f"[ETA] Found bus position for {bus_id}: {bus_pos}")
    except VehiclePosition.DoesNotExist:
        logger.error(f"[ETA] No position found for bus_id={bus_id}")
        return Response({"error": "No recent position for this bus"}, status=404)

    bus_point = bus_pos.location
    target_point = Point(float(target_lon), float(target_lat), srid=4326)

    logger.info("[ETA CALCULATION START]")
    logger.info(f"[ETA] Computing ETA for bus_id={bus_id}; recent_position_id={getattr(bus_pos, 'id', None)}")

    # Since bus_point is a geography field, .distance() returns meters.
    distance_m = bus_pos.location.distance(target_point)
    logger.info(f"[ETA] Distance (m): {distance_m:.2f}")

    # Estimate average speed (e.g., 10 m/s ~ 36 km/h)
    # Use the bus's last reported speed, with a fallback.
    avg_speed_m_per_s = bus_pos.speed_mps if bus_pos.speed_mps and bus_pos.speed_mps > 0 else 10.0
    logger.info(f"[ETA] Bus speed (m/s): {avg_speed_m_per_s:.2f}")
    
    eta_seconds = distance_m / avg_speed_m_per_s
    logger.info(f"[ETA] ETA seconds: {eta_seconds:.2f}")
    
    # Deconstruct total seconds into hours, minutes, and seconds for a richer response
    if distance_m > 10:
        m, s = divmod(eta_seconds, 60)
        h, m = divmod(m, 60)
        eta_structured = {"hours": int(h), "minutes": int(m), "seconds": int(s)}
        logger.info(f"[ETA] Final ETA structured: {eta_structured}")
    else:
        eta_structured = {"hours": 0, "minutes": 0, "seconds": 0}
        logger.info(f"[ETA] Driver is very close (< 10m), ETA = 0")
        
    logger.info(f"[ETA CALCULATION END]")
        
    data = {
        "bus_id": bus_id,
        "distance_m": round(distance_m, 1),
        # Keep the old field for backward compatibility if needed, but add the new one.
        "estimated_arrival_minutes": round(eta_seconds / 60, 1) if distance_m > 10 else 0,
        "eta": eta_structured,
        "last_reported": bus_pos.recorded_at,
    }
    
    # Avoid logging sensitive location coordinates in response; log summarized fields only
    logger.info(f"[ETA] Response data summary: bus_id={data['bus_id']}, distance_m={data['distance_m']}, eta_minutes={data['estimated_arrival_minutes']}, last_reported={data['last_reported']}")
    return Response(data)


 

@api_view(['GET'])
def buses_nearby(request):
    """
    Returns a list of buses near the given latitude and longitude that are on active trips.
    Only shows drivers that are currently logged in and have an active trip (STATUS_STARTED).
    """
    
    token_mask = _masked_token_from_request(request)
    logger.info("\n--- BUSES NEARBY DEBUG ---")
    try:
        lat = float(request.query_params.get('lat'))
        lon = float(request.query_params.get('lon'))
        radius = float(request.query_params.get('radius', 10000))  # meters
        logger.info(f"[buses_nearby] Request received: radius={radius}m, token={token_mask}, remote_addr={request.META.get('REMOTE_ADDR')}")

        user_location = Point(lon, lat, srid=4326)

        recently_updated_buses = Bus.objects.filter(
            current_location__isnull=False,
            last_reported_at__gte=timezone.now() - timedelta(hours=2)
        )
        logger.info(f"[buses_nearby] Found {recently_updated_buses.count()} buses with a recent location.")

        buses_with_started_trip = recently_updated_buses.filter(
            trips__status=Trip.STATUS_STARTED
        ).distinct()
        logger.info(f"[buses_nearby] Found {buses_with_started_trip.count()} buses with a 'STARTED' trip.")
        if buses_with_started_trip.count() == 0:
            all_trips = Trip.objects.all().values('bus_id', 'status')
            logger.warning(f"[buses_nearby] No buses have a 'STARTED' trip. Current trip statuses count={len(list(all_trips))}")

        # Step 3: Annotate distance for the remaining buses.
        buses_with_distance = buses_with_started_trip.annotate(
            distance_m=Distance('current_location', user_location)
        )

        # Step 4: Filter by distance (radius).
        final_buses = buses_with_distance.filter(
            distance_m__lte=radius
        ).order_by('distance_m')
        logger.info(f"[buses_nearby] Found {final_buses.count()} buses within the {radius}m radius.")

        # Step 5: Annotate the route name for each bus from its active trip.
        latest_trip_subquery = Trip.objects.filter(
            bus=OuterRef('pk'),
            status=Trip.STATUS_STARTED
        ).order_by('-departure_time').values('route__name')[:1]
        buses_with_route = final_buses.annotate(route_name=Coalesce(Subquery(latest_trip_subquery), None))

        serializer = BusNearbySerializer(buses_with_route, many=True)
        logger.info(f"[buses_nearby] Serializing {len(serializer.data)} buses to return to the rider.")
        logger.info("--- BUSES NEARBY DEBUG (END) ---\n")
        return Response(serializer.data)

    except (ValueError, TypeError) as e:
        logger.error(f"[buses_nearby] Invalid input parameters: {e}")
        return Response({"error": "Invalid 'lat', 'lon', or 'radius' provided."}, status=status.HTTP_400_BAD_REQUEST)
    except Exception as e:
        logger.exception("[buses_nearby] An unexpected error occurred.")
        return Response({"error": "An internal error occurred."}, status=status.HTTP_500_INTERNAL_SERVER_ERROR)

@api_view(['GET'])
def buses_for_route(request):
    """
    Returns a list of all active buses assigned to a specific route.
    Query params: route_id
    """
    route_id = request.query_params.get('route_id')
    if not route_id:
        return Response({"error": "route_id is a required query parameter."}, status=400)

    # Find all active trips for the given route.
    # A trip is considered active if it has started but not yet finished.
    active_trips = Trip.objects.filter(
        route_id=route_id,
        status=Trip.STATUS_STARTED
    ).select_related('bus')

    # Extract the buses from these active trips.
    # We only want buses that have a recently updated location.
    buses = [
        trip.bus for trip in active_trips 
        if trip.bus and trip.bus.current_location is not None and trip.bus.last_reported_at > timezone.now() - timedelta(hours=2)
    ]

    serializer = BusNearbySerializer(buses, many=True)
    return Response(serializer.data)

@api_view(['GET'])
def route_list(request):
    """
    Returns a list of all routes, including their geometry and stops.
    """
    try:
        logger.info("route_list: request from %s, query_params=%s", request.META.get('REMOTE_ADDR'), request.query_params)
        # Dump some headers useful for debugging (mask Authorization tokens)
        hdrs = {}
        for k, v in request.META.items():
            if not k.startswith('HTTP_'):
                continue
            if 'AUTH' in k:
                try:
                    # mask token value
                    val = v.split()[1] if v and isinstance(v, str) and len(v.split()) > 1 else v
                    hdrs[k] = (val[:8] + '...') if isinstance(val, str) and len(val) > 8 else val
                except Exception:
                    hdrs[k] = '***masked***'
            else:
                hdrs[k] = v
        logger.debug("route_list: headers=%s", hdrs)

        routes = Route.objects.prefetch_related('stops').all()
        serializer = RouteSerializer(routes, many=True)

        logger.info("route_list: returning %d routes", len(serializer.data))
        return Response(serializer.data)
    except Exception as e:
        # Log exception with stacktrace
        logger.exception("route_list: unexpected error while serializing routes")
        # If DEBUG, return detailed error to help local debugging
        if settings.DEBUG:
            return Response({
                "error": "exception",
                "message": str(e),
                "trace": True,
            }, status=500)
        return Response({"error": "Could not load routes."}, status=500)


@api_view(['GET'])
def route_detail(request, route_id):
    """
    Returns the full details for a single route, including geometry and stops.
    This is used by the frontend when a driver selects a route so the UI
    can present start locations derived from the geometry or stops.
    """
    try:
        route = Route.objects.prefetch_related('stops').get(pk=route_id)
    except Route.DoesNotExist:
        return Response({"error": "Route not found."}, status=404)

    serializer = RouteSerializer(route)
    return Response(serializer.data)



@api_view(['GET'])
def nearest_stop_geojson(request):
    """
    Returns the nearest stop from the local `routes/bus_stops.geojson` file.
    Query params: `lat`, `lon`, optional `max_km` to filter by maximum distance (km).
    """
    try:
        lat_s = request.query_params.get('lat')
        lon_s = request.query_params.get('lon')
        if lat_s is None or lon_s is None:
            return Response({'error': 'lat and lon are required query params'}, status=400)
        lat = float(lat_s); lon = float(lon_s)
        max_km = request.query_params.get('max_km')
        max_km_f = float(max_km) if max_km is not None else None

        stop = nearest_geojson_stop(lat, lon, max_km=max_km_f)
        if not stop:
            return Response({'error': 'No nearby stop found'}, status=404)

        props = stop.get('properties', {})
        # Derive a friendly name from available properties
        name = props.get('stop_name') or props.get('route_name') or props.get('name') or None
        if not name:
            so = props.get('stop_order')
            name = f"stop {so}" if so is not None else None

        return Response({
            'name': name,
            'properties': props,
            'latitude': stop.get('lat'),
            'longitude': stop.get('lon'),
            'distance_km': round(stop.get('distance_km', 0.0), 6)
        })
    except ValueError:
        return Response({'error': 'Invalid numeric parameters'}, status=400)
    except Exception as e:
        logger.exception("nearest_stop_geojson: unexpected error")
        return Response({'error': 'internal error'}, status=500)


@api_view(['GET'])
def nearest_stops_for_destination(request):
    """
    New endpoint: Given a destination coordinate (dest_lat, dest_lon) and optionally
    the rider's current location (user_lat, user_lon), return:
      - a snapped destination (nearest known stop from geojson)
      - nearest destination stop(s) from the DB (top N)
      - nearest boarding stop(s) from the rider location (top N)

    Query params:
      dest_lat (required), dest_lon (required)
      user_lat (optional), user_lon (optional)
      n (optional, default 3)
    """
    try:
        dest_lat_s = request.query_params.get('dest_lat') or request.query_params.get('lat')
        dest_lon_s = request.query_params.get('dest_lon') or request.query_params.get('lon')
        if dest_lat_s is None or dest_lon_s is None:
            return Response({'error': 'dest_lat and dest_lon are required'}, status=400)
        dest_lat = float(dest_lat_s); dest_lon = float(dest_lon_s)

        n = int(request.query_params.get('n', 3))

        # Snap destination to nearest known stop from geojson (best effort)
        snapped = None
        try:
            snapped_raw = nearest_geojson_stop(dest_lat, dest_lon, max_km=None)
            if snapped_raw:
                snapped = {
                    'latitude': snapped_raw.get('lat'),
                    'longitude': snapped_raw.get('lon'),
                    'distance_km': round(snapped_raw.get('distance_km', 0.0), 6),
                    'properties': snapped_raw.get('properties', {})
                }
        except Exception:
            snapped = None

        # Find nearest stops in the DB to the destination coordinate
        dest_point = Point(dest_lon, dest_lat, srid=4326)
        dest_near_qs = Stop.objects.annotate(distance=Distance('location', dest_point)).order_by('distance')[:n]
        dest_nearest = []
        for s in dest_near_qs:
            dest_nearest.append({
                'id': s.id,
                'name': s.name,
                'route': s.route.name if s.route else None,
                'distance_m': round(getattr(s, 'distance').m if hasattr(getattr(s, 'distance'), 'm') else float(getattr(s, 'distance') or 0.0), 1),
                'latitude': s.location.y,
                'longitude': s.location.x,
            })

        boarding_nearest = []
        user_lat_s = request.query_params.get('user_lat')
        user_lon_s = request.query_params.get('user_lon')
        if user_lat_s and user_lon_s:
            user_lat = float(user_lat_s); user_lon = float(user_lon_s)
            user_point = Point(user_lon, user_lat, srid=4326)
            user_near_qs = Stop.objects.annotate(distance=Distance('location', user_point)).order_by('distance')[:n]
            for s in user_near_qs:
                boarding_nearest.append({
                    'id': s.id,
                    'name': s.name,
                    'route': s.route.name if s.route else None,
                    'distance_m': round(getattr(s, 'distance').m if hasattr(getattr(s, 'distance'), 'm') else float(getattr(s, 'distance') or 0.0), 1),
                    'latitude': s.location.y,
                    'longitude': s.location.x,
                })

        return Response({
            'snapped_destination': snapped,
            'destination_nearest_stops': dest_nearest,
            'boarding_nearest_stops': boarding_nearest,
        })
    except ValueError:
        return Response({'error': 'Invalid numeric parameters'}, status=400)
    except Exception:
        logger.exception('nearest_stops_for_destination: unexpected error')
        return Response({'error': 'internal error'}, status=500)

@api_view(['GET'])
def get_bus_details(request, bus_id):
    """
    Returns details for a single bus by its ID.
    """
    try:
        bus = Bus.objects.get(pk=bus_id)
    except Bus.DoesNotExist:
        return Response({"error": f"Bus with id {bus_id} not found."}, status=404)

    # Annotate with the latest route name
    latest_trip = Trip.objects.filter(bus=bus).order_by('-departure_time').first()
    bus.route_name = latest_trip.route.name if latest_trip and latest_trip.route else None
    
    # Add driver's name to the bus object for serialization
    if bus.driver and bus.driver.user:
        bus.driver_name = bus.driver.user.get_full_name() or bus.driver.user.username

    # Check for rider location to calculate ETA and distance
    rider_lat = request.query_params.get('lat')
    rider_lon = request.query_params.get('lon')

    if rider_lat and rider_lon and bus.current_location:
        rider_point = Point(float(rider_lon), float(rider_lat), srid=4326)
        distance_m = bus.current_location.distance(rider_point)
        
        # Use bus's speed or a default to calculate ETA
        avg_speed_m_per_s = bus.speed_mps if bus.speed_mps and bus.speed_mps > 1 else 8.0 # Fallback to ~30km/h
        eta_seconds = distance_m / avg_speed_m_per_s

        m, s = divmod(eta_seconds, 60)
        h, m = divmod(m, 60)
        eta_structured = {"hours": int(h), "minutes": int(m), "seconds": int(s)}

        # Add the calculated fields to the bus object before serialization
        bus.distance_m = distance_m
        bus.eta = eta_structured # This will be a temporary attribute

    serializer = BusNearbySerializer(bus)
    data = serializer.data
    # Manually add the eta structure if it was calculated
    if hasattr(bus, 'eta'):
        data['eta'] = bus.eta
    if hasattr(bus, 'driver_name'):
        data['driver_name'] = bus.driver_name
    return Response(data)

@api_view(['POST'])
def driver_login(request):
    """
    Authenticates a driver using email and password, then returns their assigned bus and route.
    """
    email = (request.data.get('email') or '').strip().lower()
    password = request.data.get('password')

    logger.warning("driver_login attempt for email=%s", email)

    if not email or not password:
        logger.warning("driver_login: missing email or password")
        return Response({"error": "Please enter both email and password."}, status=400)

    # Look up the user by email, then authenticate using their username so
    # email-based login works regardless of the authentication backend.
    try:
        user_obj = User.objects.get(email=email)
        logger.warning("driver_login: found user username=%s for email=%s", user_obj.username, email)
    except User.DoesNotExist:
        logger.warning("driver_login: no user found for email=%s", email)
        return Response({"error": "Invalid credentials.", "detail": "No user with that email"}, status=401)

    user = authenticate(request, username=user_obj.username, password=password)

    if user is None:
        logger.warning("driver_login: authentication failed for username=%s (email=%s)", getattr(user_obj, 'username', '<unknown>'), email)
        return Response({"error": "Invalid credentials.", "detail": "Wrong password for this user"}, status=401)

    try:
        # Verify the user has a driver profile
        driver_profile = user.profile
        if not driver_profile.is_driver:
            return Response({"error": "This user is not a driver."}, status=403)

        # Find the bus assigned to this driver (may not exist yet)
        bus = Bus.objects.filter(driver=driver_profile).first()
        latest_trip = Trip.objects.filter(bus=bus).order_by('-departure_time').first() if bus else None

        # It's OK if there are no trips yet for this bus. route_id will be null.
        route_id = str(latest_trip.route.id) if (latest_trip and latest_trip.route) else None

        # Generate JWT tokens using Simple JWT so frontend has a consistent token format
        try:
            from rest_framework_simplejwt.tokens import RefreshToken
            refresh = RefreshToken.for_user(user)
            access_token = str(refresh.access_token)
            refresh_token = str(refresh)
        except ImportError:
            # Fallback if rest_framework_simplejwt not installed - use a simple token
            import base64
            token_data = f"{user.id}:{user.username}:{timezone.now().isoformat()}"
            access_token = base64.b64encode(token_data.encode()).decode()
            refresh_token = access_token

        return Response({
            "access": access_token,
            "refresh": refresh_token,
            "driver_name": user.get_full_name() or user.username,
            "bus_id": str(bus.id) if bus else None,
            "route_id": route_id
        })
    except CustomUserProfile.DoesNotExist:
        return Response({"error": "Driver profile not found for this user."}, status=404)
    except Bus.DoesNotExist:
        return Response({"error": "No bus assigned to this driver."}, status=404)


@api_view(['POST'])
def rider_login(request):
    """
    Authenticates a rider (commuter) and returns JWT tokens on success.
    """
    # Normalize incoming email to match how we store emails on user creation
    email = (request.data.get('email') or '').strip().lower()
    password = request.data.get('password')

    logger.warning("rider_login attempt for email=%s", email)

    if not email or not password:
        logger.warning("rider_login: missing email or password")
        return Response({"error": "Please enter both email and password."}, status=400)

    try:
        user_obj = User.objects.get(email=email)
        logger.warning("rider_login: found user username=%s for email=%s", user_obj.username, email)
    except User.DoesNotExist:
        logger.warning("rider_login: no user found for email=%s", email)
        return Response({"error": "Invalid credentials.", "detail": "No user with that email"}, status=401)

    user = authenticate(request, username=user_obj.username, password=password)
    if user is None:
        logger.warning("rider_login: authentication failed for username=%s (email=%s)", getattr(user_obj, 'username', '<unknown>'), email)
        return Response({"error": "Invalid credentials.", "detail": "Wrong password for this user"}, status=401)

    try:
        profile = user.profile
        if not profile.is_commuter:
            return Response({"error": "This user is not a rider."}, status=403)

        try:
            from rest_framework_simplejwt.tokens import RefreshToken
            refresh = RefreshToken.for_user(user)
            access_token = str(refresh.access_token)
            refresh_token = str(refresh)
        except ImportError:
            # Fallback if rest_framework_simplejwt not installed - use a simple token
            import base64
            token_data = f"{user.id}:{user.username}:{timezone.now().isoformat()}"
            access_token = base64.b64encode(token_data.encode()).decode()
            refresh_token = access_token

        return Response({
            "access": access_token,
            "refresh": refresh_token,
            "user": {"id": user.id, "username": user.username, "email": user.email}
        })
    except CustomUserProfile.DoesNotExist:
        return Response({"error": "User profile not found for this user."}, status=404)

@api_view(['POST'])
def update_bus_location(request):
    """
    Updates the real-time location of a bus.
    Expected POST data: {'bus_id': '...', 'latitude': '...', 'longitude': '...'}
    """
    # Diagnostic logging to identify who/what is posting location updates
    try:
        auth_hdr = request.META.get('HTTP_AUTHORIZATION') or request.META.get('Authorization')
        remote_addr = request.META.get('REMOTE_ADDR')
        xff = request.META.get('HTTP_X_FORWARDED_FOR')
        ua = request.META.get('HTTP_USER_AGENT')
        masked = _masked_token_from_request(request)
        # request.data can be a QueryDict; convert to dict for logging
        try:
            body_preview = dict(request.data)
        except Exception:
            body_preview = str(request.body)[:200]
        logger.warning(f"[update_bus_location] POST from {remote_addr} xff={xff} auth_mask={masked} ua={ua} body={body_preview}")
    except Exception:
        logger.exception("[update_bus_location] Failed to produce diagnostic log for incoming request")

    # SECURITY GUARD: Only accept location updates from the trusted simulator.
    # Require the client to set header `X-SIMULATOR: true` on simulator requests.
    # This is a temporary protection to ensure only the user's simulation script
    # updates real-time bus locations while debugging.
    sim_header = request.META.get('HTTP_X_SIMULATOR')
    if sim_header != 'true':
        logger.warning(f"[update_bus_location] Rejected POST - missing X-SIMULATOR header from {request.META.get('REMOTE_ADDR')} ua={request.META.get('HTTP_USER_AGENT')}")
        return Response({"error": "Forbidden: location updates require X-SIMULATOR header."}, status=403)

    bus_id = request.data.get('bus_id')
    latitude = request.data.get('latitude')
    longitude = request.data.get('longitude')

    if not all([bus_id, latitude, longitude]):
        return Response({"error": "bus_id, latitude, and longitude are required."}, status=400)

    try:
        bus = Bus.objects.get(pk=bus_id)
        bus.current_location = Point(float(longitude), float(latitude), srid=4326)
        bus.last_reported_at = timezone.now()
        bus.save(update_fields=['current_location', 'last_reported_at'])
        
        return Response({"status": "success", "message": f"Location for bus {bus.plate_number} updated."})

    except Bus.DoesNotExist:
        return Response({"error": f"Bus with id {bus_id} not found."}, status=404)
    except (ValueError, TypeError) as e:
        return Response({"error": f"Invalid data provided: {e}"}, status=400)


@api_view(['GET'])
@permission_classes([IsAuthenticated])
def get_driver_profile(request):
    """
    Returns the complete profile for the currently authenticated driver,
    including their assigned bus and route details.
    """
    user = request.user
    auth_header = request.META.get('HTTP_AUTHORIZATION', 'NO_AUTH_HEADER')
    logger.warning(f"[DEBUG get_driver_profile] Auth header: {auth_header[:50] if auth_header else 'None'}...")
    logger.warning(f"[DEBUG get_driver_profile] User: {user}, Authenticated: {user.is_authenticated}")
    
    try:
        # 1. Verify the user is a driver through their profile.
        driver_profile = user.profile
        if not driver_profile.is_driver:
            return Response({"error": "This user is not a driver."}, status=403)

        # 2. Find the bus assigned to this driver (may be None) and the latest route.
        bus = Bus.objects.filter(driver=driver_profile).first()
        logger.warning(f"[DEBUG get_driver_profile] user={user.username}, driver_profile={driver_profile.id}, bus={bus}")
        
        # Query trips related to this driver's profile (through buses driven by this profile)
        # This ensures we get trips even if the bus assignment recently changed
        latest_trip = Trip.objects.filter(bus__driver=driver_profile).order_by('-departure_time').first()
        logger.warning(f"[DEBUG get_driver_profile] latest_trip={latest_trip}, status={latest_trip.status if latest_trip else None}")
        # Only set active_trip_id if the trip is pending or started
        if latest_trip and latest_trip.status in [Trip.STATUS_PENDING, Trip.STATUS_STARTED]:
            active_trip_id = latest_trip.id
            route = latest_trip.route if latest_trip.route else None
        else:
            active_trip_id = None
            # Use assigned_route if set, otherwise None
            route = bus.assigned_route if bus and bus.assigned_route else None
        logger.warning(f"[DEBUG get_driver_profile] active_trip_id={active_trip_id}")
        logger.warning(f"[DEBUG get_driver_profile] assigned_route={bus.assigned_route if bus else None}")

        # --- FIX: Dynamically determine if the profile is complete ---
        # A profile is complete if the user has a name, phone, and an assigned bus with a plate.
        is_complete = all([
            user.first_name,
            user.last_name,
            driver_profile.phone_number,
            bus and bus.plate_number
        ])

        route_serializer = RouteSerializer(route) if route else None

        response_data = {
            "driver_name": user.get_full_name() or user.username,
            "phone_number": str(driver_profile.phone_number) if driver_profile.phone_number else None,
            "bus": BusNearbySerializer(bus).data if bus else None,
            "route": route_serializer.data if route_serializer else None,
            "selected_start_stop_id": driver_profile.selected_start_stop.id if getattr(driver_profile, 'selected_start_stop', None) else None,
            "selected_end_stop_id": driver_profile.selected_end_stop.id if getattr(driver_profile, 'selected_end_stop', None) else None,
            "active_trip_id": active_trip_id,
            "onboarding_complete": is_complete, # Return the calculated status
        }
        logger.warning(f"[DEBUG get_driver_profile] Response data: {response_data}")
        return Response(response_data)
    except CustomUserProfile.DoesNotExist:
        return Response({"error": "Driver profile not found for this user."}, status=404)
    except Bus.DoesNotExist:
        # This exception should not occur anymore because we use filter().first(),
        # but keep a safe fallback.
        return Response({"error": "No bus assigned to this driver."}, status=404)


@api_view(['POST'])
@permission_classes([IsAuthenticated])
def driver_onboard(request):
    # Logging is already set up at the module level
    """
    Driver onboarding: accepts first/last name, phone number, bus plate and capacity,
    and optional route_id to create/assign a Bus (and optional Trip).
    Requires authentication. Returns created/updated bus and optional trip/route info.
    """
    user = request.user
    try:
        profile = user.profile
    except CustomUserProfile.DoesNotExist:
        return Response({"error": "Driver profile not found for this user."}, status=404)

    if not profile.is_driver:
        logger.warning(f"[driver_onboard] User {user.username} is not a driver.")
        return Response({"error": "This user is not a driver."}, status=403)

    first_name = (request.data.get('first_name') or '').strip()
    last_name = (request.data.get('last_name') or '').strip()
    phone = (request.data.get('phone_number') or '').strip()
    bus_plate = (request.data.get('bus_plate_number') or '').strip()
    bus_capacity = request.data.get('bus_capacity')
    route_id = request.data.get('route_id')
    # Optional selected start/end stops from driver UI
    selected_start_id = request.data.get('selected_start_stop_id')
    selected_end_id = request.data.get('selected_end_stop_id')
    logger.info(f"[driver_onboard] Parsed fields: first_name={first_name}, last_name={last_name}, phone={phone}, bus_plate={bus_plate}, bus_capacity={bus_capacity}, route_id={route_id}")

    # --- FIX: Update user and profile information separately to ensure saves are atomic ---

    # Update user's name if provided
    if first_name or last_name:
        user.first_name = first_name
        user.last_name = last_name
        user.save(update_fields=['first_name', 'last_name'])

    # Update profile's phone number if provided
    if phone:
        profile.phone_number = phone
        profile.save(update_fields=['phone_number'])


    # Create or attach Bus if plate provided, otherwise find bus for current driver
    bus = None
    if bus_plate:
        try:
            bus, created = Bus.objects.get_or_create(plate_number=bus_plate, defaults={'capacity': int(bus_capacity) if bus_capacity else 30, 'driver': profile})
            logger.info(f"[driver_onboard] Bus get_or_create: bus={bus}, created={created}")
            if not created:
                bus.driver = profile
                if bus_capacity:
                    try:
                        bus.capacity = int(bus_capacity)
                    except (ValueError, TypeError):
                        pass
                bus.save(update_fields=['driver', 'capacity'])
                logger.info(f"[driver_onboard] Updated bus assignment: bus={bus}, driver={profile}, capacity={bus.capacity}")
            else:
                logger.warning(f"[driver_onboard] Created new bus {bus_plate} for driver {user.username}")
        except Exception as e:
            logger.exception(f"[driver_onboard] Failed to create/assign bus {bus_plate} for user {user.username}")
            return Response({"error": "failed", "message": "Could not create or assign bus."}, status=500)
    else:
        # If no bus_plate provided, find the bus for the current driver
        bus = Bus.objects.filter(driver=profile).first()
        logger.info(f"[driver_onboard] No bus_plate provided, found bus for driver: {bus}")

    # If a route_id was provided, fetch the route, persist as assigned_route, and include it in the response
    selected_route = None
    if route_id and bus:
        try:
            selected_route = Route.objects.get(id=route_id)
            logger.info(f"[driver_onboard] Selected route found: {selected_route}")
            bus.assigned_route = selected_route
            bus.save(update_fields=["assigned_route"])
        except Route.DoesNotExist:
            logger.warning(f"[driver_onboard] Route with id {route_id} does not exist.")
            selected_route = None

    latest_trip = Trip.objects.filter(bus=bus).order_by('-departure_time').first() if bus else None
    logger.info(f"[driver_onboard] Latest trip for bus: {latest_trip}")

    # Persist selected start/end stops on the driver's profile if provided
    try:
        if selected_start_id:
            try:
                start_stop = Stop.objects.get(pk=selected_start_id)
                profile.selected_start_stop = start_stop
            except Stop.DoesNotExist:
                logger.warning(f"[driver_onboard] selected_start_stop_id {selected_start_id} does not exist")
        else:
            profile.selected_start_stop = None

        if selected_end_id:
            try:
                end_stop = Stop.objects.get(pk=selected_end_id)
                profile.selected_end_stop = end_stop
            except Stop.DoesNotExist:
                logger.warning(f"[driver_onboard] selected_end_stop_id {selected_end_id} does not exist")
        else:
            profile.selected_end_stop = None

        profile.save(update_fields=['selected_start_stop', 'selected_end_stop'])
    except Exception:
        logger.exception("[driver_onboard] Failed to save selected start/end stops on profile")

    # Do NOT create a trip here. Trip creation should only happen when the driver explicitly starts a trip.

    # Return collected onboarding result
    data = {
        "driver_name": user.get_full_name() or user.username,
        "bus": BusNearbySerializer(bus).data if bus else None,
        "route": RouteSerializer(selected_route).data if selected_route else (RouteSerializer(latest_trip.route).data if (latest_trip and latest_trip.route) else None),
        "trip_id": None, # This endpoint no longer creates trips
        "active_trip_id": None,
        "selected_start_stop_id": profile.selected_start_stop.id if getattr(profile, 'selected_start_stop', None) else None,
        "selected_end_stop_id": profile.selected_end_stop.id if getattr(profile, 'selected_end_stop', None) else None,
    }
    logger.info(f"[driver_onboard] Response data: {data}")

    return Response(data)

@api_view(['POST'])
@permission_classes([IsAuthenticated])
def create_and_start_trip(request):
    """
    Creates a new trip based on the driver's assigned route and selected stops,
    and immediately returns the new trip ID. This is the primary endpoint for
    the 'Start Trip' button.
    """
    user = request.user
    try:
        profile = user.profile
        if not profile.is_driver:
            return Response({"error": "User is not a driver."}, status=status.HTTP_403_FORBIDDEN)

        bus = Bus.objects.filter(driver=profile).first()
        if not bus:
            return Response({"error": "No bus is assigned to this driver."}, status=status.HTTP_400_BAD_REQUEST)

        # The route is derived from the latest trip or the bus's current assigned route
        latest_trip_for_route = Trip.objects.filter(bus=bus).order_by('-departure_time').first()
        route = latest_trip_for_route.route if latest_trip_for_route else bus.assigned_route

        if not route:
            return Response({"error": "No route is assigned to this bus."}, status=status.HTTP_400_BAD_REQUEST)

        # End any previously active trips for this bus to prevent duplicates.
        Trip.objects.filter(bus=bus, status=Trip.STATUS_STARTED).update(
            status=Trip.STATUS_FINISHED,
            finished_at=timezone.now()
        )

        # --- FIX: Create the new trip and immediately mark it as STARTED ---
        # The name 'create_and_start_trip' implies the trip should be active
        # immediately. This simplifies the frontend logic as it no longer needs
        # to make a separate call to start the trip from the dashboard.
        new_trip = Trip.objects.create(
            bus=bus,
            route=route,
            departure_time=timezone.now(),
            started_at=timezone.now(),
            status=Trip.STATUS_STARTED # Start as active
        )

        # Decide whether to spawn the background simulator.
        # Default behaviour now follows the global setting `BUS_SIMULATION_ENABLED`.
        # Callers may still pass `simulate: false` in the POST body to override.
        from django.conf import settings as django_settings
        simulate = request.data.get('simulate', None)
        # Normalize common string values (e.g. 'false') to booleans
        if isinstance(simulate, str):
            simulate = simulate.strip().lower() not in ('false', '0', 'no', 'n', 'off', 'none', 'null', '')
        elif simulate is None:
            simulate = getattr(django_settings, 'BUS_SIMULATION_ENABLED', False)
        else:
            simulate = bool(simulate)

        if simulate:
            # Server-side simulation helper has been removed. Honor the request
            # but do not spawn any background simulator; callers should use an
            # external simulator or device updates to emit positions.
            logger.info(f"create_and_start_trip: simulate requested but server-side simulator removed; simulate flag ignored for trip {new_trip.id}")
        else:
            logger.info(f"create_and_start_trip: create trip {new_trip.id} without spawning simulator (simulate=False)")

        logger.info(f"create_and_start_trip: Created Trip ID {new_trip.id} for Bus {bus.id} on Route {route.name}")
        return Response({"trip_id": new_trip.id}, status=status.HTTP_201_CREATED)

    except CustomUserProfile.DoesNotExist:
        return Response({"error": "Driver profile not found."}, status=status.HTTP_404_NOT_FOUND)
    except Exception as e:
        logger.exception("create_and_start_trip: An unexpected error occurred.")
        return Response({"error": str(e)}, status=status.HTTP_500_INTERNAL_SERVER_ERROR)

    # NOTE: The previous `_start_trip_simulation` helper has been removed.
    # Server-side automatic simulation is intentionally disabled. Vehicle
    # positions should be provided by device clients or external simulators.

@api_view(['POST'])
def register_user(request):
    """
    Creates a new user and a linked profile based on the provided role.
    """
    username = (request.data.get('username') or '').strip()
    email = (request.data.get('email') or '').strip().lower()
    password = request.data.get('password')
    role = (request.data.get('role') or 'rider').strip().lower()  # default to rider

    if not username:
        return Response({"error": "Username is required."}, status=400)
    if not email:
        return Response({"error": "Email is required."}, status=400)
    if not password:
        return Response({"error": "Password is required."}, status=400)

    if role not in ['rider', 'driver']:
        return Response({"error": "Role must be either 'rider' or 'driver'."}, status=400)

    # Quick uniqueness checks with clear messages
    if User.objects.filter(email=email).exists():
        logger.warning("register_user: email already exists: %s", email)
        return Response({"error": "email", "message": "A user with this email already exists."}, status=400)

    if User.objects.filter(username=username).exists():
        logger.warning("register_user: username already exists: %s", username)
        return Response({"error": "username", "message": "A user with this username already exists."}, status=400)

    try:
        # Create the user. create_user handles password hashing.
        user = User.objects.create_user(username=username, email=email, password=password)

        # Optionally set first/last name for driver onboarding
        first_name = (request.data.get('first_name') or '').strip()
        last_name = (request.data.get('last_name') or '').strip()
        if first_name or last_name:
            user.first_name = first_name
            user.last_name = last_name
            user.save(update_fields=['first_name', 'last_name'])

        # Create the associated profile
        profile = CustomUserProfile.objects.create(
            user=user,
            is_driver=(role == 'driver'),
            is_commuter=(role == 'rider')
        )

        # --- FIX: Handle bus creation during driver registration ---
        if role == 'driver':
            bus_plate = (request.data.get('bus_plate_number') or '').strip()
            bus_capacity = request.data.get('bus_capacity')
            if bus_plate:
                try:
                    # Create a new bus and assign it to the new driver's profile.
                    Bus.objects.create(
                        plate_number=bus_plate,
                        capacity=int(bus_capacity) if bus_capacity else 30,
                        driver=profile
                    )
                    logger.info(f"register_user: Created bus {bus_plate} for new driver {user.username}")
                except Exception as e:
                    # Log the error but don't fail the registration. The user can add the bus later.
                    logger.error(f"register_user: Failed to create bus during registration for {user.username}. Reason: {e}")

        # Generate JWT tokens for the new user for immediate login
        try:
            from rest_framework_simplejwt.tokens import RefreshToken
            refresh = RefreshToken.for_user(user)
            access_token = str(refresh.access_token)
            refresh_token = str(refresh)
        except ImportError:
            # Fallback if rest_framework_simplejwt not installed - use a simple token
            import base64
            token_data = f"{user.id}:{user.username}:{timezone.now().isoformat()}"
            access_token = base64.b64encode(token_data.encode()).decode()
            refresh_token = access_token

        return Response({
            "message": "User created successfully.",
            "access": access_token,
            "refresh": refresh_token,
            "user": {"id": user.id, "username": user.username, "email": user.email, "role": role}
        }, status=201)

    except Exception as e:
        logger.exception("register_user: unexpected error while creating user %s (email=%s)", username, email)
        if settings.DEBUG:
            return Response({"error": "unexpected", "message": f"An unexpected error occurred: {str(e)}"}, status=500)
        return Response({"error": "An unexpected error occurred while creating user."}, status=500)

@api_view(['GET'])
def buses_to_destination(request):
    # Validate input params to avoid unhandled exceptions that cause 500
    lat_p = request.query_params.get('lat')
    lon_p = request.query_params.get('lon')
    if lat_p is None or lon_p is None:
        logger.warning('[buses_to_destination] missing lat/lon params: lat=%s lon=%s', lat_p, lon_p)
        return Response({'error': 'lat and lon query parameters are required'}, status=400)
    try:
        target_lat = float(lat_p)
        target_lon = float(lon_p)
    except Exception:
        logger.exception('[buses_to_destination] invalid lat/lon format: lat=%s lon=%s', lat_p, lon_p)
        return Response({'error': 'lat and lon must be valid numbers'}, status=400)
    target_point = Point(target_lon, target_lat, srid=4326)
    # Approach:
    # - Consider routes whose geometry comes within a buffer of the target.
    # - For each active trip on those routes, project both the bus current position
    #   and the target point onto the route polyline and compute along-route distance
    #   from bus -> target. Estimate ETA using recent bus speed (fallback to 10 m/s).
    # This lets us suggest drivers that will pass near the chosen location even if
    # the target is not their explicit stop/destination.

    # Buffers (meters) to consider routes/stops near the chosen location
    ROUTE_BUFFER_M = 800
    STOP_BUFFER_M = 1000

    # Find candidate routes by geometry buffer (routes whose geometry comes within ROUTE_BUFFER_M)
    geom_routes_qs = Route.objects.filter(geometry__dwithin=(target_point, D(m=ROUTE_BUFFER_M)))

    # Also consider routes that have any DB stop within STOP_BUFFER_M of the destination.
    # This captures routes whose stops are near the destination even if the route geometry
    # itself isn't within the stricter ROUTE_BUFFER_M.
    try:
        nearby_stops_qs = Stop.objects.annotate(distance=Distance('location', target_point)).filter(distance__lte=D(m=STOP_BUFFER_M)).order_by('distance')
        nearest_stops_qs = list(nearby_stops_qs[:50])
        nearest_stop_route_ids_set = set()
        for s in nearest_stops_qs:
            try:
                related_route_ids = list(Route.objects.filter(stops__id=s.id).values_list('id', flat=True))
                for rr in related_route_ids:
                    nearest_stop_route_ids_set.add(rr)
            except Exception:
                if getattr(s, 'route', None):
                    try:
                        nearest_stop_route_ids_set.add(s.route.id)
                    except Exception:
                        pass
        nearest_stop_route_ids = list(nearest_stop_route_ids_set)
    except Exception:
        nearest_stops_qs = []
        nearest_stop_route_ids = []

    # Combine route querysets: geometry-based OR routes that own nearby stops
    if nearest_stop_route_ids:
        routes = Route.objects.filter(Q(geometry__dwithin=(target_point, D(m=ROUTE_BUFFER_M))) | Q(id__in=nearest_stop_route_ids)).distinct()
    else:
        routes = geom_routes_qs

    route_count = routes.count()

    # Log candidate routes (id and name) and the nearest DB stops considered
    try:
        candidate_routes_summary = [f"{r.id}:{r.name}" for r in routes]
    except Exception:
        candidate_routes_summary = str(list(routes.values_list('id', flat=True)))
    try:
        nearest_stops = []
        for s in nearest_stops_qs:
            try:
                dist_m = round(getattr(s, 'distance').m if hasattr(getattr(s, 'distance'), 'm') else float(getattr(s, 'distance') or 0.0), 1)
            except Exception:
                dist_m = None
            nearest_stops.append({'id': s.id, 'name': s.name, 'route': s.route.name if s.route else None, 'distance_m': dist_m})
    except Exception:
        nearest_stops = []

    logger.info('[buses_to_destination] target=(%s,%s) ROUTE_BUFFER_M=%s -> candidate routes=%d; candidates=%s; nearest_db_stops=%s', target_lat, target_lon, ROUTE_BUFFER_M, route_count, candidate_routes_summary, nearest_stops)
    trips = Trip.objects.filter(route__in=routes).select_related('bus', 'route')
    trip_count = trips.count()
    logger.info('[buses_to_destination] initial trips count for candidate routes=%d', trip_count)

    # helpers (minimal haversine + polyline projection)
    def haversine_m(a_lat, a_lon, b_lat, b_lon):
        R = 6371000.0
        phi1 = math.radians(a_lat); phi2 = math.radians(b_lat)
        dphi = math.radians(b_lat - a_lat); dlmb = math.radians(b_lon - a_lon)
        hav = math.sin(dphi/2)**2 + math.cos(phi1)*math.cos(phi2)*math.sin(dlmb/2)**2
        return 2 * R * math.asin(math.sqrt(hav))

    def project_point_onto_linestring(linestring_coords, lat, lon):
        # linestring_coords: iterable of (lon, lat) tuples
        points = [(c[1], c[0]) for c in linestring_coords]
        seg_lengths = [haversine_m(points[i][0], points[i][1], points[i+1][0], points[i+1][1]) for i in range(len(points)-1)]
        best_seg = 0; best_frac = 0.0; best_dist = float('inf'); best_proj = points[0]
        for i in range(len(points)-1):
            a = points[i]; b = points[i+1]
            dx = b[0] - a[0]; dy = b[1] - a[1]
            if dx == 0 and dy == 0:
                frac = 0.0
            else:
                apx = lat - a[0]; apy = lon - a[1]
                denom = dx*dx + dy*dy
                frac = (apx*dx + apy*dy) / denom
                frac = max(0.0, min(1.0, frac))
            proj_lat = a[0] + (b[0]-a[0])*frac
            proj_lon = a[1] + (b[1]-a[1])*frac
            d = haversine_m(lat, lon, proj_lat, proj_lon)
            if d < best_dist:
                best_dist = d; best_seg = i; best_frac = frac; best_proj = (proj_lat, proj_lon)
        # compute absolute distance along polyline to projection
        cum = [0.0]
        s = 0.0
        for l in seg_lengths:
            s += l; cum.append(s)
        traveled = (best_frac * seg_lengths[best_seg]) if seg_lengths and best_seg < len(seg_lengths) else 0.0
        abs_dist = cum[best_seg] + traveled
        return {
            'proj_point': best_proj,
            'seg_idx': best_seg,
            'seg_frac': best_frac,
            'abs_dist': abs_dist,
            'perp_dist_m': best_dist,
            'total_length_m': cum[-1] if cum else 0.0,
        }

    data = []
    for trip in trips:
        # Protect processing of each trip so a single bad trip/geometry doesn't cause a 500
        try:
            logger.debug('[buses_to_destination] examining trip id=%s bus_id=%s route=%s', getattr(trip, 'id', None), getattr(trip.bus, 'id', None), getattr(trip.route, 'name', None))

            try:
                bus_pos = VehiclePosition.objects.filter(bus=trip.bus).latest('recorded_at')
                logger.debug('[buses_to_destination] found VehiclePosition for bus %s at %s (speed_mps=%s)', trip.bus.id, getattr(bus_pos, 'recorded_at', None), getattr(bus_pos, 'speed_mps', None))
            except VehiclePosition.DoesNotExist:
                logger.debug('[buses_to_destination] no VehiclePosition for bus %s; skipping', getattr(trip.bus, 'id', None))
                continue

            # Extract route geometry coords (GeoJSON-like order: (lon,lat))
            geom = getattr(trip.route, 'geometry', None)
            if not geom:
                logger.debug('[buses_to_destination] trip=%s has no geometry; skipping', getattr(trip, 'id', None))
                continue
            try:
                coords = list(geom.coords)
            except Exception:
                logger.exception('[buses_to_destination] failed to extract coords for route of trip=%s; skipping', getattr(trip, 'id', None))
                continue

            # Project target and bus position onto route
            try:
                target_proj = project_point_onto_linestring(coords, target_lat, target_lon)
                bus_proj = project_point_onto_linestring(coords, bus_pos.location.y, bus_pos.location.x)
            except Exception:
                logger.exception('[buses_to_destination] projection failed for trip=%s; skipping', getattr(trip, 'id', None))
                continue

            logger.debug('[buses_to_destination] trip=%s target_proj perp=%.1fm abs_dist=%.1fm total_len=%.1fm', getattr(trip, 'id', None), target_proj['perp_dist_m'], target_proj['abs_dist'], target_proj['total_length_m'])
            logger.debug('[buses_to_destination] trip=%s bus_proj perp=%.1fm abs_dist=%.1fm', getattr(trip, 'id', None), bus_proj['perp_dist_m'], bus_proj['abs_dist'])

            # Only consider this bus if the target projects onto the route reasonably close
            # (perpendicular distance less than buffer) and if the bus is upstream of the target
            if target_proj['perp_dist_m'] <= ROUTE_BUFFER_M:
                # compute along-route distance from bus to target (positive means bus before target)
                along_m = target_proj['abs_dist'] - bus_proj['abs_dist']
                # estimate bus speed
                speed_mps = bus_pos.speed_mps if getattr(bus_pos, 'speed_mps', None) and bus_pos.speed_mps > 0 else 10.0
                eta_seconds = abs(along_m) / speed_mps if speed_mps > 0 else None
                eta_minutes = round(eta_seconds/60.0, 1) if eta_seconds is not None else None

                # include bus if it's going to pass near the target within a reasonable window (e.g., 90 minutes)
                logger.debug('[buses_to_destination] trip=%s along_m=%.1f m eta_min=%s', getattr(trip, 'id', None), along_m, eta_minutes)
                if eta_minutes is not None and eta_minutes <= 90:
                    entry = {
                        'bus_id': str(trip.bus.id),
                        'route': trip.route.name,
                        'eta_min': eta_minutes,
                        'current_lat': getattr(bus_pos.location, 'y', None),
                        'current_lon': getattr(bus_pos.location, 'x', None),
                        'distance_to_route_m': bus_proj['perp_dist_m'],
                        'target_perp_dist_m': target_proj['perp_dist_m'],
                        'along_route_to_target_m': along_m,
                    }
                    logger.info('[buses_to_destination] suggesting bus=%s route=%s eta_min=%.1f perp_dist=%.1f along_m=%.1f', entry['bus_id'], entry['route'], entry['eta_min'], entry['target_perp_dist_m'], entry['along_route_to_target_m'])
                    data.append(entry)
        except Exception:
            logger.exception('[buses_to_destination] unexpected error while processing trip %s', getattr(trip, 'id', None))
            # continue processing other trips rather than aborting the request
            continue

    logger.info('[buses_to_destination] returning %d suggested buses', len(data))
    return Response(data)


@api_view(['POST'])
@permission_classes([IsAuthenticated])
def plan_trip(request):
    """
    Plan a trip for an authenticated rider.
    POST body: { "destination_stop_id": int, optional: "latitude": float, "longitude": float }
    Records destination stop and route on the rider profile, finds the nearest origin stop,
    and returns whether the destination is on the same route or what transfers are needed,
    along with an ETA estimate in minutes.
    """
    user = request.user
    try:
        profile = user.profile
    except CustomUserProfile.DoesNotExist:
        return Response({"error": "Profile not found."}, status=404)

    dest_id = request.data.get('destination_stop_id')
    if not dest_id:
        return Response({"error": "destination_stop_id is required"}, status=400)

    try:
        dest_stop = Stop.objects.select_related('route').get(pk=int(dest_id))
    except Stop.DoesNotExist:
        return Response({"error": "Destination stop not found"}, status=404)

    # Determine rider location: prefer provided coords, otherwise profile.current_location
    lat = request.data.get('latitude')
    lon = request.data.get('longitude')
    if lat is not None and lon is not None:
        try:
            lat = float(lat); lon = float(lon)
            user_point = Point(lon, lat, srid=4326)
            profile.current_location = user_point
        except Exception:
            return Response({"error": "Invalid latitude/longitude provided"}, status=400)
    else:
        if not profile.current_location:
            return Response({"error": "No rider location available; provide latitude and longitude"}, status=400)
        user_point = profile.current_location
        lat = user_point.y; lon = user_point.x

    # Save destination info on profile
    profile.destination = dest_stop.location
    profile.destination_stop = dest_stop
    profile.destination_route = dest_stop.route
    profile.save(update_fields=['destination', 'destination_stop', 'destination_route', 'current_location'])

    # Helper: haversine distance in km
    def haversine_km(lat1, lon1, lat2, lon2):
        R = 6371.0
        phi1 = math.radians(lat1); phi2 = math.radians(lat2)
        dphi = math.radians(lat2 - lat1); dlmb = math.radians(lon2 - lon1)
        a = math.sin(dphi/2)**2 + math.cos(phi1)*math.cos(phi2)*math.sin(dlmb/2)**2
        return 2 * R * math.asin(math.sqrt(a))

    # Find nearest stop to rider
    stops = Stop.objects.select_related('route').all()
    best = None; best_km = 1e9
    for s in stops:
        try:
            s_lat = s.location.y; s_lon = s.location.x
            dkm = haversine_km(lat, lon, s_lat, s_lon)
            if dkm < best_km:
                best = s; best_km = dkm
        except Exception:
            continue

    if not best:
        return Response({"error": "No stops configured in system."}, status=500)

    profile.origin_stop = best
    profile.save(update_fields=['origin_stop'])

    origin_stop = best
    origin_route = origin_stop.route
    dest_route = dest_stop.route

    same_route = (origin_route.id == dest_route.id)

    # Compute walking distance to origin stop (meters)
    walk_km = best_km
    walk_minutes = (walk_km / 5.0) * 60.0  # assume 5 km/h walking speed

    # Compute bus travel distance along route if same route
    def route_segment_km(route, a_stop, b_stop):
        stops_ordered = list(route.stops.order_by('order'))
        # map id->index
        idx_map = {s.id: i for i, s in enumerate(stops_ordered)}
        if a_stop.id not in idx_map or b_stop.id not in idx_map:
            return None
        i = idx_map[a_stop.id]; j = idx_map[b_stop.id]
        if i == j:
            return 0.0
        if i > j:
            i, j = j, i
        total = 0.0
        for k in range(i, j):
            s1 = stops_ordered[k]; s2 = stops_ordered[k+1]
            total += haversine_km(s1.location.y, s1.location.x, s2.location.y, s2.location.x)
        return total

    bus_km = None; bus_minutes = None
    if same_route:
        seg_km = route_segment_km(origin_route, origin_stop, dest_stop)
        bus_km = seg_km if seg_km is not None else 0.0
        # Find an active started trip on this route to estimate speed
        trip = Trip.objects.filter(route=origin_route, status=Trip.STATUS_STARTED).select_related('bus').first()
        if trip and trip.bus and trip.bus.speed_mps and trip.bus.speed_mps > 0:
            speed_kmh = trip.bus.speed_mps * 3.6
        else:
            speed_kmh = 30.0
        bus_minutes = (bus_km / speed_kmh) * 60.0 if speed_kmh > 0 else None

    transfers = []
    if not same_route:
        # Simple 2-hop transfer search: find a route R2 such that origin_route stops
        # are close to R2 stops, and R2 stops are close to dest_route stops.
        all_routes = Route.objects.prefetch_related('stops').all()
        def close(a, b, threshold_m=200):
            return haversine_km(a.location.y, a.location.x, b.location.y, b.location.x) * 1000.0 <= threshold_m

        found_chain = None
        for r2 in all_routes:
            if r2.id in (origin_route.id, dest_route.id):
                continue
            # check origin_route -> r2
            ok1 = any(close(s1, s2) for s1 in origin_route.stops.all() for s2 in r2.stops.all())
            # check r2 -> dest_route
            ok2 = any(close(s1, s2) for s1 in r2.stops.all() for s2 in dest_route.stops.all())
            if ok1 and ok2:
                found_chain = [origin_route.name, r2.name, dest_route.name]
                break
        if found_chain:
            transfers = found_chain
        else:
            # fallback: suggest origin_route -> dest_route (transfer at closest stops)
            transfers = [origin_route.name, dest_route.name]

    eta_total_minutes = None
    if bus_minutes is not None:
        eta_total_minutes = round(walk_minutes + bus_minutes, 1)
    else:
        # best-effort ETA: walking to origin + straight-line from origin to dest (as fallback)
        straight_km = haversine_km(origin_stop.location.y, origin_stop.location.x, dest_stop.location.y, dest_stop.location.x)
        # assume vehicle speed 30 km/h
        straight_minutes = (straight_km / 30.0) * 60.0
        eta_total_minutes = round(walk_minutes + straight_minutes, 1)

    resp = {
        "origin_stop": {"id": origin_stop.id, "order": origin_stop.order, "route": origin_route.name},
        "destination_stop": {"id": dest_stop.id, "order": dest_stop.order, "route": dest_route.name},
        "same_route": same_route,
        "transfers": transfers,
        "walk_m": round(walk_km * 1000.0, 1),
        "bus_km": round(bus_km, 3) if bus_km is not None else None,
        "eta_minutes": eta_total_minutes,
    }

    return Response(resp)


@api_view(['GET'])
def stop_list(request):
    """
    Return a list of all stops with minimal route info and GeoJSON location.
    Frontend `SearchService.getAllBusStops` depends on this returning a list
    of objects with keys: id, name, route_id, route_name, location={type:Point, coordinates:[lon,lat]}.
    """
    try:
        stops = Stop.objects.select_related('route').all()
        out = []
        for s in stops:
            try:
                geom = s.location
                coords = [geom.x, geom.y] if geom is not None else [0.0, 0.0]
                # `Stop` model historically did not include a `name` field.
                # Provide a safe fallback so the API returns usable entries
                # instead of silently skipping them due to AttributeError.
                name = getattr(s, 'name', f"Stop {s.order}")
                # Also include all route ids that reference this stop (many-to-many via FK from Stop to Route in imports)
                try:
                    related_route_ids = list(Route.objects.filter(stops__id=s.id).values_list('id', flat=True))
                except Exception:
                    related_route_ids = [s.route.id] if getattr(s, 'route', None) else []

                out.append({
                    'id': s.id,
                    'name': name,
                    'order': s.order,
                    'route_id': s.route.id if s.route else None,
                    'route_name': s.route.name if s.route else None,
                    'route_ids': related_route_ids,
                    'location': {'type': 'Point', 'coordinates': coords},
                })
            except Exception:
                continue
        return Response(out)
    except Exception as e:
        logger.exception('stop_list: unexpected error')
        return Response({'error': 'Could not load stops'}, status=500)


@api_view(['POST'])
@permission_classes([IsAuthenticated])
def start_trip(request, trip_id):
    """
    Starts a trip: mark as started, set started_at, and optionally spawn a
    background simulator to emit VehiclePosition records along the route.
    """
    try:
        trip = Trip.objects.select_related('route', 'bus').get(pk=trip_id)
    except Trip.DoesNotExist:
        return Response({"error": "Trip not found."}, status=404)

    # Only allow starting if not already started
    if trip.status == Trip.STATUS_STARTED:
        return Response({"error": "Trip already started."}, status=400)

    # Mark as started
    trip.status = Trip.STATUS_STARTED
    trip.started_at = dj_timezone.now()
    trip.save(update_fields=['status', 'started_at'])

    # --- FIX: Set initial location immediately ---
    # This prevents a race condition where the bus is started but has no location
    # until the background thread runs for the first time.
    if trip.route and trip.route.geometry and trip.bus:
        initial_point = trip.route.geometry.interpolate_normalized(0)
        trip.bus.current_location = initial_point
        trip.bus.last_reported_at = dj_timezone.now()
        trip.bus.save(update_fields=['current_location', 'last_reported_at'])
        logger.info(f"start_trip: Set initial location for bus {trip.bus.id} to start of route {trip.route.id}")

    # --- REFACTOR: Use the centralized simulation helper ---
    # Respect the global BUS_SIMULATION_ENABLED setting and allow an
    # explicit `simulate` override in the POST body (e.g. simulate=false).
    from django.conf import settings as django_settings
    simulate = None
    try:
        simulate = request.data.get('simulate', None)
    except Exception:
        simulate = None

    if isinstance(simulate, str):
        simulate = simulate.strip().lower() not in ('false', '0', 'no', 'n', 'off', 'none', 'null', '')
    elif simulate is None:
        simulate = getattr(django_settings, 'BUS_SIMULATION_ENABLED', False)
    else:
        simulate = bool(simulate)

    if simulate:
        # Server-side simulation helper was removed; do not start any thread.
        logger.info(f"start_trip: simulate requested but server-side simulator removed; simulate flag ignored for trip {trip.id}")
    else:
        logger.info(f"start_trip: trip {trip.id} started without background simulation (simulate=False)")

    return Response({"status": "started", "trip_id": str(trip.id)})


class EndTripView(APIView):
    permission_classes = [IsAuthenticated]

    def post(self, request, trip_id):
        try:
            trip = Trip.objects.get(pk=trip_id)
        except Trip.DoesNotExist:
            return Response({"error": "Trip not found."}, status=404)

        if trip.status == Trip.STATUS_FINISHED:
            return Response({"error": "Trip already finished."}, status=400)

        trip.status = Trip.STATUS_FINISHED
        trip.finished_at = dj_timezone.now()
        trip.save(update_fields=['status', 'finished_at'])

        return Response({"status": "finished", "trip_id": str(trip.id)})


@api_view(['GET'])
def get_dev_rider_location(request):
    """
    DEV-ONLY endpoint. Reads the mock rider location from the .dev_rider_location.json
    file at the project root and returns it.
    """
    # The file is in the project root, so we can use settings.BASE_DIR
    file_path = os.path.join(settings.BASE_DIR, '.dev_rider_location.json')
    
    if not os.path.exists(file_path):
        return Response({"error": "Mock location file not found."}, status=status.HTTP_404_NOT_FOUND)
        
    try:
        with open(file_path, 'r') as f:
            data = json.load(f)
        return Response(data)
    except Exception as e:
        logger.error(f"[get_dev_rider_location] Error reading mock location file: {e}")
        return Response({"error": "Could not read or parse mock location file."}, status=status.HTTP_500_INTERNAL_SERVER_ERROR)
