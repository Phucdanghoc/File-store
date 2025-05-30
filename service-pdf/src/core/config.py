import os
from pydantic_settings import BaseSettings
from typing import List, Dict, Any, Optional


class Settings(BaseSettings):
    PROJECT_NAME: str = "PDF Document Service"
    PROJECT_DESCRIPTION: str = "Dịch vụ xử lý tài liệu PDF và hình ảnh PNG"
    PROJECT_VERSION: str = "1.0.0"

    API_V1_STR: str = "/api/v1"
    HOST: str = "0.0.0.0"
    PORT: int = 10003
    DEBUG_MODE: bool = os.getenv("APP_ENV", "development") == "development"
    WORKERS: int = 1

    ALLOWED_ORIGINS: List[str] = ["*"]

    # Database settings
    DATABASE_URL: str = os.getenv("DATABASE_URL", "postgresql://postgres:postgres@postgres:5432/document_processing")
    DEBUG: bool = os.getenv("APP_ENV", "development") == "development"

    RABBITMQ_HOST: str = os.getenv("RABBITMQ_HOST", "rabbitmq")
    RABBITMQ_PORT: int = int(os.getenv("RABBITMQ_PORT", "5672"))
    RABBITMQ_USER: str = os.getenv("RABBITMQ_USER", "admin")
    RABBITMQ_PASS: str = os.getenv("RABBITMQ_PASS", "adminpassword")
    RABBITMQ_VHOST: str = os.getenv("RABBITMQ_VHOST", "/")

    MINIO_HOST: str = os.getenv("MINIO_HOST", "minio")
    MINIO_PORT: int = int(os.getenv("MINIO_PORT", "9000"))
    MINIO_ACCESS_KEY: str = os.getenv("MINIO_ACCESS_KEY", "minioadmin")
    MINIO_SECRET_KEY: str = os.getenv("MINIO_SECRET_KEY", "minioadmin")
    MINIO_PDF_BUCKET: str = "pdf-documents"
    MINIO_PNG_BUCKET: str = "png-documents"
    MINIO_STAMP_BUCKET: str = "stamp-templates"

    TEMPLATES_DIR: str = "/app/templates"
    TEMP_DIR: str = "/app/temp"

    DEFAULT_PAGE_SIZE: int = 10
    MAX_UPLOAD_SIZE: int = 20 * 1024 * 1024

    class Config:
        env_file = ".env"
        case_sensitive = True


settings = Settings()

os.makedirs(settings.TEMPLATES_DIR, exist_ok=True)
os.makedirs(settings.TEMP_DIR, exist_ok=True)