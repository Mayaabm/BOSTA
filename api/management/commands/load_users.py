from django.core.management.base import BaseCommand
from django.contrib.gis.geos import Point
from django.contrib.auth import get_user_model
from api.models import CustomUserProfile, Bus

User = get_user_model()

class Command(BaseCommand):
    help = "Create sample users (drivers and commuters) and attach CustomUserProfiles + link drivers to buses."

    def handle(self, *args, **options):
        self.stdout.write("👥 Creating users and profiles...")

        # Clean old data except superuser
        CustomUserProfile.objects.all().delete()
        User.objects.exclude(is_superuser=True).delete()

        # --- Create drivers ---
        drivers = []
        for i in range(3):
            user = User.objects.create_user(
                username=f"driver{i+1}",
                password="pass1234",
                first_name="Driver",
                last_name=str(i + 1)
            )
            profile = CustomUserProfile.objects.create(
                user=user,
                is_driver=True,
                is_commuter=False,
                current_location=Point(35.5 + i * 0.01, 33.9 + i * 0.01, srid=4326),
                destination=Point(35.52, 33.92, srid=4326)
            )
            drivers.append(profile)

        # --- Create commuters ---
        commuters = []
        for i in range(3):
            user = User.objects.create_user(
                username=f"commuter{i+1}",
                password="pass1234",
                first_name="Commuter",
                last_name=str(i + 1)
            )
            profile = CustomUserProfile.objects.create(
                user=user,
                is_driver=False,
                is_commuter=True,
                current_location=Point(35.505 + i * 0.01, 33.905 + i * 0.01, srid=4326),
                destination=Point(35.52, 33.92, srid=4326)
            )
            commuters.append(profile)

        # --- Link drivers to buses ---
        self.stdout.write("🚌 Linking drivers to buses...")
        buses = list(Bus.objects.all())
        for i, driver_profile in enumerate(drivers):
            if i < len(buses):
                buses[i].driver = driver_profile  # link to User, not profile
                buses[i].save()

        self.stdout.write(self.style.SUCCESS("✅ Sample users and profiles created successfully!"))
        self.stdout.write("You can now log in with usernames: driver1–3, commuter1–3 (password: pass1234)")
