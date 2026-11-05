import unittest
from contextlib import redirect_stderr
from io import StringIO

from bot_simulator import (
    DEFAULT_JUICE_SHOP_HOST,
    SCENARIOS,
    build_target,
    parse_args,
)


class BotSimulatorTests(unittest.TestCase):
    def test_only_retained_scenarios_are_available(self):
        self.assertEqual(
            set(SCENARIOS),
            {"brute-force", "credential-stuffing", "account-takeover"},
        )

    def test_scenarios_use_only_predefined_https_routes(self):
        for name, scenario in SCENARIOS.items():
            if scenario.local_juice_shop:
                continue
            with self.subTest(scenario=scenario):
                target = build_target("demo.example.com", scenario)
                self.assertTrue(target.startswith("https://demo.example.com/"))

    def test_login_scenarios_are_local_juice_shop_and_have_synthetic_payloads(self):
        brute_force = SCENARIOS["brute-force"]
        stuffing = SCENARIOS["credential-stuffing"]
        self.assertEqual(
            build_target("localhost", brute_force),
            "http://localhost:3000/rest/user/login",
        )
        self.assertEqual(len(brute_force.payloads), 10)
        self.assertEqual(len({email for email, _ in brute_force.payloads}), 1)
        self.assertEqual(
            [password for _, password in brute_force.payloads],
            [f"WrongPassword{index:02d}!" for index in range(1, 11)],
        )
        self.assertEqual(len(stuffing.payloads), 10)
        self.assertEqual(len({email for email, _ in stuffing.payloads}), 10)
        self.assertEqual(len({password for _, password in stuffing.payloads}), 10)
        self.assertTrue(
            all(email.endswith(".invalid") for email, _ in stuffing.payloads)
        )

    def test_login_scenarios_reject_non_local_hosts(self):
        for name in ("brute-force", "credential-stuffing"):
            with self.subTest(scenario=name), self.assertRaises(ValueError):
                build_target("example.com", SCENARIOS[name])

    def test_placeholder_host_is_rejected(self):
        for scenario in SCENARIOS.values():
            if scenario.local_juice_shop:
                with self.subTest(scenario=scenario), self.assertRaisesRegex(
                    ValueError, "still the XXXXX placeholder"
                ):
                    build_target(DEFAULT_JUICE_SHOP_HOST, scenario)

    def test_rejects_url_instead_of_hostname(self):
        with self.assertRaises(ValueError):
            build_target("https://demo.example.com/path", SCENARIOS["brute-force"])

    def test_other_demo_login_sends_empty_post(self):
        scenario = SCENARIOS["account-takeover"]
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


if __name__ == "__main__":
    unittest.main()
