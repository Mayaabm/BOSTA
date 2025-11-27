@echo off
REM This script starts both servers to allow testing the web app from other devices on the same network.

REM !!! IMPORTANT !!!
REM Replace '192.168.1.102' below with your computer's actual local IP address.
SET MY_LOCAL_IP=192.168.1.102

ECHO Starting Django backend server on all network interfaces...
REM We run Django on 0.0.0.0:8000 to make it accessible from your phone.
START "Django Backend (Network)" cmd /k "venv312\Scripts\activate.bat && python manage.py runserver 0.0.0.0:8000"

ECHO Starting Flutter frontend dev server on all network interfaces...
REM We run Flutter on hostname 0.0.0.0 to make it accessible from your phone.
REM We use --dart-define to tell the app the backend's IP address.
START "Flutter Frontend (Network)" cmd /k "cd bosta_frontend && flutter run -d chrome --web-hostname=0.0.0.0 --web-port=3000 --dart-define=BACKEND_HOST=%MY_LOCAL_IP%"

ECHO.
ECHO --- Servers are starting in separate windows ---
ECHO.
ECHO To test on THIS computer, open your browser and go to:
ECHO.
ECHO   http://localhost:3000
ECHO To test on your phone, open your phone's browser and go to:
ECHO.
ECHO   http://%MY_LOCAL_IP%:3000
ECHO.
ECHO Make sure your phone is connected to the same Wi-Fi network as this computer.
