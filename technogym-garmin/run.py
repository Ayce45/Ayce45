"""Lance le backend : python run.py (ou uvicorn app.api.main:get_app --factory)."""
import uvicorn

from app.config import get_settings

if __name__ == "__main__":
    s = get_settings()
    uvicorn.run("app.api.main:get_app", factory=True, host=s.backend_host, port=s.backend_port, reload=False)
