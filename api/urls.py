# api/urls.py
from django.urls import path
from api import views

urlpatterns = [
    path('eta/', views.eta),
    path('buses/nearby/', views.buses_nearby),
    path('buses/to_destination/', views.buses_to_destination),
    path('routes/', views.route_list),
    path('buses/update_location/', views.update_bus_location),
    path('buses/<uuid:bus_id>/', views.get_bus_details, name='get_bus_details'),
    path('driver/login/', views.driver_login, name='driver_login'),
    path('driver/me/', views.get_driver_profile, name='get_driver_profile'),
    path('register/', views.register_user, name='register_user'),
]
