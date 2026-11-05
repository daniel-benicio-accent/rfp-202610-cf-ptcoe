import unittest
from contextlib import redirect_stderr
from io import StringIO

from bot_simulator import SCENARIOS, build_target, parse_args


class BotSimulatorTests(unittest.TestCase):
    def test_scenarios_use_only_predefined_https_routes(self):
        for scenario in SCENARIOS.values():
            with self.subTest(scenario=scenario):
                target = build_target("demo.example.com", scenario)
                self.assertTrue(target.startswith("https://demo.example.com/"))

    def test_rejects_url_instead_of_hostname(self):
        with self.assertRaises(ValueError):
            build_target("https://demo.example.com/path", SCENARIOS["brute-force"])

    def test_login_scenarios_send_empty_posts(self):
        for name in ("brute-force", "account-takeover", "credential-stuffing"):
            scenario = SCENARIOS[name]
            self.assertEqual(scenario.method, "POST")
            self.assertEqual(scenario.path, "/api/demo/login")

    def test_request_count_is_capped(self):
        with redirect_stderr(StringIO()), self.assertRaises(SystemExit):
            parse_args(["brute-force", "--count", "11"])

    def test_interval_cannot_be_zero_or_non_finite(self):
        for interval in ("0", "nan", "inf"):
            with self.subTest(interval=interval):
                with redirect_stderr(StringIO()), self.assertRaises(SystemExit):
                    parse_args(["brute-force", "--interval", interval])

    def test_malicious_scraping_uses_juice_shop_reviews_endpoint(self):
        scenario = SCENARIOS["malicious-scraping"]
        self.assertEqual(scenario.method, "GET")
        self.assertEqual(scenario.path, "/rest/products/1/reviews")

    def test_malicious_scraping_allows_twenty_requests_at_five_per_second(self):
        args = parse_args(
            [
                "malicious-scraping",
                "--count",
                "20",
                "--interval",
                "0.2",
            ]
        )
        self.assertEqual(args.count, 20)
        self.assertEqual(args.interval, 0.2)

if __name__ == "__main__":
    unittest.main()
