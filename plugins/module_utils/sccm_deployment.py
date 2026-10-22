"""Installation media and prerequisite choices for understood SCCM releases."""

from typing import Dict

from .sccm_versions import RELEASES, VersionPlan, VersionPlanningError, plan_version

# Resolved from Microsoft's evaluation/download links on 2026-10-22. Fixed
# URLs avoid a moving 'latest' link silently putting another release in a cache.
BASELINE_MEDIA = {
    "2403": "https://download.microsoft.com/download/2/e/5/2e5738c0-1489-4420-ab4b-e5313b9fcec4/MCM_Configmgr_2403.exe",
    "2509": "https://download.microsoft.com/download/50e53030-0fcb-4076-8808-676c79a0ed9f/ConfigMgr_2509.exe",
}
PREREQUISITES = {
    "odbc_version": "18.6.2.1",
    "odbc_url": "https://download.microsoft.com/download/7bf9fad4-0f21-486d-a750-fc990ded5624/amd64/1033/msodbcsql.msi",
    "adk_version": "10.1.26100.9457",
    "adk_url": "https://download.microsoft.com/download/8e0c0f5a-abb5-4358-a51b-168eb40b1590/adk/adksetup.exe",
    # The supported 26100 ADKs share the 26100.1 PE binaries. Validate the
    # installed add-on's package version separately from those binary versions.
    "winpe_version_prefix": "10.1.26100.",
    "winpe_url": "https://download.microsoft.com/download/a4a79e7a-f085-41c4-aebf-2538fd000790/adkwinpeaddons/adkwinpesetup.exe",
    "vc_url": "https://aka.ms/vs/17/release/vc_redist.x64.exe",
}


def deployment_settings(plan: VersionPlan) -> Dict[str, object]:
    """Describe fresh media without changing the existing-site upgrade route.

    Existing sites do not use media for servicing. Keeping a baseline choice in
    this result lets preparation roles share one layout; the installer must
    still refuse to run fresh setup over an installed site.
    """
    fresh_plan = plan_version(plan.target_version, plan.install_hotfixes)
    baseline = fresh_plan.baseline_version
    if baseline is None or baseline not in BASELINE_MEDIA:
        raise VersionPlanningError(
            "No verified baseline download is known for this installation plan."
        )
    return {
        "baseline_version": baseline,
        "media_url": BASELINE_MEDIA[baseline],
        "media_filename": "ConfigMgr_{0}.exe".format(baseline),
        "prerequisites": dict(PREREQUISITES),
        "release_builds": {release.version: release.site_build for release in RELEASES},
    }
