# api/urls.py
from django.urls import path
from .views import get_buses
from.views import buses_near_location

urlpatterns = [
    path('buses/', get_buses),
     path('buses/near/', buses_near_location),
]
