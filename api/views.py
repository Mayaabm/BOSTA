from django.contrib.gis.geos import Point
from django.utils import timezone
from rest_framework.decorators import api_view, permission_classes
from rest_framework import generics, status
from rest_framework.response import Response
from rest_framework.views import APIView
from .models import VehiclePosition, Trip, Route, Bus, CustomUserProfile, Stop
from datetime import timedelta
import datetime
from django.contrib.auth.models import User
from django.contrib.gis.measure import D  
from django.contrib.gis.db.models.functions import Distance
from django.db.models import OuterRef, Subquery
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
 
logger = logging.getLogger(__name__)


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

    logger.info(f"[ETA] Request: bus_id={bus_id}, target_lat={target_lat}, target_lon={target_lon}")

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

    logger.info(f"[ETA CALCULATION START]")
    logger.info(f"[ETA] Driver position: LAT={bus_pos.location.y:.6f}, LON={bus_pos.location.x:.6f}")
    logger.info(f"[ETA] Rider position: LAT={float(target_lat):.6f}, LON={float(target_lon):.6f}")

    # Since bus_point is a geography field, .distance() returns meters.
    distance_m = bus_pos.location.distance(target_point)
    logger.info(f"[ETA] Distance: {distance_m:.2f} meters ({distance_m/1000:.2f} km)")

    # Estimate average speed (e.g., 10 m/s ~ 36 km/h)
    # Use the bus's last reported speed, with a fallback.
    avg_speed_m_per_s = bus_pos.speed_mps if bus_pos.speed_mps and bus_pos.speed_mps > 0 else 10.0
    logger.info(f"[ETA] Bus speed: {avg_speed_m_per_s:.2f} m/s ({avg_speed_m_per_s * 3.6:.2f} km/h)")
    
    eta_seconds = distance_m / avg_speed_m_per_s
    logger.info(f"[ETA] ETA seconds: {eta_seconds:.2f}")
    
    # Deconstruct total seconds into hours, minutes, and seconds for a richer response
    if distance_m > 10:
        m, s = divmod(eta_seconds, 60)
        h, m = divmod(m, 60)
        eta_structured = {"hours": int(h), "minutes": int(m), "seconds": int(s)}
        logger.info(f"[ETA] Final ETA: {eta_structured['hours']}h {eta_structured['minutes']}m {eta_structured['seconds']}s")
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
    
    logger.info(f"[ETA] Response data: {data}")
    return Response(data)


 

