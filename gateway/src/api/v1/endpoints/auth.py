from fastapi import APIRouter, HTTPException, Depends, status, Request, Response, Body
from fastapi.security import OAuth2PasswordBearer, OAuth2PasswordRequestForm
from typing import Dict, Any, Optional
import httpx
from core.config import settings
from utils.client import ServiceClient
from pydantic import BaseModel

class UserRegistration(BaseModel):
    username: str
    email: str
    password: str
    full_name: Optional[str] = None

router = APIRouter()

user_service = ServiceClient(settings.USER_SERVICE_URL)

oauth2_scheme = OAuth2PasswordBearer(tokenUrl="/api/v1/auth/login")


async def get_current_user(token: str = Depends(oauth2_scheme)):
    """
    Lấy thông tin người dùng hiện tại từ token.

    Args:
        token: JWT token

    Returns:
        Thông tin người dùng
    
    Raises:
        HTTPException: Nếu token không hợp lệ hoặc người dùng không tồn tại
    """
    try:
        response = await user_service.post("/api/v1/auth/validate-token", {"token": token})
        return response
    except HTTPException as e:
        if e.status_code == 401:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Token không hợp lệ hoặc đã hết hạn",
                headers={"WWW-Authenticate": "Bearer"}
            )
        raise e


@router.post("/register", summary="Đăng ký người dùng mới")
async def register(user: UserRegistration):
    """
    Đăng ký người dùng mới.
    """
    try:
        response = await user_service.post("/api/v1/auth/register", user.model_dump())
        return response
    except HTTPException as e:
        raise e


@router.post("/login", summary="Đăng nhập và nhận token JWT")
async def login(form_data: OAuth2PasswordRequestForm = Depends()):
    """
    Đăng nhập và nhận token JWT.
    """
    try:
        async with httpx.AsyncClient(timeout=60) as client:
            response = await client.post(
                f"{settings.USER_SERVICE_URL}/api/v1/auth/login",
                data={"username": form_data.username, "password": form_data.password},
                headers={"Content-Type": "application/x-www-form-urlencoded"}
            )
            
            if response.status_code >= 400:
                error_detail = response.json().get('detail', 'Lỗi không xác định') if response.headers.get(
                    'content-type') == 'application/json' else response.text
                raise HTTPException(status_code=response.status_code, detail=error_detail)
            
            return response.json()
    except httpx.RequestError as exc:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail=f"Lỗi kết nối đến service: {str(exc)}"
        )
    except HTTPException as e:
        if e.status_code == 401:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Tên đăng nhập hoặc mật khẩu không đúng",
                headers={"WWW-Authenticate": "Bearer"}
            )
        raise e

@router.post("/refresh-token", summary="Làm mới token JWT")
async def refresh_token(refresh_token: str = Body(..., embed=True)):
    """
    Làm mới token JWT bằng refresh token.
    """
    try:
        response = await user_service.post("/api/v1/auth/refresh-token", {"refresh_token": refresh_token})
        return response
    except HTTPException as e:
        if e.status_code == 401:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Refresh token không hợp lệ hoặc đã hết hạn",
                headers={"WWW-Authenticate": "Bearer"}
            )
        raise e


@router.post("/logout", summary="Đăng xuất")
async def logout(refresh_token: Optional[str] = Body(None, embed=True)):
    """
    Đăng xuất người dùng.
    """
    try:
        if not refresh_token:
            return {"detail": "Successfully logged out"}
            
        response = await user_service.post("/api/v1/auth/logout", {"refresh_token": refresh_token})
        return response
    except Exception as e:
        # Trong trường hợp lỗi, vẫn trả về thành công để client xóa token
        return {"detail": "Successfully logged out"}


@router.get("/me", summary="Lấy thông tin người dùng hiện tại")
async def get_me(current_user: Dict[str, Any] = Depends(get_current_user)):
    """
    Lấy thông tin người dùng hiện tại.
    """
    return current_user

@router.get("/stats", summary="Lấy thống kê tài liệu")
async def get_stats():
    """
    Lấy thống kê số lượng các loại tài liệu trong hệ thống.
    """
    try:
        response = await user_service.get("/api/v1/stats")
        return response
    except Exception as e:
        return {
            "totalDocuments": 0,
            "pdfCount": 0,
            "wordCount": 0,
            "excelCount": 0
        }

@router.get("/recent-documents", summary="Lấy tài liệu gần đây")
async def get_recent_documents(
    limit: int = 5,
):
    """
    Lấy danh sách tài liệu gần đây.
    """
    try:
        response = await user_service.get("/api/v1/recent-documents", params={"limit": limit})
        return response
    except Exception as e:
        return []