import importlib
import os
import sys
import types
import unittest
from pathlib import Path
from unittest.mock import patch


sys.path.insert(0, str(Path(__file__).resolve().parent))

google_stub = types.ModuleType("google")
google_stub.__path__ = []
cloud_stub = types.ModuleType("google.cloud")
cloud_stub.__path__ = []
firestore_stub = types.ModuleType("google.cloud.firestore")
firestore_stub.Client = lambda: None
cloud_stub.firestore = firestore_stub
google_stub.cloud = cloud_stub

with patch.dict(
    sys.modules,
    {
        "google": google_stub,
        "google.cloud": cloud_stub,
        "google.cloud.firestore": firestore_stub,
    },
):
    with patch.dict(os.environ, {"EDGE_SECRET": ""}):
        app_module = importlib.import_module("main")


class SyntheticRouteTests(unittest.TestCase):
    def setUp(self):
        app_module.app.config["TESTING"] = True
        self.client = app_module.app.test_client()
        with app_module._demo_counters_lock:
            for name in app_module._demo_counters:
                app_module._demo_counters[name] = 0

    def test_six_scenarios_increment_separate_counters(self):
        cases = [
            ("POST", "/api/demo/login?scenario=brute-force", 401, "brute_force"),
            ("GET", "/api/demo/catalog", 200, "malicious_scraping"),
            ("POST", "/api/demo/contact?scenario=spam-bots", 202, "spam_bots"),
            ("POST", "/api/demo/contact?scenario=form-abuse", 202, "automated_form_abuse"),
            ("POST", "/api/demo/login?scenario=account-takeover", 401, "account_takeover"),
            ("POST", "/api/demo/login?scenario=credential-stuffing", 401, "credential_stuffing"),
        ]
        for method, path, status, _ in cases:
            with self.subTest(path=path):
                response = self.client.open(path, method=method, data=b"not-retained")
                self.assertEqual(response.status_code, status)

        events = self.client.get("/api/demo/stats").get_json()["events"]
        self.assertEqual(set(events), {case[3] for case in cases})
        self.assertTrue(all(value == 1 for value in events.values()))

    def test_unknown_scenarios_are_rejected(self):
        login = self.client.post("/api/demo/login?scenario=unknown")
        contact = self.client.post("/api/demo/contact?scenario=unknown")
        self.assertEqual(login.status_code, 400)
        self.assertEqual(contact.status_code, 400)


if __name__ == "__main__":
    unittest.main()
