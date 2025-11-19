# api/urls.py
from django.urls import path
from api import views

urlpatterns = [
    path('eta/', views.eta),
    path('buses/nearby/', views.buses_nearby),
    path('buses/to_destination/', views.buses_to_destination),
    path('routes/', views.route_list),
    path('routes/<int:route_id>/', views.route_detail),
    path('buses/update_location/', views.update_bus_location),
    # Bus IDs are integer primary keys in this project; accept int here so
    # frontend requests like /api/buses/2 match the view.
    path('buses/<int:bus_id>/', views.get_bus_details, name='get_bus_details'),
    path('driver/login/', views.driver_login, name='driver_login'),
    path('rider/login/', views.rider_login, name='rider_login'),
    path('driver/onboard/', views.driver_onboard, name='driver_onboard'),
    path('driver/me/', views.get_driver_profile, name='get_driver_profile'),
    path('trips/<int:trip_id>/start/', views.start_trip, name='start_trip'),
    path('register/', views.register_user, name='register_user'),
]
