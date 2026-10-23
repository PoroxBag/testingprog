from __future__ import annotations

import os
import urllib3
from locust import HttpUser, between, task

urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

BMC_URL = os.getenv("BMC_URL", "https://127.0.0.1:2443").rstrip("/")
BMC_USER = os.getenv("BMC_USER", "root")
BMC_PASSWORD = os.getenv("BMC_PASSWORD", "0penBmc")


class OpenBMCUser(HttpUser):
    """Нагрузка на OpenBMC Redfish API."""

    host = BMC_URL
    wait_time = between(1, 3)
    # вес: чуть меньше, чем публичное API — BMC на QEMU слабее
    weight = 2

    def on_start(self):
        self.client.verify = False
        self.auth = (BMC_USER, BMC_PASSWORD)

    @task(3)
    def get_system_info(self):
        """GET /redfish/v1/Systems/system — информация о системе."""
        with self.client.get(
            "/redfish/v1/Systems/system",
            auth=self.auth,
            name="OpenBMC: GET Systems/system",
            catch_response=True,
        ) as resp:
            if resp.status_code != 200:
                resp.failure(f"HTTP {resp.status_code}")
                return
            try:
                data = resp.json()
            except ValueError:
                resp.failure("Ответ не JSON")
                return
            if "Id" not in data and "@odata.id" not in data:
                resp.failure("Нет ожидаемых полей системы")
            else:
                resp.success()

    @task(2)
    def get_power_state(self):
        """Запрос PowerState из Systems/system."""
        with self.client.get(
            "/redfish/v1/Systems/system",
            auth=self.auth,
            name="OpenBMC: GET PowerState",
            catch_response=True,
        ) as resp:
            if resp.status_code != 200:
                resp.failure(f"HTTP {resp.status_code}")
                return
            try:
                data = resp.json()
            except ValueError:
                resp.failure("Ответ не JSON")
                return
            power = data.get("PowerState")
            if power is None:
                resp.failure("Поле PowerState отсутствует")
            else:
                # фиксируем значение в логе Locust через success
                resp.success()


class PublicApiUser(HttpUser):
    """Нагрузка на открытые публичные API."""

    # базовый host для JSONPlaceholder; wttr.in вызывается абсолютным URL
    host = "https://jsonplaceholder.typicode.com"
    wait_time = between(1, 2)
    weight = 3

    @task(3)
    def get_posts(self):
        """GET /posts — список постов JSONPlaceholder."""
        with self.client.get(
            "/posts",
            name="Public: JSONPlaceholder /posts",
            catch_response=True,
        ) as resp:
            if resp.status_code != 200:
                resp.failure(f"HTTP {resp.status_code}")
                return
            try:
                data = resp.json()
            except ValueError:
                resp.failure("Ответ не JSON")
                return
            if not isinstance(data, list) or len(data) == 0:
                resp.failure("Ожидали непустой список постов")
            else:
                resp.success()

    @task(2)
    def get_weather_novosibirsk(self):
        """GET wttr.in — погода Новосибирска (JSON)."""
        with self.client.get(
            "https://wttr.in/Novosibirsk?format=j1",
            name="Public: wttr.in Novosibirsk",
            headers={"User-Agent": "locust-lab6/1.0", "Accept": "application/json"},
            catch_response=True,
        ) as resp:
            if resp.status_code != 200:
                resp.failure(f"HTTP {resp.status_code}")
                return
            try:
                data = resp.json()
            except ValueError:
                resp.failure("Ответ не JSON")
                return
            if "current_condition" not in data and "weather" not in data:
                resp.failure("Нет погодных полей в ответе wttr.in")
            else:
                resp.success()
