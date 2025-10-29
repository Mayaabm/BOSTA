from django.contrib import admin

from django.contrib import admin
from .models import Route, Stop, Bus, Trip, VehiclePosition, CustomUserProfile

# Register your models so they show up in the admin site
admin.site.register(Route)
admin.site.register(Stop)
admin.site.register(Bus)
admin.site.register(Trip)
admin.site.register(VehiclePosition)
admin.site.register(CustomUserProfile)
