"""Print an SCCM version plan without connecting to the lab or changing it."""

import argparse
import json
import logging
from typing import Dict, Optional, Sequence

from plugins.module_utils.sccm_versions import VersionPlanningError, plan_version


def make_parser() -> argparse.ArgumentParser:
    """Describe the read-only inputs, output, and internet requirement."""
    parser = argparse.ArgumentParser(
        description=(
            "Print an SCCM release plan as JSON. This command never installs software "
            "or connects to SCCM. 'latest' reads public Microsoft Learn pages; explicit "
            "releases work offline. No credentials are required."
        ),
        epilog=(
            "Run from the repository root. Example: python -m dev.plan_sccm_version "
            "--target-version 2603 --current-site CAS=5.00.9128.1000 "
            "--current-site PS1=5.00.9128.1000 --current-site SEC=5.00.9128.1000"
        ),
    )
    parser.add_argument(
        "--target-version",
        default="latest",
        help="Desired release, such as 2509, or latest (the default).",
    )
    parser.add_argument(
        "--no-hotfixes",
        action="store_true",
        help="Record that additional hotfixes should be skipped; no installed fixes are removed.",
    )
    parser.add_argument(
        "--current-site",
        action="append",
        default=[],
        metavar="SITE=VERSION",
        help="Existing site's release or full site version; repeat for each site. Omit for a fresh-install plan.",
    )
    return parser


def current_sites(arguments: Sequence[str]) -> Dict[str, str]:
    """Reject missing or duplicate site names instead of overwriting input."""
    sites: Dict[str, str] = {}
    for argument in arguments:
        name, separator, version = argument.partition("=")
        normalized_name = name.strip().upper()
        if not separator or not normalized_name or not version.strip():
            raise VersionPlanningError("--current-site must contain SITE=VERSION.")
        if normalized_name in sites:
            raise VersionPlanningError(
                "--current-site names must be unique, ignoring letter case."
            )
        sites[normalized_name] = version.strip()
    return sites


def main(arguments: Optional[Sequence[str]] = None) -> int:
    """Return an error status for an unresolvable plan; print JSON on success."""
    options = make_parser().parse_args(arguments)
    logging.basicConfig(level=logging.INFO, format="%(levelname)s: %(message)s")
    try:
        plan = plan_version(
            target_version=options.target_version,
            install_hotfixes=not options.no_hotfixes,
            current_site_versions=current_sites(options.current_site),
        )
    except VersionPlanningError as error:
        logging.error("Cannot plan the requested SCCM version: %s", error)
        return 1
    print(json.dumps(plan.to_dict(), indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
