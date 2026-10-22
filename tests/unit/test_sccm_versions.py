"""Offline behavior checks using small invented Microsoft-shaped documents."""

import io
import unittest
from contextlib import redirect_stdout
from unittest.mock import Mock, patch

from dev.plan_sccm_version import current_sites, main
from plugins.module_utils.sccm_versions import (
    LEARN_ROOT,
    MAX_DOCUMENT_BYTES,
    RELEASES,
    UPDATES_URL,
    Release,
    VersionPlanningError,
    is_globally_available,
    plan_version,
    published_releases,
    read_microsoft_markdown,
    release_for_installed_version,
    upgrade_path,
)


def version_table(rows):
    """Build only the public table structure, without copying a whole article."""
    entries = [
        "#### Supported versions",
        "| Version | Availability date | Support end date | Baseline | In-console update |",
        "| --- | --- | --- | --- | --- |",
    ]
    for version, build in rows:
        entries.append(
            "| [**{0}**](release-{0}) (5.00.{1}.1000) | date | date | No | Yes |".format(
                version, build
            )
        )
    entries.extend(
        [
            "#### Historical versions",
            "| **9999** (5.00.9999) | date | date | Yes | Yes |",
        ]
    )
    return "\n".join(entries)


def checklist(version, is_global):
    """Use the minimum release-channel wording recognized by the reader."""
    statement = (
        "globally available for all customers"
        if is_global
        else "released for the early update ring"
    )
    return (
        "### Early update ring\nVersion {0} is {1}.\n## Pre-update checklist\n".format(
            version, statement
        )
    )


def checklist_url(version):
    return (
        LEARN_ROOT
        + "/checklist-for-installing-update-"
        + version
        + "?accept=text/markdown"
    )


class VersionPlanTests(unittest.TestCase):
    def test_fresh_releases_choose_a_usable_baseline(self):
        cases = (
            ("2403", "2403", ()),
            ("2409", "2403", ("2409",)),
            ("2503", "2403", ("2503",)),
            ("2509", "2509", ()),
            ("2603", "2509", ("2603",)),
        )
        for target, baseline, updates in cases:
            with self.subTest(target=target):
                result = plan_version(target)
                self.assertEqual(result.baseline_version, baseline)
                self.assertEqual(result.upgrade_versions, updates)

    def test_existing_2403_hierarchy_uses_newest_intermediate_release(self):
        result = plan_version(
            "2603",
            current_site_versions={
                "CAS": "5.00.9128.1000",
                "PS1": "5.00.9128.1030",
                "SEC": "2403",
            },
        )
        self.assertIsNone(result.baseline_version)
        self.assertEqual(result.upgrade_versions, ("2509", "2603"))

    def test_same_release_needs_no_release_update(self):
        result = plan_version("2509", current_site_versions={"PS1": "5.00.9141.9999"})
        self.assertEqual(result.upgrade_versions, ())
        self.assertTrue(result.install_hotfixes)

    def test_direct_upgrade_is_preferred_when_allowed(self):
        result = plan_version("2603", current_site_versions={"PS1": "2409"})
        self.assertEqual(result.upgrade_versions, ("2603",))

    def test_every_known_forward_route_obeys_the_upgrade_floor(self):
        by_version = {release.version: release for release in RELEASES}
        for source in RELEASES:
            for target in RELEASES:
                if source.site_build > target.site_build:
                    continue  # Downgrades have their own rejection test.
                previous = source
                for step in upgrade_path(source, target):
                    destination = by_version[step]
                    self.assertGreater(destination.site_build, previous.site_build)
                    self.assertGreaterEqual(
                        int(previous.version), int(destination.minimum_source_version)
                    )
                    previous = destination
                self.assertEqual(previous, target)

    def test_no_hotfixes_is_recorded_without_inventing_a_patch_version(self):
        result = plan_version("2509", install_hotfixes=False)
        self.assertFalse(result.to_dict()["install_hotfixes"])
        self.assertEqual(result.target_site_build, 9141)

    def test_explicit_target_never_uses_the_network(self):
        reader = Mock(side_effect=AssertionError("Explicit targets must work offline"))
        result = plan_version("2509", read_document=reader)
        self.assertEqual(result.discovery_sources, ())
        reader.assert_not_called()

    def test_downloading_older_media_is_not_a_downgrade_path(self):
        with self.assertRaisesRegex(VersionPlanningError, "Downgrading"):
            plan_version("2403", current_site_versions={"PS1": "2603"})

    def test_mixed_releases_require_existing_update_investigation(self):
        with self.assertRaisesRegex(VersionPlanningError, "mixed SCCM releases"):
            plan_version("2603", current_site_versions={"CAS": "2509", "PS1": "2403"})

    def test_unknown_installed_build_is_not_guessed(self):
        with self.assertRaisesRegex(VersionPlanningError, "unknown build"):
            plan_version("2603", current_site_versions={"PS1": "5.00.9999.1000"})

    def test_unknown_and_malformed_targets_are_rejected(self):
        for target in (
            "2609",
            "2703",
            "latest-preview",
            " 2509",
            "5.00.9141.1000",
            True,
            2509,
        ):
            with self.subTest(target=target), self.assertRaises(VersionPlanningError):
                plan_version(target)

    def test_boolean_switch_cannot_be_a_truthy_string(self):
        with self.assertRaisesRegex(VersionPlanningError, "YAML boolean"):
            plan_version("2509", install_hotfixes="false")

    def test_invalid_current_site_input_is_rejected(self):
        for sites in (["2403"], {"": "2403"}, {"PS1": 2403}, {"PS1": "unknown"}):
            with self.subTest(sites=sites), self.assertRaises(VersionPlanningError):
                plan_version("2509", current_site_versions=sites)

    def test_a_missing_intermediate_route_is_an_error(self):
        source = Release("2403", 9128, None, True)
        target = Release("2603", 9146, "2509")
        with self.assertRaisesRegex(
            VersionPlanningError, "No understood upgrade route"
        ):
            upgrade_path(source, target, (source, target))

    def test_full_site_versions_accept_hotfix_revision_and_zero_padding(self):
        self.assertEqual(release_for_installed_version("5.0.9128.1030").version, "2403")
        self.assertEqual(
            release_for_installed_version("5.00.9128.1000").version, "2403"
        )


