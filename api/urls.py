# api/urls.py
from django.urls import path
from api import views
print("--- Loading api/urls.py ---")

urlpatterns = [
    path('eta/', views.eta),
    path('buses/nearby/', views.buses_nearby),
    path('buses/to_destination/', views.buses_to_destination),
    path('buses/for_route/', views.buses_for_route, name='buses_for_route'),
    path('routes/', views.route_list),
    path('routes/<int:route_id>/', views.route_detail),
    path('buses/update_location/', views.update_bus_location),
    # Bus IDs are integer primary keys in this project; accept int here so
    # frontend requests like /api/buses/2 match the view.
    path('buses/<int:bus_id>/', views.get_bus_details, name='get_bus_details'),
    path('driver/login/', views.driver_login, name='driver_login'),
    path('rider/login/', views.rider_login, name='rider_login'),
    path('driver/onboard/', views.driver_onboard, name='driver_onboard'),
    path('driver/me/', views.get_driver_profile, name='get_driver_profile'), # Correctly reference the function view
    path('trips/<str:trip_id>/start/', views.start_trip, name='start_trip'),
    path('trips/create_and_start/', views.create_and_start_trip, name='create_and_start_trip'),
    path('trips/<str:trip_id>/end/', views.EndTripView.as_view(), name='trip-end'),
    # Dev-only endpoint for mock rider location
    path('dev/rider_location/', views.get_dev_rider_location, name='get_dev_rider_location'),
    path('register/', views.register_user, name='register_user'),
    path('plan_trip/', views.plan_trip, name='plan_trip'),
    path('stops/', views.stop_list, name='stop_list'),
]

print("--- Finished loading api/urls.py ---")
