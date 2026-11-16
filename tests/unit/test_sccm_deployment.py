"""Media choice and interrupted-route checks; these never contact the lab."""

import unittest

from plugins.module_utils.sccm_deployment import deployment_settings
from plugins.module_utils.sccm_versions import VersionPlanningError, plan_version


class DeploymentSettingsTests(unittest.TestCase):
    def test_2609_uses_2509_media_and_direct_supported_servicing(self):
        plan = plan_version("2609", current_site_versions={"CAS": "2509"})
        settings = deployment_settings(plan)
        self.assertEqual(plan.upgrade_versions, ("2609",))
        self.assertEqual(settings["baseline_version"], "2509")
        self.assertEqual(settings["release_builds"]["2609"], 9152)
        self.assertEqual(settings["prerequisites"]["odbc_version"], "18.6.2.1")

    def test_2609_from_2403_keeps_required_intermediate_hop(self):
        plan = plan_version("2609", current_site_versions={"CAS": "2403"})
        self.assertEqual(plan.upgrade_versions, ("2509", "2609"))

    def test_existing_route_keeps_the_new_install_media_choice_separate(self):
        plan = plan_version("2603", current_site_versions={"CAS": "5.00.9128.1000"})
        settings = deployment_settings(plan)
        self.assertIsNone(plan.baseline_version)
        self.assertEqual(plan.upgrade_versions, ("2509", "2603"))
        self.assertEqual(settings["baseline_version"], "2509")
        self.assertEqual(settings["media_filename"], "ConfigMgr_2509.exe")

    def test_historical_target_does_not_get_newer_baseline_media(self):
        settings = deployment_settings(plan_version("2503"))
        self.assertEqual(settings["baseline_version"], "2403")
        self.assertIn("2403", settings["media_url"])

    def test_interrupted_hierarchy_can_finish_from_the_oldest_site(self):
        plan = plan_version(
            "2603",
            current_site_versions={"CAS": "5.00.9141.1000", "PS1": "5.00.9128.1000"},
            allow_mixed_versions=True,
        )
        self.assertEqual(plan.upgrade_versions, ("2509", "2603"))

    def test_resume_permission_does_not_permit_downgrades(self):
        with self.assertRaisesRegex(VersionPlanningError, "newer release"):
            plan_version(
                "2509",
                current_site_versions={
                    "CAS": "5.00.9146.1000",
                    "SEC": "5.00.9141.1000",
                },
                allow_mixed_versions=True,
            )


if __name__ == "__main__":
    unittest.main()
