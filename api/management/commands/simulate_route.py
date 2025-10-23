import time
import random
from datetime import timedelta

from django.core.management.base import BaseCommand
from django.contrib.gis.geos import Point, LineString
from django.utils import timezone

from api.models import Bus, VehiclePosition, Route, Trip

class Command(BaseCommand):
    help = "Simulates multiple buses moving along a specific route from Jbeil to Batroun."

    def handle(self, *args, **options):
        self.stdout.write("🚌 Starting Jbeil -> Batroun route simulation...")
        simulation_interval_seconds = 5

        # A more detailed route from near Jbeil to Batroun.
        # In a real app, this would come from OSRM or a similar service.
        route_coords = [
            (35.643100, 34.147900), # Start near Jbeil
            (35.6445, 34.1520),
            (35.6460, 34.1570),
            (35.6480, 34.1620),
            (35.6500, 34.1680),
            (35.6525, 34.1750),
            (35.6550, 34.1830),
            (35.6570, 34.1900),
            (35.6585, 34.1980),
            (35.6590, 34.2050),
            (35.6580, 34.2120),
            (35.6560, 34.2190),
            (35.6540, 34.2260),
            (35.6520, 34.2330),
            (35.6500, 34.2400),
            (35.6480, 34.2470),
            (35.6547, 34.2559), # End near Batroun
        ]
        polyline = [Point(lon, lat, srid=4326) for lon, lat in route_coords]

        # Create the Route object
        route, _ = Route.objects.update_or_create(
            name="Jbeil-Batroun Express",
            defaults={
                "description": "A simulated express route from Jbeil to Batroun.",
                "geometry": LineString(polyline, srid=4326)
            }
        )

        # Initialize 3 buses for this route
        buses_to_simulate = []
        for i in range(3):
            bus, _ = Bus.objects.get_or_create(
                plate_number=f"JB-EXP-{i+1:03}",
                defaults={"capacity": 50}
            )
            
            # Ensure the bus has an active trip on this route
            Trip.objects.get_or_create(
                bus=bus,
                route=route,
                defaults={
                    "departure_time": timezone.now() - timedelta(minutes=10),
                    "estimated_arrival_time": timezone.now() + timedelta(minutes=60),
                }
            )

            # Stagger the starting positions of the buses
            start_segment = (i * 5) % (len(polyline) -1)
            buses_to_simulate.append({
                "bus": bus,
                "segment_idx": start_segment,
                "progress": 0.0, # 0.0 to 1.0 along the current segment
            })

        self.stdout.write(f"✅ {len(buses_to_simulate)} buses initialized. Starting simulation... (Ctrl+C to stop)")

        while True:
            try:
                for sim_bus in buses_to_simulate:
                    bus = sim_bus["bus"]
                    
                    start_point = polyline[sim_bus["segment_idx"]]
                    # Loop back to the start if it reaches the end
                    next_idx = (sim_bus["segment_idx"] + 1) % len(polyline)
                    if next_idx == 0: # Reached the end of the line
                        sim_bus["segment_idx"] = 0
                        sim_bus["progress"] = 0.0
                        self.stdout.write(self.style.NOTICE(f"Bus {bus.plate_number} reached destination, restarting."))
                        continue

                    end_point = polyline[next_idx]
                    
                    segment_distance_m = start_point.distance(end_point)
                    current_speed_mps = random.uniform(10.0, 18.0) # Approx 36-65 km/h

                    # Calculate progress for this interval
                    progress_step = (current_speed_mps * simulation_interval_seconds) / segment_distance_m if segment_distance_m > 0 else 1.0
                    sim_bus["progress"] += progress_step

                    # If we passed the end point, move to the next segment
                    if sim_bus["progress"] >= 1.0:
                        sim_bus["segment_idx"] += 1
                        sim_bus["progress"] -= 1.0 # Carry over the remainder

                    # Interpolate new position
                    new_lon = start_point.x + sim_bus["progress"] * (end_point.x - start_point.x)
                    new_lat = start_point.y + sim_bus["progress"] * (end_point.y - start_point.y)
                    new_location = Point(new_lon, new_lat, srid=4326)

                    # Update Bus model for real-time APIs
                    bus.current_location = new_location
                    bus.speed_mps = current_speed_mps
                    bus.last_reported_at = timezone.now()
                    bus.save(update_fields=['current_location', 'speed_mps', 'last_reported_at'])

                    self.stdout.write(f"🚌 {bus.plate_number} -> Lat:{new_lat:.5f}, Lon:{new_lon:.5f}")

                time.sleep(simulation_interval_seconds)
            except KeyboardInterrupt:
                self.stdout.write(self.style.WARNING("\n🛑 Simulation stopped manually."))
                break