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
    routes = Route.objects.prefetch_related('stops').all()
    serializer = RouteSerializer(routes, many=True)
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

    if not email or not password:
        return Response({"error": "Please enter both email and password."}, status=400)

    # Use Django's secure `authenticate` function.
    # It will handle finding the user and checking the password.
    # We pass the email from the request as the 'username' parameter for authentication.
    user = authenticate(request, username=email, password=password)
    
    if user is None: # This means the password was incorrect
        return Response({"error": "Invalid credentials."}, status=401)

    # If authentication is successful, get or create a token for the user.
    token, created = Token.objects.get_or_create(user=user)

    try:
        # 1. Verify the user is a driver through their profile.
        driver_profile = user.profile
        if not driver_profile.is_driver:
            return Response({"error": "This user is not a driver."}, status=403)

        # 2. Find the bus assigned to this driver.
        # The route info will be fetched from the /driver/me/ endpoint.
        bus = Bus.objects.get(driver=driver_profile)
        latest_trip = Trip.objects.filter(bus=bus).order_by('-departure_time').first()
        if not latest_trip:
            return Response({"error": "No trips assigned to this driver's bus."}, status=404)

        return Response({
            "token": token.key,
            "driver_name": user.get_full_name() or user.username,
            "bus_id": str(bus.id),
            "route_id": str(latest_trip.route.id)
        })
    except CustomUserProfile.DoesNotExist:
        return Response({"error": "Driver profile not found for this user."}, status=404)
    except Bus.DoesNotExist:
        return Response({"error": "No bus assigned to this driver."}, status=404)

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

        # 2. Find the bus assigned to this driver and the latest route.
        bus = Bus.objects.get(driver=driver_profile)
        latest_trip = Trip.objects.filter(bus=bus).order_by('-departure_time').first()
        if not latest_trip or not latest_trip.route:
            return Response({"error": "No route assigned to this driver's bus."}, status=404)

        route = latest_trip.route
        route_serializer = RouteSerializer(route)

        return Response({
            "driver_name": user.get_full_name() or user.username,
            "bus": BusNearbySerializer(bus).data, # Re-use existing serializer for bus details
            "route": route_serializer.data,
        })
    except CustomUserProfile.DoesNotExist:
        return Response({"error": "Driver profile not found for this user."}, status=404)
    except Bus.DoesNotExist:
        return Response({"error": "No bus assigned to this driver."}, status=404)


@api_view(['POST'])
def register_user(request):
    """
    Creates a new user and a linked profile based on the provided role.
    """
    username = request.data.get('username')
    email = request.data.get('email')
    password = request.data.get('password')
    role = request.data.get('role') # 'rider' or 'driver'

    if not all([username, email, password, role]):
        return Response({"error": "Username, email, password, and role are required."}, status=400)

    if role not in ['rider', 'driver']:
        return Response({"error": "Role must be either 'rider' or 'driver'."}, status=400)

    if User.objects.filter(email=email).exists():
        return Response({"error": "A user with this email already exists."}, status=400)
    
    if User.objects.filter(username=username).exists():
        return Response({"error": "A user with this username already exists."}, status=400)

    try:
        # Create the user. create_user handles password hashing.
        user = User.objects.create_user(username=username, email=email, password=password)

        # Create the associated profile with the correct role
        CustomUserProfile.objects.create(
            user=user,
            is_driver=(role == 'driver'),
            is_commuter=(role == 'rider')
        )

        # Generate JWT tokens for the new user for immediate login
        refresh = RefreshToken.for_user(user)

        return Response({
            "message": "User created successfully.",
            # The frontend expects 'token' for login, so we send the access token under that key.
            "token": str(refresh.access_token),
            "refresh": str(refresh),
            "user": {"id": user.id, "username": user.username, "email": user.email, "role": role}
        }, status=201)

    except Exception as e:
        return Response({"error": f"An unexpected error occurred: {str(e)}"}, status=500)

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