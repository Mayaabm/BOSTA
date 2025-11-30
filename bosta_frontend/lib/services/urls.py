"""
URL configuration for the 'api' app.
"""
from django.urls import path
from .views import (
    DriverProfileView, register_user, driver_onboarding, start_trip, EndTripView
)
from rest_framework_simplejwt.views import (
    TokenObtainPairView,
    TokenRefreshView,
)

urlpatterns = [
    # Endpoint for user registration
    path('register/', register_user, name='register'),

    # --- Driver Endpoints ---
    path('driver/me/', DriverProfileView.as_view(), name='driver-profile'),
    path('driver/onboard/', driver_onboarding, name='driver-onboard'),

    # --- Trip Endpoints ---
    # This is the new endpoint for creating a trip
    path('trips/start/', start_trip, name='start_trip'), # Correct path for creating a trip
    path('trips/<str:trip_id>/end/', EndTripView.as_view(), name='trip-end'),

    # --- Auth Endpoints ---
    # The login endpoint for drivers, which uses the standard token obtain view.
    path('driver/login/', TokenObtainPairView.as_view(), name='driver-login'),

    path('token/', TokenObtainPairView.as_view(), name='token_obtain_pair'),
    path('token/refresh/', TokenRefreshView.as_view(), name='token_refresh'),
]