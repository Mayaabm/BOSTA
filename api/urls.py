# api/urls.py
from django.urls import path
from .views import  eta,buses_nearby, buses_to_destination, route_list
from api import views

urlpatterns = [
    path('eta/', views.eta),
    path('buses_nearby/', buses_nearby),
    path('buses_to_destination/', buses_to_destination),
    path('routes/', route_list),


]
