from django.contrib.gis.geos import Point
from django.utils import timezone
from rest_framework.decorators import api_view, permission_classes
from rest_framework.response import Response
from .models import VehiclePosition, Trip, Route, Bus, CustomUserProfile
from datetime import timedelta
from django.contrib.auth.models import User
from django.contrib.gis.measure import D  
from django.contrib.gis.db.models.functions import Distance
from django.db.models import OuterRef, Subquery
from django.db.models.functions import Coalesce, Cast
from .serializers import BusNearbySerializer, RouteSerializer
from django.contrib.auth import authenticate
from rest_framework.permissions import IsAuthenticated
from rest_framework_simplejwt.tokens import RefreshToken
import logging
from django.conf import settings

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
    
    # Deconstruct total seconds into hours, minutes, and seconds for a richer response
    if distance_m > 10:
        m, s = divmod(eta_seconds, 60)
        h, m = divmod(m, 60)
        eta_structured = {"hours": int(h), "minutes": int(m), "seconds": int(s)}
    else:
        eta_structured = {"hours": 0, "minutes": 0, "seconds": 0}
        
    data = {
        "bus_id": bus_id,
        "distance_m": round(distance_m, 1),
        # Keep the old field for backward compatibility if needed, but add the new one.
        "estimated_arrival_minutes": round(eta_seconds / 60, 1) if distance_m > 10 else 0,
        "eta": eta_structured,
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
    return Response(data)

@api_view(['POST'])
def driver_login(request):
    """
    Authenticates a driver using email and password, then returns their assigned bus and route.
    """
    email = request.data.get('email')
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
        refresh = RefreshToken.for_user(user)
        access_token = str(refresh.access_token)

        return Response({
            "access": access_token,
            "refresh": str(refresh),
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
    email = request.data.get('email')
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

        refresh = RefreshToken.for_user(user)
        access_token = str(refresh.access_token)

        return Response({
            "access": access_token,
            "refresh": str(refresh),
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
    try:
        # 1. Verify the user is a driver through their profile.
        driver_profile = user.profile
        if not driver_profile.is_driver:
            return Response({"error": "This user is not a driver."}, status=403)

        # 2. Find the bus assigned to this driver (may be None) and the latest route.
        bus = Bus.objects.filter(driver=driver_profile).first()
        latest_trip = Trip.objects.filter(bus=bus).order_by('-departure_time').first() if bus else None
        route = latest_trip.route if (latest_trip and latest_trip.route) else None
        route_serializer = RouteSerializer(route) if route else None

        return Response({
            "driver_name": user.get_full_name() or user.username,
            "bus": BusNearbySerializer(bus).data if bus else None,
            "route": route_serializer.data if route_serializer else None,
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
            route = Route.objects.get(pk=route_id)
            # Create a trip starting now with minimal required fields
            from django.utils import timezone as dj_timezone
            trip_obj = Trip.objects.create(bus=bus, route=route, departure_time=dj_timezone.now())
        except Route.DoesNotExist:
            return Response({"error": "invalid_route", "message": "Provided route_id does not exist."}, status=400)
        except Exception:
            logger.exception("driver_onboard: failed to create trip for bus %s and route %s", bus_plate, route_id)
            return Response({"error": "failed", "message": "Could not create trip for bus."}, status=500)

    # Return collected onboarding result
    data = {
        "driver_name": user.get_full_name() or user.username,
        "bus": BusNearbySerializer(bus).data if bus else None,
        "route": RouteSerializer(route).data if (trip_obj and trip_obj.route) else None,
        "trip_id": str(trip_obj.id) if trip_obj else None,
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
        refresh = RefreshToken.for_user(user)

        return Response({
            "message": "User created successfully.",
            "access": str(refresh.access_token),
            "refresh": str(refresh),
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