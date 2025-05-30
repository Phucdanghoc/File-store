@echo off
setlocal EnableDelayedExpansion

echo === Khoi dong he thong xu ly tai lieu ===
echo Su dung docker-compose...

:: Tạo các thư mục cần thiết
mkdir data\minio 2>nul
mkdir data\rabbitmq 2>nul

mkdir gateway\src\temp 2>nul
mkdir service-word\src\temp 2>nul
mkdir service-word\src\templates 2>nul
mkdir service-excel\src\temp 2>nul
mkdir service-excel\src\templates 2>nul
mkdir service-pdf\src\temp 2>nul
mkdir service-pdf\src\templates 2>nul
mkdir service-files\src\temp 2>nul
mkdir service-files\src\templates 2>nul
mkdir service-user\src\temp 2>nul
mkdir service-user\src\templates 2>nul

:: Không cần chmod trên Windows, bỏ qua việc cấp quyền thực thi cho file .py
:: Nếu cần, có thể đảm bảo các file Python có thể chạy bằng cách kiểm tra Python đã cài đặt

:: Kiểm tra Docker
where docker >nul 2>&1
if %ERRORLEVEL% neq 0 (
    echo Docker chua duoc cai dat. Vui long cai dat Docker truoc.
    exit /b 1
)

:: Kiểm tra Docker Compose
where docker-compose >nul 2>&1
if %ERRORLEVEL% neq 0 (
    echo Docker Compose chua duoc cai dat. Vui long cai dat Docker Compose truoc.
    exit /b 1
)

echo Khoi dong dich vu...
docker-compose up -d

echo Dang cho cac dich vu khoi dong...
timeout /t 10 >nul

echo Kiem tra trang thai dich vu...
docker-compose ps

echo.
echo === He thong xu ly tai lieu da khoi dong ===
echo - Gateway API: http://localhost:10000/docs
echo - Word Service: http://localhost:10001/docs
echo - Excel Service: http://localhost:10002/docs
echo - PDF Service: http://localhost:10003/docs
echo - Files Service: http://localhost:10004/docs
echo - User Service: http://localhost:10005/docs
echo - PostgreSQL: http://localhost:6006
echo - RabbitMQ Management: http://localhost:15672
echo - MinIO Console: http://localhost:9001
echo   Username: admin
echo   Admin Email: admin@admin.com
echo   Password: password123
echo   MinIO Username: minioadmin
echo   MinIO Password: minioadmin
echo.
echo De dung he thong, su dung lenh: stop.bat

endlocal