class ReleaseDiscoveryTests(unittest.TestCase):
    def setUp(self):
        self.documents = {
            UPDATES_URL: version_table(
                (("2603", 9146), ("2609", 9152), ("2509", 9141))
            ),
            checklist_url("2609"): checklist("2609", False),
            checklist_url("2603"): checklist("2603", True),
        }

    def test_latest_excludes_early_release_and_records_its_sources(self):
        result = plan_version(read_document=self.documents.__getitem__)
        self.assertEqual(result.target_version, "2603")
        self.assertEqual(result.baseline_version, "2509")
        self.assertEqual(
            result.discovery_sources,
            (UPDATES_URL, checklist_url("2609"), checklist_url("2603")),
        )

    def test_historical_table_cannot_supply_latest(self):
        releases = published_releases(self.documents[UPDATES_URL])
        self.assertEqual(
            [release.version for release in releases], ["2609", "2603", "2509"]
        )

    def test_new_unknown_broad_release_stops_instead_of_using_an_older_one(self):
        self.documents[UPDATES_URL] = version_table((("2703", 9160), ("2603", 9146)))
        self.documents[checklist_url("2703")] = checklist("2703", True)
        with self.assertRaisesRegex(
            VersionPlanningError, "2703.*not in the understood"
        ):
            plan_version(read_document=self.documents.__getitem__)

    def test_published_build_disagreement_is_an_error(self):
        self.documents[UPDATES_URL] = version_table((("2603", 9999),))
        with self.assertRaisesRegex(VersionPlanningError, "build disagrees"):
            plan_version(read_document=self.documents.__getitem__)

    def test_release_date_does_not_prove_broad_availability(self):
        self.documents[checklist_url("2609")] = (
            "### Early update ring\nReleased yesterday.\n"
        )
        with self.assertRaisesRegex(
            VersionPlanningError, "unambiguous release channel"
        ):
            plan_version(read_document=self.documents.__getitem__)

    def test_failure_to_read_newer_release_does_not_select_an_older_one(self):
        reader = Mock(side_effect=VersionPlanningError("Cannot read release evidence"))
        with self.assertRaisesRegex(VersionPlanningError, "Cannot read"):
            plan_version(read_document=reader)

    def test_all_early_releases_produce_an_error(self):
        self.documents[UPDATES_URL] = version_table((("2609", 9152),))
        with self.assertRaisesRegex(
            VersionPlanningError, "No broadly available release"
        ):
            plan_version(read_document=self.documents.__getitem__)

    def test_wrong_release_statement_is_rejected(self):
        with self.assertRaisesRegex(VersionPlanningError, "unambiguous"):
            is_globally_available(checklist("2509", True), "2603")

    def test_contradictory_channel_statements_are_rejected(self):
        text = checklist("2603", True).replace(
            "## Pre-update checklist",
            "Version 2603 is released for the early update ring.",
        )
        with self.assertRaisesRegex(VersionPlanningError, "unambiguous"):
            is_globally_available(text, "2603")

    def test_unrelated_global_statement_outside_channel_section_is_ignored(self):
        text = checklist("2609", False) + "Version 2609 is globally available.\n"
        self.assertFalse(is_globally_available(text, "2609"))

    def test_empty_missing_duplicate_and_malformed_tables_are_errors(self):
        invalid_documents = (
            "",
            "#### Supported versions\nNo table.\n",
            version_table((("2603", 9146), ("2603", 9146))),
            version_table((("2603", 9146),)).replace("| No | Yes |", "| Maybe | Yes |"),
            version_table((("2603", 9146),)).replace("5.00.9146.1000", "unknown build"),
            version_table((("2603", 9146),)) + "\n#### Supported versions\n",
        )
        for document in invalid_documents:
            with self.subTest(document=document):
                with self.assertRaises(VersionPlanningError):
                    published_releases(document)

    def test_duplicate_channel_headings_are_an_error(self):
        with self.assertRaisesRegex(VersionPlanningError, "exactly one"):
            is_globally_available(checklist("2603", True) * 2, "2603")

    def test_microsoft_line_endings_and_bold_channel_text_are_supported(self):
        document = (
            checklist("2603", True).replace("2603", "**2603**").replace("\n", "\r\r\n")
        )
        self.assertTrue(is_globally_available(document, "2603"))


