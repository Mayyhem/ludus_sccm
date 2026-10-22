# This file documents the controller-only action plugin of the same name.
# All execution happens in plugins/action/sccm_version_plan.py, including for
# Windows hosts. No remote Python module or PowerShell implementation is needed.

DOCUMENTATION = r"""
---
module: sccm_version_plan
short_description: Plan a requested SCCM release without changing the lab
description:
  - Runs on the Ansible controller and returns a read-only installation or upgrade route.
  - Explicit releases work offline; latest requires Microsoft Learn internet access.
  - Does not install SCCM, apply fixes, inspect guest state, or alter deployment defaults.
  - Requires Python 3.8 or newer on the controller.
options:
  target_version:
    description: Desired quoted release number, or latest for the newest confirmed broadly available release.
    type: str
    default: latest
  install_hotfixes:
    description: Record whether the eventual deployment should apply additional hotfixes. Does not apply or remove fixes.
    type: bool
    default: true
  current_site_versions:
    description: Actual versions of all existing sites. Omit for a fresh deployment plan.
    type: dict
    default: {}
  allow_mixed_versions:
    description: Plan from the oldest site when a deployment coordinator will verify and finish an interrupted hierarchy update. False remains the safe preview default.
    type: bool
    default: false
author:
  - Chris Thompson (@_Mayyhem)
"""

EXAMPLES = r"""
- name: Plan a fresh deployment on the latest broad release
  mayyhem.ludus_sccm.sccm_version_plan:
    target_version: latest
    install_hotfixes: true
  register: version_result

- name: Plan the existing mayyhem.com hierarchy
  mayyhem.ludus_sccm.sccm_version_plan:
    target_version: '2603'
    current_site_versions:
      CAS: '5.00.9128.1000'
      PS1: '5.00.9128.1000'
      SEC: '5.00.9128.1000'
  register: version_result
"""

RETURN = r"""
plan:
  description: Resolved release, starting baseline or existing release, update sequence, hotfix policy, and discovery sources.
  returned: success
  type: dict
deployment:
  description: Separate fresh-install media, supported prerequisites, and release builds used by deployment roles.
  returned: success
  type: dict
"""
