@echo off
setlocal EnableDelayedExpansion

:: Thiết lập biến môi trường từ file .env (nếu có)
if exist .env (
    for /f "tokens=1,2 delims==" %%a in (.env) do (
        if not "%%a"=="#" (
            set %%a=%%b
        )
    )
)

:: Thiết lập các biến mặc định cho PostgreSQL
set POSTGRES_USER=%POSTGRES_USER:postgres%
set POSTGRES_PASSWORD=%POSTGRES_PASSWORD:postgres%
set POSTGRES_DB=%POSTGRES_DB:document_processing%
set POSTGRES_HOST=%POSTGRES_HOST:postgres%
set POSTGRES_PORT=5432

:: In tên máy chủ
echo %COMPUTERNAME%

:: Chờ PostgreSQL khởi động
echo Waiting for PostgreSQL to start...
:check_postgres
set PGPASSWORD=%POSTGRES_PASSWORD%
psql -h %POSTGRES_HOST% -p %POSTGRES_PORT% -U %POSTGRES_USER% -c "\q" 2>nul
if %ERRORLEVEL% neq 0 (
    echo PostgreSQL is unavailable - sleeping
    timeout /t 2 >nul
    goto check_postgres
)

echo PostgreSQL started

:: Kiểm tra và tạo cơ sở dữ liệu nếu chưa tồn tại
psql -h %POSTGRES_HOST% -p %POSTGRES_PORT% -U %POSTGRES_USER% -t -c "SELECT 1 FROM pg_database WHERE datname = '%POSTGRES_DB%'" | findstr /r "^ *1 *$" >nul
if %ERRORLEVEL% neq 0 (
    psql -h %POSTGRES_HOST% -p %POSTGRES_PORT% -U %POSTGRES_USER% -c "CREATE DATABASE %POSTGRES_DB%"
)

echo Database %POSTGRES_DB% is ready

