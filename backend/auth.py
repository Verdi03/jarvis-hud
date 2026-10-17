"""Fail-closed HTTP Basic authentication for the private JARVIS HUD API."""
import hmac
import os

from fastapi import Depends, HTTPException
from fastapi.security import HTTPBasic, HTTPBasicCredentials

_basic = HTTPBasic(auto_error=False)


def require_auth(credentials: HTTPBasicCredentials | None = Depends(_basic)) -> bool:
    expected = os.getenv("JARVIS_ACCESS_PASSWORD", "")
    if not expected:
        raise HTTPException(
            status_code=503,
            detail="Accès privé non configuré : ajoutez JARVIS_ACCESS_PASSWORD dans les secrets Base44.",
        )

    supplied = credentials.password if credentials else ""
    if not credentials or not hmac.compare_digest(supplied.encode("utf-8"), expected.encode("utf-8")):
        raise HTTPException(
            status_code=401,
            detail="Mot de passe JARVIS invalide.",
            headers={"WWW-Authenticate": 'Basic realm="JARVIS HUD"'},
        )
    return True
