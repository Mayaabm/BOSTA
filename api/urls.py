# api/urls.py
from django.urls import path
from .views import stops_nearby_view, buses_nearby_view

urlpatterns = [
    path("stops/nearby", stops_nearby_view),
    path("vehicles/nearby", buses_nearby_view),
]
