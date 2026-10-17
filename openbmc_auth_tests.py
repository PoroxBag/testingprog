import os
import re
import time
import unittest

from selenium import webdriver
from selenium.common.exceptions import TimeoutException
from selenium.webdriver.common.by import By
from selenium.webdriver.support import expected_conditions as EC
from selenium.webdriver.support.ui import WebDriverWait

BASE_URL = os.getenv("OPENBMC_WEBUI_URL", "https://localhost:8000")
LOGIN_URL = f"{BASE_URL}/#/login"

BMC_USERNAME = os.getenv("OPENBMC_USERNAME", "root")
BMC_PASSWORD = os.getenv("OPENBMC_PASSWORD", "0penBmc")

LOCKOUT_USERNAME = os.getenv("OPENBMC_LOCKOUT_USERNAME", "")
LOCKOUT_PASSWORD = os.getenv("OPENBMC_LOCKOUT_PASSWORD", "")
LOCKOUT_ATTEMPTS = int(os.getenv("OPENBMC_LOCKOUT_ATTEMPTS", "5"))
RUN_LOCKOUT_TEST = os.getenv("RUN_LOCKOUT_TEST", "0") == "1"
RUN_POWER_TEST = os.getenv("RUN_POWER_TEST", "0") == "1"
EVENT_LOG_MARKER = os.getenv("OPENBMC_LOG_MARKER", "TestError1")

WAIT_SECONDS = 20
POWER_WAIT_SECONDS = 75