@api_view(['GET'])
def buses_nearby(request):
    """
    Returns a list of buses near the given latitude and longitude that are on active trips.
    Only shows drivers that are currently logged in and have an active trip (STATUS_STARTED).
    """
    # --- Start of new logging ---
    logger.info("\n--- BUSES NEARBY DEBUG ---")
    try:
        lat = float(request.query_params.get('lat'))
        lon = float(request.query_params.get('lon'))
        radius = float(request.query_params.get('radius', 10000))  # meters
        logger.info(f"[buses_nearby] Rider location: lat={lat}, lon={lon}, radius={radius}m")

        user_location = Point(lon, lat, srid=4326)

        # Step 1: Get all buses that have a location and a recent update.
        recently_updated_buses = Bus.objects.filter(
            current_location__isnull=False,
            last_reported_at__gte=timezone.now() - timedelta(hours=2)
        )
        logger.info(f"[buses_nearby] Found {recently_updated_buses.count()} buses with a recent location.")

        # Step 2: From those, find the ones associated with a 'STARTED' trip.
        buses_with_started_trip = recently_updated_buses.filter(
            trips__status=Trip.STATUS_STARTED
        ).distinct()
        logger.info(f"[buses_nearby] Found {buses_with_started_trip.count()} buses with a 'STARTED' trip.")
        if buses_with_started_trip.count() == 0:
            all_trips = Trip.objects.all().values('bus_id', 'status')
            logger.warning(f"[buses_nearby] No buses have a 'STARTED' trip. Current trip statuses: {list(all_trips)}")

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
        # Dump some headers useful for debugging (may include Authorization)
        hdrs = {k: v for k, v in request.META.items() if k.startswith('HTTP_')}
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
    print(f"[DEBUG get_driver_profile] Auth header: {auth_header[:50] if auth_header else 'None'}...")
    print(f"[DEBUG get_driver_profile] User: {user}, Authenticated: {user.is_authenticated}")
    
    try:
        # 1. Verify the user is a driver through their profile.
        driver_profile = user.profile
        if not driver_profile.is_driver:
            return Response({"error": "This user is not a driver."}, status=403)

        # 2. Find the bus assigned to this driver (may be None) and the latest route.
        bus = Bus.objects.filter(driver=driver_profile).first()
        print(f"[DEBUG get_driver_profile] user={user.username}, driver_profile={driver_profile.id}, bus={bus}")
        
        # Query trips related to this driver's profile (through buses driven by this profile)
        # This ensures we get trips even if the bus assignment recently changed
        latest_trip = Trip.objects.filter(bus__driver=driver_profile).order_by('-departure_time').first()
        print(f"[DEBUG get_driver_profile] latest_trip={latest_trip}, status={latest_trip.status if latest_trip else None}")
        
        route = latest_trip.route if (latest_trip and latest_trip.route) else None
        active_trip_id = latest_trip.id if latest_trip and latest_trip.status in [Trip.STATUS_PENDING, Trip.STATUS_STARTED] else None
        print(f"[DEBUG get_driver_profile] active_trip_id={active_trip_id}")

        route_serializer = RouteSerializer(route) if route else None

        return Response({
            "driver_name": user.get_full_name() or user.username,
            "bus": BusNearbySerializer(bus).data if bus else None,
            "route": route_serializer.data if route_serializer else None,
            # This tells the frontend if there's a trip ready to be started or resumed.
            "active_trip_id": active_trip_id,
        })
    except CustomUserProfile.DoesNotExist:
        return Response({"error": "Driver profile not found for this user."}, status=404)
    except Bus.DoesNotExist:
        # This exception should not occur anymore because we use filter().first(),
        # but keep a safe fallback.
        return Response({"error": "No bus assigned to this driver."}, status=404)


