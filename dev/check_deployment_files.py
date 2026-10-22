"""Check deployment documents and extract embedded scripts for Windows parsing.

This is an offline development check, not a replacement for Ansible checks.
Requires PyYAML in the validation environment. Example:
  python dev/check_deployment_files.py --script-directory /tmp/sccm-script-checks
"""

from __future__ import annotations

import argparse
import ast
from pathlib import Path

import yaml


def extract_scripts(value: object, scripts: list[str]) -> None:
    """Find PowerShell bodies under both modern and existing shell task forms."""
    if isinstance(value, dict):
        for key, child in value.items():
            if key in (
                "script",
                "ansible.windows.win_shell",
                "win_shell",
            ) and isinstance(child, str):
                # Existing tasks contain Jinja expressions; placeholders let
                # PowerShell parse their surrounding syntax without execution.
                import re

                scripts.append(re.sub(r"{{.*?}}", "placeholder", child))
            else:
                extract_scripts(child, scripts)
    elif isinstance(value, list):
        for child in value:
            extract_scripts(child, scripts)


def main() -> None:
    """Validate YAML and shared selection, then save script bodies if requested."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--script-directory",
        type=Path,
        help="Save embedded scripts for parsing, never execution.",
    )
    options = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    documents = [
        *root.glob("*.yml"),
        *root.glob("roles/**/*.yml"),
        *root.glob("roles/**/*.yaml"),
        *root.glob("tests/**/*.yml"),
    ]
    scripts: list[str] = []
    for path in documents:
        value = yaml.safe_load(path.read_text(encoding="utf-8-sig"))
        extract_scripts(value, scripts)
    module = ast.parse((root / "plugins/modules/sccm_version_plan.py").read_text())
    for statement in module.body:
        if (
            isinstance(statement, ast.Assign)
            and isinstance(statement.value, ast.Constant)
            and isinstance(statement.value.value, str)
        ):
            yaml.safe_load(statement.value.value)
    config = yaml.safe_load((root / "new-config.yml").read_text())
    settings = config["ludus"][0]["role_vars"]
    coordinators = []
    for vm in config["ludus"]:
        for key in ("ludus_sccm_target_version", "ludus_sccm_install_hotfixes"):
            assert vm["role_vars"][key] == settings[key], (vm["hostname"], key)
        for role in vm["roles"]:
            if role["name"] == "mayyhem.ludus_sccm.service_hierarchy":
                coordinators.append((vm, role))
    assert len(coordinators) == 1, "Exactly one hierarchy coordinator is required"
    assert coordinators[0][0]["hostname"] == "cas-pss"
    dependencies = {item["role"] for item in coordinators[0][1]["depends_on"]}
    for required in (
        "install_primary_site",
        "install_sms",
        "install_passive_site_server",
        "install_secondary_site",
    ):
        assert "mayyhem.ludus_sccm." + required in dependencies, required
    if options.script_directory:
        options.script_directory.mkdir(parents=True, exist_ok=True)
        for index, script in enumerate(scripts):
            (options.script_directory / f"embedded-{index:03}.ps1").write_text(
                script, encoding="utf-8"
            )
    print(
        f"Parsed {len(documents)} YAML files and module help; checked shared settings and coordinator dependencies; found {len(scripts)} embedded scripts."
    )


if __name__ == "__main__":
    main()
