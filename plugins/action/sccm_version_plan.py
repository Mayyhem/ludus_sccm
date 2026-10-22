"""Run read-only SCCM version planning on the Ansible controller.

An action plugin keeps Python and internet requests on the Linux controller;
Windows guests do not need Python. There is no corresponding Windows script.
"""

from typing import Dict, Optional

from ansible.plugins.action import ActionBase
from ansible_collections.mayyhem.ludus_sccm.plugins.module_utils.sccm_deployment import (
    deployment_settings,
)
from ansible_collections.mayyhem.ludus_sccm.plugins.module_utils.sccm_versions import (
    VersionPlanningError,
    plan_version,
)


class ActionModule(ActionBase):
    """Return one resolved plan, including in Ansible check mode."""

    TRANSFERS_FILES = False
    _requires_connection = False
    _supports_check_mode = True
    _supports_async = False
    _VALID_ARGS = frozenset(
        (
            "target_version",
            "install_hotfixes",
            "current_site_versions",
            "allow_mixed_versions",
        )
    )

    def run(
        self,
        tmp: Optional[str] = None,
        task_vars: Optional[Dict[str, object]] = None,
    ) -> Dict[str, object]:
        """Validate task input and return a plan or an explanatory task failure."""
        # Ansible owns these loosely typed arguments and result dictionaries.
        # Validation stays at this boundary before calling the typed planner.
        result = super().run(tmp, task_vars)
        options = self._task.args
        target = options.get("target_version", "latest")
        hotfixes = options.get("install_hotfixes", True)
        sites = options.get("current_site_versions", {})
        if not isinstance(sites, dict):
            result.update(
                failed=True,
                changed=False,
                msg="current_site_versions must be a dictionary of site names and versions.",
            )
            return result
        try:
            allow_mixed = options.get("allow_mixed_versions", False)
            if not isinstance(allow_mixed, bool):
                raise VersionPlanningError(
                    "allow_mixed_versions must be a YAML boolean."
                )
            plan = plan_version(
                target, hotfixes, sites, allow_mixed_versions=allow_mixed
            )
        except VersionPlanningError as error:
            result.update(failed=True, changed=False, msg=str(error))
            return result
        result.update(
            changed=False,
            plan=plan.to_dict(),
            deployment=deployment_settings(plan),
            msg="Read-only SCCM plan resolved. Installation and servicing are not performed by this action.",
        )
        return result
