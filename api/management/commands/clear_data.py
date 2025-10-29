from django.core.management.base import BaseCommand
from django.db import transaction
from api.models import Route, Stop, Trip, VehiclePosition, Bus, CustomUserProfile

class Command(BaseCommand):
    help = "Clears all data from the Route, Stop, Trip, and VehiclePosition tables."

    def handle(self, *args, **options):
        self.stdout.write(self.style.WARNING('This will delete all Route, Stop, Trip, and VehiclePosition data.'))
        confirmation = input('Are you sure you want to continue? (y/n): ')

        if confirmation.lower() != 'y':
            self.stdout.write(self.style.NOTICE('Operation cancelled.'))
            return

        with transaction.atomic():
            self.stdout.write("Deleting VehiclePosition records...")
            VehiclePosition.objects.all().delete()
            self.stdout.write("Deleting Trip records...")
            Trip.objects.all().delete()
            self.stdout.write("Deleting Stop records...")
            Stop.objects.all().delete()
            self.stdout.write("Deleting Route records...")
            Route.objects.all().delete()
            self.stdout.write("Deleting Bus records...")
            Bus.objects.all().delete()
            self.stdout.write("Deleting CustomUserProfile records...")
            CustomUserProfile.objects.all().delete()

        self.stdout.write(self.style.SUCCESS('✅ All specified table data has been cleared.'))