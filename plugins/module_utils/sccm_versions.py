"""Plan SCCM releases without connecting to or changing an SCCM installation.

The catalog records the release paths we understand. Microsoft Learn determines
which release is broadly available today; the catalog must never decide that by
itself. No installer, SCCM command, or credential belongs in this module.
"""

from __future__ import annotations

import logging
import re
from collections import deque
from dataclasses import dataclass
from typing import Callable, Deque, Dict, Mapping, Optional, Sequence, Tuple
from urllib.error import URLError
from urllib.parse import urlsplit
from urllib.request import Request, urlopen

LOGGER = logging.getLogger(__name__)
LEARN_ROOT = "https://learn.microsoft.com/en-us/intune/configmgr/core/servers/manage"
UPDATES_URL = LEARN_ROOT + "/updates?accept=text/markdown"
MAX_DOCUMENT_BYTES = 1024 * 1024


class VersionPlanningError(ValueError):
    """The requested release cannot be planned safely from available evidence."""


@dataclass(frozen=True)
class Release:
    """A known SCCM release, its site build, and its allowed upgrade floor."""

    version: str
    site_build: int
    minimum_source_version: Optional[str]
    has_baseline: bool = False


# These are release requirements, not a hardcoded choice for "latest".
# Sources and the maintenance procedure are documented in docs/version-selection.md.
# 2609 is deliberately not an understood target yet: its prerequisites and early
# release handling must be implemented before deployments can select it.
RELEASES = (
    Release("2403", 9128, None, has_baseline=True),
    Release("2409", 9132, "2303"),
    Release("2503", 9135, "2309"),
    Release("2509", 9141, "2403", has_baseline=True),
    Release("2603", 9146, "2409"),
)


@dataclass(frozen=True)
class PublishedRelease:
    """Release information read from Microsoft's current supported-version table."""

    version: str
    site_build: int


@dataclass(frozen=True)
class VersionPlan:
    """A read-only route; it does not claim that any installation has completed."""

    requested_version: str
    target_version: str
    target_site_build: int
    starting_version: str
    baseline_version: Optional[str]
    upgrade_versions: Tuple[str, ...]
    install_hotfixes: bool
    discovery_sources: Tuple[str, ...]

    def to_dict(self) -> Dict[str, object]:
        """Return JSON-compatible values for Ansible and the command-line tool."""
        return {
            "requested_version": self.requested_version,
            "target_version": self.target_version,
            "target_site_build": self.target_site_build,
            "starting_version": self.starting_version,
            "baseline_version": self.baseline_version,
            "upgrade_versions": list(self.upgrade_versions),
            "install_hotfixes": self.install_hotfixes,
            "discovery_sources": list(self.discovery_sources),
        }


def read_microsoft_markdown(url: str) -> str:
    """Read a bounded, TLS-verified Markdown response from Microsoft Learn.

    Learn's public Markdown endpoint is used because its linked GitHub source
    files can be unavailable. HTML, login pages, and changed response formats
    are errors rather than evidence that an older release should be selected.
    """
    parsed_url = urlsplit(url)
    if parsed_url.scheme != "https" or parsed_url.netloc != "learn.microsoft.com":
        raise VersionPlanningError(
            "Release discovery only reads HTTPS Microsoft Learn URLs."
        )
    # A fixed public document is read; no credentials or lab data are sent.
    request = Request(url, headers={"Accept": "text/markdown"})
    LOGGER.info("Reading release evidence from %s", url)
    try:
        with urlopen(request, timeout=20) as response:
            final_url = urlsplit(response.geturl())
            if final_url.scheme != "https" or final_url.netloc != "learn.microsoft.com":
                raise VersionPlanningError(
                    "Microsoft Learn redirected release discovery to another host."
                )
            if response.headers.get_content_type() != "text/markdown":
                raise VersionPlanningError(
                    "Microsoft Learn did not return the expected Markdown document."
                )
            content = response.read(MAX_DOCUMENT_BYTES + 1)
    except (OSError, URLError) as error:
        raise VersionPlanningError(
            "Cannot read release evidence from {0}: {1}".format(url, error)
        ) from error
    if len(content) > MAX_DOCUMENT_BYTES:
        raise VersionPlanningError(
            "The release document exceeds the expected size limit."
        )
    try:
        return content.decode("utf-8")
    except UnicodeDecodeError as error:
        raise VersionPlanningError(
            "Microsoft Learn returned a document that is not UTF-8 text."
        ) from error