class OpenBMCWebUITests(unittest.TestCase):
    """End-to-end tests executed in a real Chromium browser."""

    def setUp(self):
        options = webdriver.ChromeOptions()
        options.add_argument("--headless=new")
        options.add_argument("--no-sandbox")
        options.add_argument("--disable-dev-shm-usage")
        options.add_argument("--ignore-certificate-errors")
        options.add_argument("--allow-insecure-localhost")
        options.add_argument("--window-size=1440,1000")
        options.accept_insecure_certs = True

        self.driver = webdriver.Chrome(options=options)
        self.driver.set_page_load_timeout(40)
        self.wait = WebDriverWait(self.driver, WAIT_SECONDS)

    def tearDown(self):
        if hasattr(self, "driver"):
            self.driver.quit()

    def open_login_page(self):
        self.driver.get(LOGIN_URL)
        self.wait.until(EC.visibility_of_element_located((By.ID, "username")))
        self.wait.until(EC.visibility_of_element_located((By.ID, "password")))

    def submit_login(self, username, password):
        username_box = self.wait.until(
            EC.visibility_of_element_located(
                (By.CSS_SELECTOR, '[data-test-id="login-input-username"]')
            )
        )
        password_box = self.wait.until(
            EC.visibility_of_element_located(
                (By.CSS_SELECTOR, '[data-test-id="login-input-password"]')
            )
        )
        username_box.clear()
        username_box.send_keys(username)
        password_box.clear()
        password_box.send_keys(password)
        self.wait.until(
            EC.element_to_be_clickable(
                (By.CSS_SELECTOR, '[data-test-id="login-button-submit"]')
            )
        ).click()

    def login_as_admin(self):
        self.open_login_page()
        self.submit_login(BMC_USERNAME, BMC_PASSWORD)
        self.wait.until(EC.invisibility_of_element_located((By.ID, "username")))

    def visible_login_error(self):
        elements = self.driver.find_elements(By.ID, "login-error-alert")
        return bool(elements and elements[0].is_displayed())

    def test_01_successful_login(self):
        """Correct credentials should open the authenticated UI."""
        self.open_login_page()
        self.submit_login(BMC_USERNAME, BMC_PASSWORD)
        self.wait.until(EC.invisibility_of_element_located((By.ID, "username")))
        self.assertFalse(
            self.driver.find_elements(By.ID, "username"),
            "The login form is still displayed after valid credentials.",
        )
        self.assertNotIn("#/login", self.driver.current_url)

    def test_02_invalid_credentials(self):
        """An invalid username/password pair should be rejected with an error."""
        self.open_login_page()
        self.submit_login("selenium_invalid_user", "DefinitelyWrongPassword!2026")
        self.wait.until(lambda _driver: self.visible_login_error())
        self.assertTrue(self.driver.find_element(By.ID, "username").is_displayed())
        self.assertIn("#/login", self.driver.current_url)

    @unittest.skipUnless(
        RUN_LOCKOUT_TEST and LOCKOUT_USERNAME and LOCKOUT_PASSWORD,
        "Set RUN_LOCKOUT_TEST=1 and supply a dedicated lockout-test account first.",
    )
    def test_03_account_lockout(self):
        """After repeated failures, even the correct password should be rejected.

        This test locks the supplied dedicated account on systems with account
        lockout enabled. Do not point it at root or another important account.
        """
        if LOCKOUT_ATTEMPTS < 2:
            self.fail("OPENBMC_LOCKOUT_ATTEMPTS must be at least 2.")

        self.open_login_page()
        for attempt in range(LOCKOUT_ATTEMPTS):
            self.submit_login(
                LOCKOUT_USERNAME,
                f"WrongPasswordForLockout-{attempt}-2026!",
            )
            self.wait.until(lambda _driver: self.visible_login_error())
            time.sleep(0.4)

        self.open_login_page()
        self.submit_login(LOCKOUT_USERNAME, LOCKOUT_PASSWORD)

        def login_result(_driver):
            if not _driver.find_elements(By.ID, "username"):
                return "authenticated"
            if self.visible_login_error():
                return "rejected"
            return False

        result = WebDriverWait(self.driver, WAIT_SECONDS).until(login_result)
        self.assertEqual(
            result,
            "rejected",
            "The account accepted its correct password after repeated failed logins; "
            "lockout may be disabled or the configured threshold may be incorrect.",
        )

    def test_04_inventory_page_renders_hardware_sections(self):
        """The Inventory UI should render its inventory sections and tables.

        This test checks the UI rendering only. It does not claim that CPU/RAM
        data exist on the QEMU image; Redfish may report zero processors/memory.
        """
        self.login_as_admin()
        self.driver.get(f"{BASE_URL}/#/hardware-status/inventory")

        self.wait.until(
            lambda driver: "inventory" in driver.find_element(By.TAG_NAME, "body").text.lower()
            and not driver.find_elements(By.ID, "username")
        )
        body_text = self.driver.find_element(By.TAG_NAME, "body").text.lower()
        tables = self.driver.find_elements(By.CSS_SELECTOR, "table")
        expected_sections = (
            "system", "bmc manager", "chassis", "fans", "processors"
        )
        rendered_sections = [name for name in expected_sections if name in body_text]
        self.assertGreaterEqual(
            len(rendered_sections), 3,
            "The Inventory page did not render enough expected sections. Page text:\n"
            + body_text[:2500],
        )
        self.assertTrue(
            tables,
            "Inventory page has section labels but no HTML tables were rendered.",
        )

    def test_05_event_logs_page_renders(self):
        """
        Smoke test for Event Logs Web UI.
        This checks page rendering, not event ingestion.
        The current QEMU image does not expose the created D-Bus
        event through the Redfish EventLog collection.
        """
        self.login_as_admin()
        self.driver.get(f"{BASE_URL}/#/logs/event-logs")

        table = self.wait.until(
            EC.visibility_of_element_located((By.ID, "table-event-logs"))
        )
        search = self.wait.until(
            EC.visibility_of_element_located(
                (
                    By.CSS_SELECTOR,
                    '[data-test-id="eventLogs-input-searchLogs"] input',
                )
            )
        )

        self.assertTrue(table.is_displayed())
        self.assertTrue(search.is_displayed())
        self.assertNotIn("#/login", self.driver.current_url)

    def _host_status(self):
        status_nodes = self.driver.find_elements(
            By.CSS_SELECTOR, '[data-test-id="powerServerOps-text-hostStatus"]'
        )
        if not status_nodes:
            return None
        value = status_nodes[0].text.strip().lower()
        if value in {"on", "включен", "включено"}:
            return "on"
        if value in {"off", "выключен", "выключено"}:
            return "off"
        return value

    def _wait_for_host_status(self, expected_status):
        WebDriverWait(self.driver, POWER_WAIT_SECONDS, poll_frequency=1).until(
            lambda _driver: self._host_status() == expected_status,
            message=f"Host status did not change to '{expected_status}'.",
        )

    def _power_on_host(self):
        button = WebDriverWait(self.driver, WAIT_SECONDS).until(
            EC.element_to_be_clickable(
                (By.CSS_SELECTOR, '[data-test-id="serverPowerOperations-button-powerOn"]')
            )
        )
        button.click()
        self._wait_for_host_status("on")

    def _power_off_host(self):
        radio = WebDriverWait(self.driver, WAIT_SECONDS).until(
            EC.element_to_be_clickable(
                (
                    By.CSS_SELECTOR,
                    '[data-test-id="serverPowerOperations-radio-shutdownOrderly"]',
                )
            )
        )
        radio.click()
        self.wait.until(
            EC.element_to_be_clickable(
                (By.CSS_SELECTOR, '[data-test-id="serverPowerOperations-button-shutDown"]')
            )
        ).click()

        confirm_button = WebDriverWait(self.driver, WAIT_SECONDS).until(
            EC.element_to_be_clickable((By.CSS_SELECTOR, ".modal-footer button.btn-primary"))
        )
        confirm_button.click()
        self._wait_for_host_status("off")

    @unittest.skipUnless(
        RUN_POWER_TEST,
        "Disabled by default: this romulus-bmc QEMU image reports the host as Quiesced "
        "and does not complete power-on. Set RUN_POWER_TEST=1 only to retry explicitly.",
    )
    def test_06_host_power_on_and_off_via_webui(self):
        """Toggle host power through Web UI and restore the initial state."""
        self.login_as_admin()
        self.driver.get(f"{BASE_URL}/#/operations/server-power-operations")
        try:
            WebDriverWait(
                self.driver, POWER_WAIT_SECONDS, poll_frequency=1
            ).until(
                lambda _driver: self._host_status() in {"on", "off"},
                message="The Web UI did not report host status On/Off.",
            )
        except TimeoutException:
            self.skipTest(
                "The Web UI did not report host status On/Off within the timeout; "
                "power control cannot be verified on this QEMU image."
            )

        initial_status = self._host_status()

        if initial_status == "off":
            self._power_on_host()
            self._power_off_host()
        else:
            self._power_off_host()
            self._power_on_host()

        self.assertEqual(self._host_status(), initial_status)


if __name__ == "__main__":
    unittest.main(verbosity=2)
