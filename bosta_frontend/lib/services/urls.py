"""
URL configuration for the 'api' app.
"""
from django.urls import path, include
from api.views import DriverProfileView
from rest_framework_simplejwt.views import (
    TokenObtainPairView,
    TokenRefreshView,
)
from api.views import register_user, driver_onboarding

urlpatterns = [
    # Endpoint for user registration
    path('register/', register_user, name='register'),

    # Endpoint for authenticated driver to get their profile
    path('driver/me/', DriverProfileView.as_view(), name='driver-profile'),
    path('driver/onboard/', driver_onboarding, name='driver-onboard'),

    # SimpleJWT Token URLs
    path('token/', TokenObtainPairView.as_view(), name='token_obtain_pair'),
    path('token/refresh/', TokenRefreshView.as_view(), name='token_refresh'),
]