from django.contrib import admin

from django.contrib import admin
from .models import Route, Location

# Register your models so they show up in the admin site
admin.site.register(Route)
admin.site.register(Location)