def markdown_section(document: str, title: str, level: int) -> str:
    """Extract one required section, excluding following sections at its level."""
    heading = re.compile(
        r"^" + "#" * level + r"\s+" + re.escape(title) + r"\s*$", re.MULTILINE
    )
    matches = list(heading.finditer(document))
    if len(matches) != 1:
        raise VersionPlanningError(
            "Expected exactly one '{0}' section in Microsoft's document.".format(title)
        )
    remaining = document[matches[0].end() :]
    next_heading = re.search(r"^#{1," + str(level) + r"}\s+", remaining, re.MULTILINE)
    # Subheadings belong to this section; the next peer or parent does not.
    end = next_heading.start() if next_heading else len(remaining)
    return remaining[:end]


def published_releases(document: str) -> Tuple[PublishedRelease, ...]:
    """Read supported releases only; historical versions cannot become latest."""
    section = markdown_section(document, "Supported versions", 4)
    releases: Dict[str, PublishedRelease] = {}
    for line in section.splitlines():
        if not line.strip().startswith("|"):
            # Ordinary prose and notes are not release rows.
            continue
        cells = [cell.strip() for cell in line.strip().strip("|").split("|")]
        if cells[0] == "Version" or re.fullmatch(r"[-: ]+", cells[0]):
            # Table headings contain no release decisions.
            continue
        if (
            len(cells) != 5
            or cells[3] not in ("Yes", "No")
            or cells[4] not in ("Yes", "No")
        ):
            raise VersionPlanningError(
                "Microsoft's supported-version table has an unexpected format."
            )
        version_match = re.search(r"(?<!\d)(\d{4})(?!\d)", cells[0])
        build_match = re.search(r"\(5\.0+\.(\d{4})(?:\.\d+)?\)", cells[0])
        if not version_match or not build_match:
            raise VersionPlanningError(
                "A supported release row is missing its release or site build."
            )
        version = version_match.group(1)
        if version in releases:
            raise VersionPlanningError(
                "Microsoft's supported-version table lists a release more than once."
            )
        releases[version] = PublishedRelease(version, int(build_match.group(1)))
    if not releases:
        raise VersionPlanningError(
            "Microsoft's supported-version table contains no releases."
        )
    return tuple(
        sorted(
            releases.values(), key=lambda release: int(release.version), reverse=True
        )
    )


def is_globally_available(document: str, version: str) -> bool:
    """Require an explicit release-channel statement for the requested release."""
    channel_section = markdown_section(document, "Early update ring", 3)
    text = " ".join(channel_section.replace("**", "").split())
    prefix = r"\bversion\s+" + re.escape(version) + r"\s+is\s+"
    is_global = (
        re.search(prefix + r"globally available\b", text, re.IGNORECASE) is not None
    )
    is_early = (
        re.search(prefix + r"released for the early update ring\b", text, re.IGNORECASE)
        is not None
    )
    if is_global == is_early:
        raise VersionPlanningError(
            "Cannot establish an unambiguous release channel for SCCM {0}.".format(
                version
            )
        )
    LOGGER.info(
        "SCCM %s has a confirmed %s release statement",
        version,
        "broad" if is_global else "early",
    )
    return is_global


def latest_broad_release(
    read_document: Callable[[str], str] = read_microsoft_markdown,
) -> Tuple[PublishedRelease, Tuple[str, ...]]:
    """Check release statements in descending order without guessing a fallback."""
    sources = [UPDATES_URL]
    for release in published_releases(read_document(UPDATES_URL)):
        checklist_url = (
            LEARN_ROOT
            + "/checklist-for-installing-update-"
            + release.version
            + "?accept=text/markdown"
        )
        sources.append(checklist_url)
        if is_globally_available(read_document(checklist_url), release.version):
            return release, tuple(sources)
        LOGGER.info(
            "Excluding SCCM %s because it is still an early release", release.version
        )
    raise VersionPlanningError(
        "No broadly available release could be established from Microsoft Learn."
    )


def known_release(version: str, catalog: Sequence[Release] = RELEASES) -> Release:
    """Reject a release until its installation requirements are understood."""
    for release in catalog:
        if release.version == version:
            return release
        # Continue looking: catalog ordering has no policy meaning.
    raise VersionPlanningError(
        "SCCM {0} is not in the understood release catalog. Update and test its requirements before deployment; "
        "an older release will not be substituted.".format(version)
    )


def release_for_installed_version(
    version: str, catalog: Sequence[Release] = RELEASES
) -> Release:
    """Accept a release name or full site version, including an installed hotfix."""
    if re.fullmatch(r"\d{4}", version):
        return known_release(version, catalog)
    match = re.fullmatch(r"5\.0+\.(\d{4})\.\d+", version)
    if not match:
        raise VersionPlanningError(
            "Installed versions must be a release such as '2403' or a full site version."
        )
    for release in catalog:
        if release.site_build == int(match.group(1)):
            return release
        # Hotfix revisions do not change which release owns the site build.
    raise VersionPlanningError(
        "Installed site version {0} has an unknown build; inspect it before upgrading.".format(
            version
        )
    )