:: Tạo file SQL tạm thời
echo -- Enable UUID extension > create_tables.sql
echo CREATE EXTENSION IF NOT EXISTS "uuid-ossp"; >> create_tables.sql
echo. >> create_tables.sql
echo -- Create tables for user service >> create_tables.sql
echo CREATE TABLE IF NOT EXISTS users ( >> create_tables.sql
echo     id UUID PRIMARY KEY DEFAULT uuid_generate_v4(), >> create_tables.sql
echo     username VARCHAR(50) UNIQUE NOT NULL, >> create_tables.sql
echo     email VARCHAR(100) UNIQUE NOT NULL, >> create_tables.sql
echo     hashed_password VARCHAR(100) NOT NULL, >> create_tables.sql
echo     full_name VARCHAR(100), >> create_tables.sql
echo     is_active BOOLEAN DEFAULT TRUE, >> create_tables.sql
echo     is_verified BOOLEAN DEFAULT FALSE, >> create_tables.sql
echo     created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP, >> create_tables.sql
echo     updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP, >> create_tables.sql
echo     last_login TIMESTAMP, >> create_tables.sql
echo     profile_image VARCHAR(255), >> create_tables.sql
echo     user_metadata TEXT >> create_tables.sql
echo ); >> create_tables.sql
echo. >> create_tables.sql
echo CREATE TABLE IF NOT EXISTS roles ( >> create_tables.sql
echo     id UUID PRIMARY KEY DEFAULT uuid_generate_v4(), >> create_tables.sql
echo     name VARCHAR(50) UNIQUE NOT NULL, >> create_tables.sql
echo     description VARCHAR(255), >> create_tables.sql
echo     created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP, >> create_tables.sql
echo     updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP >> create_tables.sql
echo ); >> create_tables.sql
echo. >> create_tables.sql
echo CREATE TABLE IF NOT EXISTS permissions ( >> create_tables.sql
echo     id UUID PRIMARY KEY DEFAULT uuid_generate_v4(), >> create_tables.sql
echo     name VARCHAR(100) UNIQUE NOT NULL, >> create_tables.sql
echo     description VARCHAR(255), >> create_tables.sql
echo     resource VARCHAR(50) NOT NULL, >> create_tables.sql
echo     action VARCHAR(50) NOT NULL, >> create_tables.sql
echo     created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP >> create_tables.sql
echo ); >> create_tables.sql
echo. >> create_tables.sql
echo CREATE TABLE IF NOT EXISTS user_roles ( >> create_tables.sql
echo     user_id UUID REFERENCES users(id), >> create_tables.sql
echo     role_id UUID REFERENCES roles(id), >> create_tables.sql
echo     PRIMARY KEY (user_id, role_id) >> create_tables.sql
echo ); >> create_tables.sql
echo. >> create_tables.sql
echo CREATE TABLE IF NOT EXISTS role_permissions ( >> create_tables.sql
echo     role_id UUID REFERENCES roles(id), >> create_tables.sql
echo     permission_id UUID REFERENCES permissions(id), >> create_tables.sql
echo     PRIMARY KEY (role_id, permission_id) >> create_tables.sql
echo ); >> create_tables.sql
echo. >> create_tables.sql
echo CREATE TABLE IF NOT EXISTS refresh_tokens ( >> create_tables.sql
echo     id UUID PRIMARY KEY DEFAULT uuid_generate_v4(), >> create_tables.sql
echo     token VARCHAR(255) UNIQUE NOT NULL, >> create_tables.sql
echo     user_id UUID REFERENCES users(id), >> create_tables.sql
echo     expires_at TIMESTAMP NOT NULL, >> create_tables.sql
echo     created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP, >> create_tables.sql
echo     revoked BOOLEAN DEFAULT FALSE, >> create_tables.sql
echo     revoked_at TIMESTAMP >> create_tables.sql
echo ); >> create_tables.sql
echo. >> create_tables.sql
echo -- Create shared documents table for all document services >> create_tables.sql
echo CREATE TABLE IF NOT EXISTS documents ( >> create_tables.sql
echo     id UUID PRIMARY KEY DEFAULT uuid_generate_v4(), >> create_tables.sql
echo     storage_id UUID DEFAULT uuid_generate_v4() UNIQUE NOT NULL, >> create_tables.sql
echo     document_category VARCHAR(50) NOT NULL, >> create_tables.sql
echo     title VARCHAR(255) NOT NULL, >> create_tables.sql
echo     description TEXT, >> create_tables.sql
echo     file_size INTEGER NOT NULL, >> create_tables.sql
echo     storage_path VARCHAR(255) NOT NULL, >> create_tables.sql
echo     original_filename VARCHAR(255) NOT NULL, >> create_tables.sql
echo     doc_metadata TEXT, >> create_tables.sql
echo     created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP, >> create_tables.sql
echo     updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP, >> create_tables.sql
echo     user_id UUID NOT NULL REFERENCES users(id), >> create_tables.sql
echo     page_count INTEGER, >> create_tables.sql
echo     is_encrypted BOOLEAN DEFAULT FALSE, >> create_tables.sql
echo     sheet_count INTEGER, >> create_tables.sql
echo     compression_type VARCHAR(50), >> create_tables.sql
echo     file_type VARCHAR(100), >> create_tables.sql
echo     version INTEGER DEFAULT 1, >> create_tables.sql
echo     checksum VARCHAR(255), >> create_tables.sql
echo     source_service VARCHAR(50) DEFAULT 'files' >> create_tables.sql
echo ); >> create_tables.sql
echo. >> create_tables.sql
echo -- Create index on document_category and user_id >> create_tables.sql
echo CREATE INDEX IF NOT EXISTS idx_documents_category ON documents(document_category); >> create_tables.sql
echo CREATE INDEX IF NOT EXISTS idx_documents_user_id ON documents(user_id); >> create_tables.sql
echo CREATE INDEX IF NOT EXISTS idx_documents_cat_user ON documents(document_category, user_id); >> create_tables.sql
echo. >> create_tables.sql
echo -- Insert default roles >> create_tables.sql
echo INSERT INTO roles (name, description) >> create_tables.sql
echo VALUES ('admin', 'Administrator role with full access') >> create_tables.sql
echo ON CONFLICT (name) DO NOTHING; >> create_tables.sql
echo. >> create_tables.sql
echo INSERT INTO roles (name, description) >> create_tables.sql
echo VALUES ('user', 'Regular user role with limited access') >> create_tables.sql
echo ON CONFLICT (name) DO NOTHING; >> create_tables.sql
echo. >> create_tables.sql
echo -- Insert default permissions >> create_tables.sql
echo INSERT INTO permissions (name, description, resource, action) >> create_tables.sql
echo VALUES ('user:read', 'Read user information', 'user', 'read') >> create_tables.sql
echo ON CONFLICT (name) DO NOTHING; >> create_tables.sql
echo. >> create_tables.sql
echo INSERT INTO permissions (name, description, resource, action) >> create_tables.sql
echo VALUES ('user:write', 'Create or update user information', 'user', 'write') >> create_tables.sql
echo ON CONFLICT (name) DO NOTHING; >> create_tables.sql
echo. >> create_tables.sql
echo INSERT INTO permissions (name, description, resource, action) >> create_tables.sql
echo VALUES ('document:read', 'Read documents', 'document', 'read') >> create_tables.sql
echo ON CONFLICT (name) DO NOTHING; >> create_tables.sql
echo. >> create_tables.sql
echo INSERT INTO permissions (name, description, resource, action) >> create_tables.sql
echo VALUES ('document:write', 'Create or update documents', 'document', 'write') >> create_tables.sql
echo ON CONFLICT (name) DO NOTHING; >> create_tables.sql
echo. >> create_tables.sql
echo INSERT INTO permissions (name, description, resource, action) >> create_tables.sql
echo VALUES ('document:delete', 'Delete documents', 'document', 'delete') >> create_tables.sql
echo ON CONFLICT (name) DO NOTHING; >> create_tables.sql
echo. >> create_tables.sql
echo -- Assign permissions to roles >> create_tables.sql
echo INSERT INTO role_permissions (role_id, permission_id) >> create_tables.sql
echo SELECT r.id, p.id FROM roles r, permissions p >> create_tables.sql
echo WHERE r.name = 'admin' AND p.name IN ('user:read', 'user:write', 'document:read', 'document:write', 'document:delete') >> create_tables.sql
echo ON CONFLICT DO NOTHING; >> create_tables.sql
echo. >> create_tables.sql
echo INSERT INTO role_permissions (role_id, permission_id) >> create_tables.sql
echo SELECT r.id, p.id FROM roles r, permissions p >> create_tables.sql
echo WHERE r.name = 'user' AND p.name IN ('document:read', 'document:write') >> create_tables.sql
echo ON CONFLICT DO NOTHING; >> create_tables.sql
echo. >> create_tables.sql
echo -- Create admin user if not exists >> create_tables.sql
echo INSERT INTO users (username, email, hashed_password, full_name, is_active, is_verified) >> create_tables.sql
echo VALUES ('admin', 'admin@admin.com', '$2b$12$BmQVt7Z6UlJPU3olJ3yK2eJIBp7dIrTMWNJiOoIXoplkQxfIvfgPe', 'Admin User', true, true) >> create_tables.sql
echo ON CONFLICT (username) DO NOTHING; >> create_tables.sql
echo. >> create_tables.sql
echo -- Assign admin role to admin user >> create_tables.sql
echo INSERT INTO user_roles (user_id, role_id) >> create_tables.sql
echo SELECT u.id, r.id FROM users u, roles r >> create_tables.sql
echo WHERE u.username = 'admin' AND r.name = 'admin' >> create_tables.sql
echo ON CONFLICT DO NOTHING; >> create_tables.sql

:: Chạy file SQL
set PGPASSWORD=%POSTGRES_PASSWORD%
psql -h %POSTGRES_HOST% -p %POSTGRES_PORT% -U %POSTGRES_USER% -d %POSTGRES_DB% -f create_tables.sql
if %ERRORLEVEL% neq 0 (
    echo Failed to initialize database
    exit /b 1
)

echo Database initialization completed successfully

:: Xóa file SQL tạm thời
del create_tables.sql

endlocal