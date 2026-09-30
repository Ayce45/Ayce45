"""Lance le backend et, avec --open, ouvre la page de synchronisation dans le navigateur.

    python run.py           # API + page web sur http://127.0.0.1:8000
    python run.py --open    # idem et ouvre le navigateur
"""
import sys
import threading
import webbrowser

import uvicorn

from app.config import get_settings

if __name__ == "__main__":
    s = get_settings()
    if "--open" in sys.argv:
        host = "127.0.0.1" if s.backend_host in ("0.0.0.0", "::") else s.backend_host
        threading.Timer(1.5, lambda: webbrowser.open(f"http://{host}:{s.backend_port}/")).start()
    uvicorn.run("app.api.main:get_app", factory=True, host=s.backend_host, port=s.backend_port, reload=False)