@api_view(['POST'])
@permission_classes([IsAuthenticated])
def driver_onboard(request):
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
        return Response({"error": "This user is not a driver."}, status=403)

    first_name = (request.data.get('first_name') or '').strip()
    last_name = (request.data.get('last_name') or '').strip()
    phone = (request.data.get('phone_number') or '').strip()
    bus_plate = (request.data.get('bus_plate_number') or '').strip()
    bus_capacity = request.data.get('bus_capacity')
    route_id = request.data.get('route_id')

    # Update user name / profile phone if given
    if first_name or last_name:
        user.first_name = first_name
        user.last_name = last_name
        user.save(update_fields=['first_name', 'last_name'])

    if phone:
        profile.current_location = profile.current_location  # no-op placeholder; keep profile save below if needed

    # Create or attach Bus if plate provided
    bus = None
    if bus_plate:
        try:
            # If a bus with this plate exists, attach it to this driver.
            bus, created = Bus.objects.get_or_create(plate_number=bus_plate, defaults={'capacity': int(bus_capacity) if bus_capacity else 30, 'driver': profile})
            if not created:
                # assign driver if not already assigned
                bus.driver = profile
                if bus_capacity:
                    try:
                        bus.capacity = int(bus_capacity)
                    except (ValueError, TypeError):
                        pass
                bus.save(update_fields=['driver', 'capacity'])
            else:
                logger.warning("driver_onboard: created bus %s for driver %s", bus_plate, user.username)
        except Exception as e:
            logger.exception("driver_onboard: failed to create/assign bus %s for user %s", bus_plate, user.username)
            return Response({"error": "failed", "message": "Could not create or assign bus."}, status=500)

    # Optionally create a Trip if route_id provided and bus exists
    trip_obj = None
    if route_id and bus:
        try:
            # First, end any previously active trips for this bus
            active_trips = Trip.objects.filter(bus=bus, status=Trip.STATUS_STARTED)
            for trip in active_trips:
                trip.status = Trip.STATUS_FINISHED
                trip.finished_at = timezone.now()
                trip.save(update_fields=['status', 'finished_at'])
                logger.warning("driver_onboard: ended previous trip %s for bus %s", trip.id, bus.id)
            
            route = Route.objects.get(pk=route_id)
            # Create a trip starting now with minimal required fields
            trip_obj = Trip.objects.create(bus=bus, route=route, departure_time=timezone.now())
            print(f"[DEBUG driver_onboard] Created trip {trip_obj.id} for bus {bus.id}")
        except Route.DoesNotExist:
            print(f"[DEBUG driver_onboard] Route {route_id} not found!")
            return Response({"error": "invalid_route", "message": "Provided route_id does not exist."}, status=400)
        except Exception as e:
            print(f"[DEBUG driver_onboard] Failed to create trip: {e}")
            logger.exception("driver_onboard: failed to create trip for bus %s and route %s", bus_plate, route_id)
            return Response({"error": "failed", "message": "Could not create trip for bus."}, status=500)

    # If a trip was created, mark it as pending but do NOT auto-start simulation here.
    # Trips should be explicitly started via the `start_trip` endpoint so drivers
    # control when a trip moves from pending -> started. This avoids the frontend
    # seeing "Trip already started" when a user finishes onboarding then presses
    # the Start button.
    if trip_obj:
        try:
            trip_obj.status = Trip.STATUS_PENDING
            trip_obj.save(update_fields=['status'])
            logger.info(f"driver_onboard: created trip {trip_obj.id} and set to PENDING for bus {bus.id}")
        except Exception:
            logger.exception(f"driver_onboard: could not set trip {trip_obj.id} to PENDING")

    # Return collected onboarding result
    data = {
        "driver_name": user.get_full_name() or user.username,
        "bus": BusNearbySerializer(bus).data if bus else None,
        "route": RouteSerializer(route).data if (trip_obj and trip_obj.route) else None,
        "trip_id": str(trip_obj.id) if trip_obj else None,
        "active_trip_id": str(trip_obj.id) if trip_obj else None,  # Include for consistency with get_driver_profile
    }

    return Response(data)


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

        # Create the associated profile with the correct role
        CustomUserProfile.objects.create(
            user=user,
            is_driver=(role == 'driver'),
            is_commuter=(role == 'rider')
        )

        # Note: driver registration only creates the account/profile.
        # Bus, trips, routes and stops should be managed separately via
        # driver onboarding endpoints. We intentionally do not create a Bus here.

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

    # Spawn a background simulation thread to create VehiclePosition points
    def _simulate_trip(trip_pk, speed=10.0, interval=2.0):
        try:
            t = Trip.objects.select_related('route', 'bus').get(pk=trip_pk)
            route = t.route
            bus = t.bus
            if not route or not bus:
                logger.error(f"Cannot simulate trip {trip_pk}: missing route or bus.")
                return

            coords = list(route.geometry.coords)
            points = [Point(c[0], c[1], srid=4326) for c in coords]
            start_index = 0

            for i in range(start_index, len(points)):
                point = points[i]
                lon, lat = point.x, point.y

                heading = None
                if i < len(points) - 1:
                    nlon, nlat = points[i + 1].x, points[i + 1].y
                    dy = nlat - lat
                    dx = nlon - lon
                    heading = math.degrees(math.atan2(dy, dx))

                vp = VehiclePosition.objects.create(
                    bus=bus,
                    location=Point(lon, lat, srid=4326),
                    heading_deg=heading,
                    speed_mps=speed,
                )
                # --- FIX: Update the main Bus model as well ---
                # This ensures the bus is visible to the buses_nearby endpoint.
                bus.current_location = vp.location
                bus.last_reported_at = dj_timezone.now()
                bus.save(update_fields=['current_location', 'last_reported_at'])

                time.sleep(interval)

            # Mark trip finished
            t.status = Trip.STATUS_FINISHED
            t.finished_at = dj_timezone.now()
            t.save(update_fields=['status', 'finished_at'])
            logger.info(f"Simulation for trip {t.id} finished.")

        except Exception:
            logger.exception(f"start_trip: unexpected error in background simulator for trip {trip_pk}")

    simulation_thread = threading.Thread(target=_simulate_trip, args=(trip.id,), daemon=True)
    simulation_thread.start()

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
