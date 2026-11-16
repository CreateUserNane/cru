# cru

Flutter account app with a Laravel 13 API, Sanctum bearer-token authentication, and MySQL storage.

## Start the API

Requirements: PHP 8.3+, Composer, and MySQL.

1. Create an empty MySQL database named `cru` (or change `DB_DATABASE` in `backend/.env`).
2. Copy `backend/.env.example` to `backend/.env` and set `DB_HOST`, `DB_PORT`, `DB_DATABASE`, `DB_USERNAME`, and `DB_PASSWORD` for your MySQL instance.
3. Run:

   ```powershell
   cd backend
   composer install
   php artisan key:generate
   php artisan migrate
   php artisan serve --host 0.0.0.0
   ```

The API is available at `http://localhost:8000/api`. Endpoints are `POST /register`, `POST /login`, `GET /user`, `PUT /user`, and `POST /logout`. Authenticated requests use `Authorization: Bearer <token>`.

## Run the Flutter app

In another terminal, from the repository root:

```powershell
flutter pub get
flutter run
```

The app automatically uses `http://localhost:8000/api` for web, desktop, and iOS simulator, and `http://10.0.2.2:8000/api` for the Android emulator. For a physical phone, use the computer's LAN IP and start Laravel with `--host 0.0.0.0`, for example `flutter run --dart-define=API_BASE_URL=http://192.168.1.20:8000/api`.

The app stores its Sanctum token with the platform's secure storage and restores the signed-in user when reopened.

Local HTTP is enabled for emulator/device development. Use HTTPS and remove the Android cleartext allowance before deploying the API publicly.