def upgrade_path(
    source: Release, target: Release, catalog: Sequence[Release] = RELEASES
) -> Tuple[str, ...]:
    """Find the fewest allowed updates, favoring the newest intermediate release."""
    if source.site_build > target.site_build:
        raise VersionPlanningError(
            "Downgrading SCCM is not supported. Deploy a fresh lab to select an older release."
        )
    pending: Deque[Tuple[Release, Tuple[str, ...]]] = deque([(source, ())])
    visited = {source.version}
    candidates = sorted(catalog, key=lambda release: release.site_build, reverse=True)
    while pending:
        current, steps = pending.popleft()
        if current.version == target.version:
            return steps
        for candidate in candidates:
            can_upgrade = (
                current.site_build < candidate.site_build <= target.site_build
                and candidate.minimum_source_version is not None
                and int(current.version) >= int(candidate.minimum_source_version)
                and candidate.version not in visited
            )
            if can_upgrade:
                pending.append((candidate, steps + (candidate.version,)))
                visited.add(candidate.version)
            # Other candidates are older, unreachable, or already examined.
    raise VersionPlanningError(
        "No understood upgrade route connects SCCM {0} to {1}.".format(
            source.version, target.version
        )
    )


def plan_version(
    target_version: str = "latest",
    install_hotfixes: bool = True,
    current_site_versions: Optional[Mapping[str, str]] = None,
    read_document: Callable[[str], str] = read_microsoft_markdown,
    allow_mixed_versions: bool = False,
) -> VersionPlan:
    """Resolve one target and return a route without reading or changing the lab.

    Explicit historical targets work offline. For an existing hierarchy, callers
    must supply actual site versions. Mixed releases require investigation of
    an existing upgrade before a new hierarchy-wide route can be planned.
    """
    if not isinstance(target_version, str) or not re.fullmatch(
        r"latest|\d{4}", target_version
    ):
        raise VersionPlanningError(
            "target_version must be 'latest' or a quoted four-digit release."
        )
    if not isinstance(install_hotfixes, bool):
        raise VersionPlanningError(
            "install_hotfixes must be a YAML boolean: true or false."
        )
    if current_site_versions is not None and not isinstance(
        current_site_versions, Mapping
    ):
        raise VersionPlanningError(
            "current_site_versions must be a dictionary of site names and versions."
        )
    sources: Tuple[str, ...] = ()
    if target_version == "latest":
        published, sources = latest_broad_release(read_document)
        target = known_release(published.version)
        if target.site_build != published.site_build:
            raise VersionPlanningError(
                "Microsoft's published site build disagrees with the understood release catalog."
            )
    else:
        LOGGER.info(
            "Planning the explicitly selected SCCM %s release without a network lookup",
            target_version,
        )
        target = known_release(target_version)

    baseline_version = None
    if current_site_versions:
        installed = []
        for site, version in current_site_versions.items():
            if (
                not isinstance(site, str)
                or not site.strip()
                or not isinstance(version, str)
            ):
                raise VersionPlanningError(
                    "Each current site must have a nonempty name and a string version."
                )
            installed.append(release_for_installed_version(version))
        if (
            len({release.version for release in installed}) != 1
            and not allow_mixed_versions
        ):
            raise VersionPlanningError(
                "Sites have mixed SCCM releases. Inspect and finish the existing update before planning another."
            )
        # The deployment coordinator verifies in-progress packages before it
        # starts work. It can plan from the oldest site to finish an interrupted
        # hop; the standalone preview retains its stricter default.
        starting_release = min(installed, key=lambda release: release.site_build)
        if any(release.site_build > target.site_build for release in installed):
            raise VersionPlanningError(
                "A site already runs a newer release. Downgrading requires a fresh lab."
            )
        LOGGER.info(
            "Planning an existing hierarchy starting at SCCM %s",
            starting_release.version,
        )
    else:
        baselines = [
            release
            for release in RELEASES
            if release.has_baseline and release.site_build <= target.site_build
        ]
        if not baselines:
            raise VersionPlanningError(
                "No understood installation baseline can reach the requested release."
            )
        starting_release = max(baselines, key=lambda release: release.site_build)
        baseline_version = starting_release.version
        LOGGER.info(
            "Planning a fresh hierarchy from the SCCM %s baseline", baseline_version
        )

    steps = upgrade_path(starting_release, target)
    LOGGER.info(
        "Resolved SCCM target %s with %s release updates; additional hotfixes: %s",
        target.version,
        len(steps),
        install_hotfixes,
    )
    return VersionPlan(
        requested_version=target_version,
        target_version=target.version,
        target_site_build=target.site_build,
        starting_version=starting_release.version,
        baseline_version=baseline_version,
        upgrade_versions=steps,
        install_hotfixes=install_hotfixes,
        discovery_sources=sources,
    )
