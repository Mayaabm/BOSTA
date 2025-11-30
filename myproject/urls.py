"""
Main URL configuration for myproject.

The `urlpatterns` list routes URLs to views. For more information please see:
    https://docs.djangoproject.com/en/stable/topics/http/urls/

This configuration includes the URLs from the 'api' app under the 'api/' prefix.
"""
from django.contrib import admin
from django.urls import path, include

print("--- Loading myproject/urls.py ---")

urlpatterns = [
    # Admin site URL
    path('admin/', admin.site.urls),

    # Include all URLs from the 'api' app under the 'api/' prefix.
    # This is the crucial part that makes your API endpoints available.
    # For example, 'driver/login/' in the api app will be accessible at '/api/driver/login/'.
    path('api/', include('api.urls')),
]

print("--- Finished loading myproject/urls.py ---")