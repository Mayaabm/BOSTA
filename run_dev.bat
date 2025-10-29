@echo off
REM This script starts both the Django backend and the Flutter frontend for development.

ECHO Starting Django backend server in a new window...
REM The 'START' command runs the following command in a new command prompt window.
REM The `cmd /k` part keeps the window open so you can see server logs and errors.
START "Django Backend" cmd /k "venv312\Scripts\activate.bat && python manage.py runserver"

ECHO Starting Flutter frontend dev server in a new window...
REM We change into the frontend directory first, then start the flutter process.
START "Flutter Frontend" cmd /k "cd bosta_frontend && flutter run -d chrome --web-port=3000"

ECHO Both servers are starting in separate windows.
@echo off
REM This script starts both the Django backend and the Flutter frontend for development.

ECHO Starting Django backend server in a new window...
REM The 'START' command runs the following command in a new command prompt window.
REM The `cmd /k` part keeps the window open so you can see server logs and errors.
START "Django Backend" cmd /k "venv312\Scripts\activate.bat && python manage.py runserver"

ECHO Starting Flutter frontend dev server in a new window...
REM We change into the frontend directory first, then start the flutter process.
START "Flutter Frontend" cmd /k "cd bosta_frontend && flutter run -d chrome --web-port=3000"

ECHO Both servers are starting in separate windows.