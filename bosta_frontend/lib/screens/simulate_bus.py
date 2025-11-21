import time
from django.core.management.base import BaseCommand, CommandError
from django.contrib.gis.geos import Point
from django.contrib.gis.db.models.functions import LineLocatePoint
from buses.models import Bus, Route

class Command(BaseCommand):
    help = 'Simulates a bus moving along a specified route.'

    def add_arguments(self, parser):
        parser.add_argument('bus_id', type=int, help='The ID of the bus to simulate.')
        parser.add_argument('route_id', type=int, help='The ID of the route to follow.')
        parser.add_argument(
            '--speed',
            type=float,
            default=40.0,
            help='Simulated speed in km/h. Default is 40.'
        )
        parser.add_argument(
            '--interval',
            type=int,
            default=5,
            help='Update interval in seconds. Default is 5.'
        )

    def handle(self, *args, **options):
        bus_id = options['bus_id']
        route_id = options['route_id']
        speed_kph = options['speed']
        interval_seconds = options['interval']

        try:
            bus = Bus.objects.get(pk=bus_id)
            self.stdout.write(self.style.SUCCESS(f'Found bus: {bus.plate_number} (ID: {bus.id})'))
        except Bus.DoesNotExist:
            raise CommandError(f'Bus with ID "{bus_id}" does not exist.')

        try:
            route = Route.objects.get(pk=route_id)
            self.stdout.write(self.style.SUCCESS(f'Found route: {route.name} (ID: {route.id})'))
        except Route.DoesNotExist:
            raise CommandError(f'Route with ID "{route_id}" does not exist.')

        if not route.geometry:
            raise CommandError('The selected route has no geometry data.')

        # --- Simulation Logic ---
        speed_mps = speed_kph * 1000 / 3600  # Convert km/h to m/s
        route_length_meters = route.geometry.length
        self.stdout.write(f'Route length: {route_length_meters:.2f} meters.')
        self.stdout.write(f'Simulating at {speed_kph} km/h ({speed_mps:.2f} m/s), updating every {interval_seconds}s.')
        self.stdout.write(self.style.WARNING('Press Ctrl+C to stop the simulation.'))

        distance_traveled_meters = 0

        try:
            while distance_traveled_meters <= route_length_meters:
                # Calculate the fraction of the route completed
                fraction = distance_traveled_meters / route_length_meters
                
                # Interpolate the point on the line
                new_point = route.geometry.interpolate(fraction, normalized=True)

                # Update the bus location in the database
                bus.location = Point(new_point.x, new_point.y, srid=route.geometry.srid)
                bus.save()

                self.stdout.write(
                    f'Updating bus location... Progress: {fraction*100:.1f}% '
                    f'({distance_traveled_meters:.0f}m / {route_length_meters:.0f}m) '
                    f'Coords: ({new_point.y:.5f}, {new_point.x:.5f})'
                )

                # Wait for the next interval
                time.sleep(interval_seconds)

                # Increment distance for the next iteration
                distance_traveled_meters += speed_mps * interval_seconds

            self.stdout.write(self.style.SUCCESS('Simulation finished: Reached end of route.'))

        except KeyboardInterrupt:
            self.stdout.write(self.style.WARNING('\nSimulation stopped by user.'))
