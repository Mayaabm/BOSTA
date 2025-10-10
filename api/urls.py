# api/urls.py
from django.urls import path
from .views import stops_nearby_view, buses_nearby_view
from api import views

urlpatterns = [
    path('eta/', views.eta),

]
