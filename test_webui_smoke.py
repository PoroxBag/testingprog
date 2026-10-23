"""
WebUI-ориентированные проверки для CI.

На QEMU romulus bmcweb часто не отдаёт статику SPA на `/` (401/404),
поэтому проверяем Redfish API, которыми пользуется OpenBMC WebUI
(сессии, аккаунты, managers). Полный Selenium — опционально при живом SPA.
"""

from __future__ import annotations

import os

import requests
import urllib3

urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

BASE_URL = os.getenv("OPENBMC_WEBUI_URL", "https://127.0.0.1:2443").rstrip("/")
USER = os.getenv("OPENBMC_USERNAME", "root")
PASSWORD = os.getenv("OPENBMC_PASSWORD", "0penBmc")


def _get(path: str, **kwargs):
    return requests.get(
        f"{BASE_URL}{path}",
        auth=(USER, PASSWORD),
        verify=False,
        timeout=30,
        **kwargs,
    )


def test_bmcweb_https_alive():
    """HTTPS-порт bmcweb отвечает (WebUI и Redfish на одном порту)."""
    resp = requests.get(BASE_URL + "/", verify=False, timeout=30)
    # 401/404 без статики UI — норма для этой сборки; 5xx — нет
    assert resp.status_code < 500, resp.status_code
    assert "www-authenticate" in {k.lower() for k in resp.headers} or resp.status_code in (
        200,
        401,
        403,
        404,
    )


def test_webui_backend_account_service():
    """AccountService — страница Users/Security в WebUI."""
    resp = _get("/redfish/v1/AccountService")
    assert resp.status_code == 200, resp.text[:300]
    data = resp.json()
    assert "@odata.id" in data


def test_webui_backend_session_login():
    """SessionService — то же, что login form WebUI."""
    resp = requests.post(
        f"{BASE_URL}/redfish/v1/SessionService/Sessions",
        json={"UserName": USER, "Password": PASSWORD},
        verify=False,
        timeout=30,
    )
    assert resp.status_code in (200, 201), resp.text[:300]
    token = resp.headers.get("X-Auth-Token")
    assert token
    location = resp.headers.get("Location")
    if location:
        url = location if location.startswith("http") else f"{BASE_URL}{location}"
        requests.delete(url, headers={"X-Auth-Token": token}, verify=False, timeout=15)


def test_webui_backend_managers_bmc():
    """Managers/bmc — данные для overview WebUI."""
    resp = _get("/redfish/v1/Managers/bmc")
    assert resp.status_code == 200, resp.text[:300]
    data = resp.json()
    assert data.get("Id") or data.get("@odata.id")
