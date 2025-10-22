import time
import random
from datetime import datetime, timedelta

from django.core.management.base import BaseCommand
from django.contrib.gis.geos import Point, LineString
from django.utils import timezone

from api.models import Bus, VehiclePosition, Route, Trip

class Command(BaseCommand):
    help = "Simulates a bus moving along a predefined route, updating its position and creating VehiclePosition records."

    def handle(self, *args, **options):
        self.stdout.write("🚌 Starting bus simulation...")

        # Define a sample polyline (lon, lat) for a route from Batroun to Beirut
        # This is a simplified path for demonstration purposes.
        batroun_beirut_polyline_coords = [
            (35.6547228, 34.148448),  # Batroun center
            (35.660, 34.140),
            (35.670, 34.130),
            (35.680, 34.120),
            (35.690, 34.110),
            (35.700, 34.100),
            (35.710, 34.090),
            (35.720, 34.080),
            (35.730, 34.070),
            (35.740, 34.060),
            (35.750, 34.050),
            (35.760, 34.040),
            (35.770, 34.030),
            (35.780, 34.020),
            (35.790, 34.010),
            (35.800, 34.000),
            (35.810, 33.990),
            (35.820, 33.980),
            (35.830, 33.970),
            (35.840, 33.960),
            (35.850, 33.950),
            (35.860, 33.940),
            (35.870, 33.930),
            (35.880, 33.920),
            (35.890, 33.910),
            (35.900, 33.900),
            (35.5663872, 33.8624512) # Beirut center (approx)
        ]
        # Convert to Point objects (lon, lat)
        polyline = [Point(lon, lat, srid=4326) for lon, lat in batroun_beirut_polyline_coords]

        # Get or create a bus to simulate
        bus, created = Bus.objects.get_or_create(
            plate_number="SIM-001",
            defaults={
                "capacity": 50,
                "speed_mps": random.uniform(5.0, 15.0), # Initial speed
                "current_location": polyline[0],
                "last_reported_at": timezone.now(),
            }
        )
        if created:
            self.stdout.write(self.style.SUCCESS(f"Created new simulated bus: {bus.plate_number}"))
        else:
            self.stdout.write(f"Using existing simulated bus: {bus.plate_number}")

        # Ensure the bus has a trip and route for the frontend to display route name
        route, _ = Route.objects.get_or_create(
            name="Simulated Route Batroun-Beirut",
            defaults={"description": "Simulated route for SIM-001"}
        )
        if not route.geometry:
            route.geometry = LineString(polyline, srid=4326)
            route.save()

        # Ensure the bus has an active trip on this route
        Trip.objects.get_or_create(
            bus=bus,
            route=route,
            defaults={
                "departure_time": timezone.now() - timedelta(minutes=10),
                "estimated_arrival_time": timezone.now() + timedelta(minutes=60),
                "current_location": None # This will be updated by VehiclePosition
            }
        )

        current_segment_idx = 0
        segment_progress = 0.0 # 0.0 to 1.0 along the current segment

        simulation_interval_seconds = 5 # Update bus position every 5 seconds

        self.stdout.write(f"Simulating bus {bus.plate_number} along {route.name}...")
        self.stdout.write("Press Ctrl+C to stop the simulation.")

        while True:
            try:
                # Get current and next point in the polyline
                start_point = polyline[current_segment_idx]
                end_point = polyline[(current_segment_idx + 1) % len(polyline)]

                # Calculate distance of the current segment (in meters, as geography=True)
                segment_distance_m = start_point.distance(end_point)

                # Randomize speed slightly for realism (5-15 m/s, approx 18-54 km/h)
                current_speed_mps = random.uniform(5.0, 15.0)

                # Distance covered in this interval
                distance_covered_m = current_speed_mps * simulation_interval_seconds

                # Update progress along the segment
                if segment_distance_m > 0:
                    segment_progress += distance_covered_m / segment_distance_m
                else:
                    segment_progress = 1.0 # If segment has no length, move to next

                if segment_progress >= 1.0:
                    # Move to the next segment
                    current_segment_idx = (current_segment_idx + 1) % len(polyline)
                    
                    # If we wrapped around, start from the beginning
                    if current_segment_idx == 0:
                        self.stdout.write(self.style.NOTICE("Bus completed route, restarting from beginning."))

                    # Adjust segment_progress if we overshot the previous segment
                    # This ensures smooth transition if distance_covered_m was larger than remaining segment
                    segment_progress = segment_progress - 1.0 # Carry over overshoot

                # Interpolate new position
                new_lon = start_point.x + segment_progress * (end_point.x - start_point.x)
                new_lat = start_point.y + segment_progress * (end_point.y - start_point.y)
                new_location = Point(new_lon, new_lat, srid=4326)

                # Update Bus model's current state
                bus.current_location = new_location
                bus.speed_mps = current_speed_mps # Update the bus's current speed
                bus.last_reported_at = timezone.now()
                bus.save(update_fields=['current_location', 'speed_mps', 'last_reported_at'])

                # Create a new VehiclePosition record for historical tracking
                VehiclePosition.objects.create(
                    bus=bus,
                    location=new_location,
                    speed_mps=current_speed_mps,
                    recorded_at=timezone.now(),
                    heading_deg=random.choice([0.0, 45.0, 90.0, 135.0, 180.0, 225.0, 270.0, 315.0]) # Random heading
                )

                self.stdout.write(
                    f"Bus {bus.plate_number} moved to Lat: {new_lat:.4f}, Lon: {new_lon:.4f} "
                    f"Speed: {current_speed_mps:.1f} m/s ({current_speed_mps * 3.6:.1f} km/h)"
                )

                time.sleep(simulation_interval_seconds)

            except KeyboardInterrupt:
                self.stdout.write(self.style.WARNING("\nBus simulation stopped."))
                break
            except Exception as e:
                self.stdout.write(self.style.ERROR(f"An error occurred during simulation: {e}"))
                time.sleep(simulation_interval_seconds) # Wait before retrying