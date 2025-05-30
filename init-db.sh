#!/bin/bash

set -e

# Log output to a file for debugging
exec > >(tee -i /tmp/init-db.log) 2>&1
echo "Starting database initialization..."

# Install Python based on available package manager
if command -v apt-get >/dev/null 2>&1; then
    echo "Using apt-get to install Python..."
    apt-get update && apt-get install -y python3 python3-pip
elif command -v apk >/dev/null 2>&1; then
    echo "Using apk to install Python..."
    apk add --no-cache python3 py3-pip
elif command -v yum >/dev/null 2>&1; then
    echo "Using yum to install Python..."
    yum install -y python3 python3-pip
else
    echo "Warning: No supported package manager found. Skipping Python installation."
fi

# Load environment variables from .env file, ignoring comments
if [ -f .env ]; then
    export $(grep -v '^#' .env | xargs)
fi

# Set default PostgreSQL variables
POSTGRES_USER=${POSTGRES_USER:-postgres}
POSTGRES_PASSWORD=${POSTGRES_PASSWORD:-postgres}
POSTGRES_DB=${POSTGRES_DB:-document_processing}
POSTGRES_HOST=${POSTGRES_HOST:-postgres}
POSTGRES_PORT=5432

echo "Hostname: $(hostname)"

echo "Waiting for PostgreSQL to start..."
until PGPASSWORD=$POSTGRES_PASSWORD psql -h $POSTGRES_HOST -p $POSTGRES_PORT -U $POSTGRES_USER -c '\q' 2>/dev/null; do
    echo "PostgreSQL is unavailable - sleeping"
    sleep 2
done

echo "PostgreSQL started"

# Create database if it doesn't exist
PGPASSWORD=$POSTGRES_PASSWORD psql -h $POSTGRES_HOST -p $POSTGRES_PORT -U $POSTGRES_USER -tc "SELECT 1 FROM pg_database WHERE datname = '$POSTGRES_DB'" | grep -q 1 || PGPASSWORD=$POSTGRES_PASSWORD psql -h $POSTGRES_HOST -p $POSTGRES_PORT -U $POSTGRES_USER -c "CREATE DATABASE $POSTGRES_DB"

echo "Database $POSTGRES_DB is ready"

# Create SQL script for table creation and data initialization
cat > create_tables.sql << 'EOF'
-- Enable UUID extension
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Drop tables to ensure clean schema (optional: remove if data persistence is needed)
DROP TABLE IF EXISTS user_roles, role_permissions, refresh_tokens, documents, users, roles, permissions CASCADE;

-- Create tables for user service
CREATE TABLE users (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    username VARCHAR(50) UNIQUE NOT NULL,
    email VARCHAR(100) UNIQUE NOT NULL,
    hashed_password VARCHAR(100) NOT NULL,
    full_name VARCHAR(100),
    is_active BOOLEAN DEFAULT TRUE,
    is_verified BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    last_login TIMESTAMP,
    profile_image VARCHAR(255),
    user_metadata TEXT
);