class DocumentTransportTests(unittest.TestCase):
    def response(
        self, content=b"example", content_type="text/markdown", final_url=UPDATES_URL
    ):
        response = Mock()
        response.__enter__ = Mock(return_value=response)
        response.__exit__ = Mock(return_value=False)
        response.geturl.return_value = final_url
        response.headers.get_content_type.return_value = content_type
        response.read.return_value = content
        return response

    def test_only_https_microsoft_learn_sources_are_read(self):
        for url in (
            "http://learn.microsoft.com/page",
            "https://example.com/page",
            "https://learn.microsoft.com.evil.test/page",
        ):
            with self.subTest(url=url):
                with self.assertRaisesRegex(
                    VersionPlanningError, "HTTPS Microsoft Learn"
                ):
                    read_microsoft_markdown(url)

    @patch("plugins.module_utils.sccm_versions.urlopen")
    def test_read_is_bounded_and_has_a_timeout(self, open_url):
        response = self.response()
        open_url.return_value = response
        self.assertEqual(read_microsoft_markdown(UPDATES_URL), "example")
        response.read.assert_called_once_with(MAX_DOCUMENT_BYTES + 1)
        self.assertEqual(open_url.call_args.kwargs["timeout"], 20)

    @patch("plugins.module_utils.sccm_versions.urlopen")
    def test_transport_failures_become_explanatory_errors(self, open_url):
        open_url.side_effect = OSError("network unavailable")
        with self.assertRaisesRegex(
            VersionPlanningError, "Cannot read release evidence"
        ):
            read_microsoft_markdown(UPDATES_URL)

    @patch("plugins.module_utils.sccm_versions.urlopen")
    def test_html_large_invalid_utf8_and_offsite_redirects_are_rejected(self, open_url):
        responses = (
            self.response(content_type="text/html"),
            self.response(content=b"x" * (MAX_DOCUMENT_BYTES + 1)),
            self.response(content=b"\xff"),
            self.response(final_url="https://example.com/login"),
        )
        for response in responses:
            open_url.return_value = response
            with self.subTest(response=response):
                with self.assertRaises(VersionPlanningError):
                    read_microsoft_markdown(UPDATES_URL)


class CommandLineTests(unittest.TestCase):
    def test_current_site_names_are_case_insensitive_and_unique(self):
        self.assertEqual(current_sites(["ps1=2403"]), {"PS1": "2403"})
        for arguments in (["PS1=2403", "ps1=2403"], ["PS1"], ["=2403"], ["PS1="]):
            with self.subTest(arguments=arguments):
                with self.assertRaises(VersionPlanningError):
                    current_sites(arguments)

    def test_explicit_command_prints_a_plan(self):
        output = io.StringIO()
        with redirect_stdout(output):
            status = main(
                [
                    "--target-version",
                    "2603",
                    "--current-site",
                    "PS1=2403",
                    "--no-hotfixes",
                ]
            )
        self.assertEqual(status, 0)
        self.assertIn('"install_hotfixes": false', output.getvalue())
        self.assertIn('"2603"', output.getvalue())

    def test_invalid_command_returns_failure_without_success_json(self):
        output = io.StringIO()
        with redirect_stdout(output), self.assertLogs(level="ERROR"):
            status = main(["--target-version", "2703"])
        self.assertEqual(status, 1)
        self.assertEqual(output.getvalue(), "")

    def test_help_does_not_read_documents(self):
        with patch("plugins.module_utils.sccm_versions.urlopen") as open_url:
            with redirect_stdout(io.StringIO()):
                with self.assertRaises(SystemExit) as result:
                    main(["--help"])
        self.assertEqual(result.exception.code, 0)
        open_url.assert_not_called()


if __name__ == "__main__":
    unittest.main()
