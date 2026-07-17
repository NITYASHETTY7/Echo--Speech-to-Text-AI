@echo off
REM ============================================================
REM  Echo - start local backend services (for local testing)
REM  Double-click this after a PC restart, BEFORE launching Echo.
REM  It starts the local database (dynalite) + the DB browser.
REM  Leave the two windows it opens running while you use Echo.
REM ============================================================
cd /d "%~dp0"

echo Starting Echo local database (dynalite) on http://localhost:8000 ...
start "Echo DB (dynalite)" cmd /k dynalite --port 8000 --path "%~dp0dynalite-data"

REM give dynalite a moment to bind the port
timeout /t 2 /nobreak >nul

echo Starting DB browser (dynamodb-admin) on http://localhost:8001 ...
start "Echo DB Browser" cmd /k "set DYNAMO_ENDPOINT=http://localhost:8000 && dynamodb-admin"

echo.
echo ============================================================
echo  Local DB     : http://localhost:8000   (data: dynalite-data\)
echo  DB browser   : http://localhost:8001   (open in a browser)
echo.
echo  Keep the two opened windows running while using Echo.
echo  Closing them stops the local database.
echo ============================================================
echo.
pause
