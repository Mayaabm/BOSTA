Preparation for Flutter frontend integration

This repository contains the Django backend for the BOSTA project. The following minimal steps prepare the backend for a Flutter frontend to communicate with it (development setup).

What I changed or added (non-functional config only):
- Added `corsheaders` to `INSTALLED_APPS` and `CorsMiddleware` to `MIDDLEWARE` in `myproject/settings.py`.
- Set `CORS_ALLOW_ALL_ORIGINS = True` (development only; tighten for production).
- Added minimal `REST_FRAMEWORK` defaults allowing JSON responses and open permissions for local testing.
- Added `requirements.txt` listing the main packages to install.

How to get ready locally

1. Create and activate a virtual environment (Windows PowerShell):

```powershell
py -3 -m venv .venv
.\.venv\Scripts\Activate.ps1
```

2. Install dependencies:

```powershell
pip install -r requirements.txt
```

3. Run migrations and create a superuser:

```powershell
py manage.py makemigrations
py manage.py migrate
py manage.py createsuperuser
```

4. Run the development server:

```powershell
py manage.py runserver
```

5. API endpoints are mounted under `/api/` (see `api/urls.py`). Example endpoints added by the project:
- `/api/eta/` – estimate arrival time
- `/api/buses_nearby/` – find buses near a lat/lon
- `/api/buses_to_destination/` – find buses heading to a destination

Notes and next steps

- In production, set `CORS_ALLOW_ALL_ORIGINS = False` and configure `CORS_ALLOWED_ORIGINS` with your frontend origin(s).
- Consider adding token-based auth (e.g., DRF TokenAuth or JWT) to secure endpoints.
- Add serializers and viewsets to expose model lists with pagination if the Flutter app needs them.
- If using GIS features in production, ensure PostGIS and system GDAL/GEOS libs are installed and configured.