CREATE TABLE roles (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name VARCHAR(50) UNIQUE NOT NULL,
    description VARCHAR(255),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE permissions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name VARCHAR(100) UNIQUE NOT NULL,
    description VARCHAR(255),
    resource VARCHAR(50) NOT NULL,
    action VARCHAR(50) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE user_roles (
    user_id UUID REFERENCES users(id) ON DELETE CASCADE,
    role_id UUID REFERENCES roles(id) ON DELETE CASCADE,
    PRIMARY KEY (user_id, role_id)
);

CREATE TABLE role_permissions (
    role_id UUID REFERENCES roles(id) ON DELETE CASCADE,
    permission_id UUID REFERENCES permissions(id) ON DELETE CASCADE,
    PRIMARY KEY (role_id, permission_id)
);

CREATE TABLE refresh_tokens (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    token VARCHAR(255) UNIQUE NOT NULL,
    user_id UUID REFERENCES users(id) ON DELETE CASCADE,
    expires_at TIMESTAMP NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    revoked BOOLEAN DEFAULT FALSE,
    revoked_at TIMESTAMP
);

-- Create shared documents table for all document services
CREATE TABLE documents (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    storage_id UUID DEFAULT uuid_generate_v4() UNIQUE NOT NULL,
    document_category VARCHAR(50) NOT NULL,
    title VARCHAR(255) NOT NULL,
    description TEXT,
    file_size INTEGER NOT NULL,
    storage_path VARCHAR(255) NOT NULL,
    original_filename VARCHAR(255) NOT NULL,
    doc_metadata TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    page_count INTEGER,
    is_encrypted BOOLEAN DEFAULT FALSE,
    sheet_count INTEGER,
    compression_type VARCHAR(50),
    file_type VARCHAR(100),
    version INTEGER DEFAULT 1,
    checksum VARCHAR(255),
    source_service VARCHAR(50) DEFAULT 'files'
);

-- Create indexes
CREATE INDEX IF NOT EXISTS idx_documents_category ON documents(document_category);
CREATE INDEX IF NOT EXISTS idx_documents_user_id ON documents(user_id);
CREATE INDEX IF NOT EXISTS idx_documents_cat_user ON documents(document_category, user_id);

-- Insert default roles
INSERT INTO roles (name, description) 
VALUES ('admin', 'Administrator role with full access') 
ON CONFLICT (name) DO NOTHING;

INSERT INTO roles (name, description) 
VALUES ('user', 'Regular user role with limited access') 
ON CONFLICT (name) DO NOTHING;

-- Insert default permissions
INSERT INTO permissions (name, description, resource, action)
VALUES ('user:read', 'Read user information', 'user', 'read')
ON CONFLICT (name) DO NOTHING;

INSERT INTO permissions (name, description, resource, action)
VALUES ('user:write', 'Create or update user information', 'user', 'write')
ON CONFLICT (name) DO NOTHING;

INSERT INTO permissions (name, description, resource, action)
VALUES ('document:read', 'Read documents', 'document', 'read')
ON CONFLICT (name) DO NOTHING;

INSERT INTO permissions (name, description, resource, action)
VALUES ('document:write', 'Create or update documents', 'document', 'write')
ON CONFLICT (name) DO NOTHING;

INSERT INTO permissions (name, description, resource, action)
VALUES ('document:delete', 'Delete documents', 'document', 'delete')
ON CONFLICT (name) DO NOTHING;

-- Assign permissions to roles
INSERT INTO role_permissions (role_id, permission_id)
SELECT r.id, p.id FROM roles r, permissions p
WHERE r.name = 'admin' AND p.name IN ('user:read', 'user:write', 'document:read', 'document:write', 'document:delete')
ON CONFLICT DO NOTHING;

INSERT INTO role_permissions (role_id, permission_id)
SELECT r.id, p.id FROM roles r, permissions p
WHERE r.name = 'user' AND p.name IN ('document:read', 'document:write')
ON CONFLICT DO NOTHING;

-- Create admin user if not exists
INSERT INTO users (username, email, hashed_password, full_name, is_active, is_verified)
VALUES ('admin', 'admin@admin.com', '$2b$12$BmQVt7Z6UlJPU3olJ3yK2eJIBp7dIrTMWNJiOoIXoplkQxfIvfgPe', 'Admin User', true, true)
ON CONFLICT (username) DO NOTHING;

-- Assign admin role to admin user
INSERT INTO user_roles (user_id, role_id)
SELECT u.id, r.id FROM users u, roles r
WHERE u.username = 'admin' AND r.name = 'admin'
ON CONFLICT DO NOTHING;
EOF

# Execute the SQL script
echo "Executing create_tables.sql..."
PGPASSWORD=$POSTGRES_PASSWORD psql -h $POSTGRES_HOST -p $POSTGRES_PORT -U $POSTGRES_USER -d $POSTGRES_DB -f create_tables.sql

echo "Database initialization completed successfully"