# SCCM version selection and lab upgrade plan

Plan agreed on 2026-10-21. This document describes the intended work, the reasons for it, and the evidence needed before calling it complete. It is not a claim that the features below already exist.

## Agreed outcome

Update this Ansible collection so a fresh Ludus deployment finishes on the requested SCCM release. Also provide a supported route for upgrading the existing mayyhem.com research lab. Preserve its hierarchy and intentional research settings where the selected Microsoft release permits them.

The user-facing settings will be:

```yaml
ludus_sccm_target_version: "latest"
ludus_sccm_install_hotfixes: true
```

An explicit release, such as `"2509"`, means stop at that release. `"latest"` means automatically choose the newest broadly available current-branch release, excluding technical previews and early-release opt-ins. Resolve and record the target once for each deployment so it cannot change halfway through. A later deployment can select a newer release.

The hotfix switch defaults to true and includes applicable SCCM hotfixes for the selected release. False skips additional hotfixes. It never uninstalls fixes already present. Selecting an older release or earlier patch level on an existing installation must explain that a fresh lab is required, rather than automatically removing or rebuilding anything. Fixes already included in installation media cannot be removed by this switch.

Completion includes CAS, PS1, SEC, the passive site server, remote roles, installed consoles, and reachable lab clients. Update and redistribute the boot images used by the lab. List unreachable or incomplete systems explicitly. Match each component against its expected version; console and client version numbers need not equal the site version number.

## Working boundaries

- Work in `C:\Users\domainadmin\ludus_sccm`. Do not change OpenHound or its shared libraries.
- Do not stage, commit, push, create a release, or publish the collection. The owner will review and perform Git actions.
- Implementing the collection does not itself authorize starting an upgrade, restarting guests, or rebuilding the running lab during this development pass. Preserve it for the owner's branch testing.
- Active tests may target only 10.10.10.0/24, 10.10.11.0/24, and mayyhem.com objects reached through authorized hosts. Validate DNS results before remote access.
- Use existing Ansible and PowerShell facilities where practical. Add no new runtime dependency without checking its license and documenting why it is needed. This collection already declares GPL-3.0-or-later; do not copy its implementation into the Apache-licensed collector.
- Keep comments and documentation in plain English. New tests belong under `tests/`.
- Supporting-software policy: retain existing Windows and SQL major versions where practical; change prerequisites needed for compatibility and support. A general Windows/SQL modernization is not an agreed goal.

## Evidence from the existing lab

Read-only inspection on 2026-10-21 found:

| Component | Observed state | Consequence |
| --- | --- | --- |
| CAS, PS1, SEC | SCCM 2403, 5.00.9128.1000 | An intermediate release is needed before the then-current broadly available target, 2603. |
| CAS-DB and PS1-DB | SQL Server 2022 Developer RTM, 16.0.1000.6 | Review supported SQL updates. |
| CM_CAS and CM_PS1 | Compatibility level 160 | Use supported level 150 while on releases before 2603; verify behavior before and after the change. |
| PS1-SEC | SQL Server 2016 Express SP2, 13.0.5026.0 | Plan SP3 before an in-place SQL Server 2022 Express upgrade. |
| SCCM software inventory | ADK 10.1.25398.1 with WinPE add-on 10.1.22621.5337 | Recheck installed versions directly, then replace with a supported combination. |
| SQL connection drivers | Mixed 18.1.2.1 and 18.5.2.1 | Some hosts need newer drivers; the existing unconditional 18.5.2 pin cannot serve all future targets. |
| Inspected site servers | Windows Server 2022, .NET Framework 4.8 | No general server OS replacement is proposed. |
| CAS update catalog | Includes 2509 but not 2603 | The newest visible package is not necessarily the final reachable release; refresh after intermediate upgrades. |

At that inspection, Microsoft described 2603 as globally available and 2609 as early release. These are dated observations, not permanent defaults. The proposed existing-lab route was 2403 -> 2509 -> 2603. Microsoft's evaluation download advertised 2509, giving a proposed fresh route of 2509 -> 2603. Revalidate availability and requirements before a live run.

## Design and alternatives

### Release selection and upgrade paths

Keep a small central list of understood releases with their build numbers, available baseline media, prerequisite requirements, and allowed source versions. Resolve explicit requests against that list. For `latest`, establish Microsoft's broadly available release independently of the packages currently applicable to an older site. Do not treat a release date, the largest build number, or presence in an opted-in early catalog as proof of broad availability.

Use Microsoft's published release/checklist information and the site's normal servicing catalog, with a documented source contract and tests. If those sources disagree or cannot establish broad availability, stop with an actionable message. Do not silently choose an older release. A newly published release with requirements the collection does not understand must also stop clearly; automatic release discovery does not eliminate maintenance of compatibility rules.

Choose installation media separately from the final target. Fresh installations use a supported baseline and then the necessary updates. CAS expansion must use media compatible with the primary site being expanded. Do not run release upgrades concurrently with CAS expansion or creation of other site roles.

Existing deployments compare the requested build with actual site builds. Same release means verify and finish requested fixes; older means plan the supported upgrade route; newer means reject a downgrade. A mixed-version hierarchy requires checking update progress rather than blindly starting another update. Readiness and recovery checks must distinguish an update in progress, a failure, and a completed installation.

A single hardcoded newest release was rejected because the owner wants automatic broad-release selection. An unrestricted newest-version lookup was rejected because early releases and incompatible prerequisites must be excluded. Reinstalling SCCM to change versions was rejected because it would destroy research state.

### Prerequisites and cached installers

Make prerequisite decisions depend on the starting release, each intermediate release, and the final target. Review SQL engine support, database compatibility level, .NET, ADK/WinPE, ODBC, Visual C++ runtimes, Windows support, disk space, and pending restarts on applicable hosts.

Use supported ADK/WinPE components, not simply the newest downloads. Microsoft currently identifies ODBC 18.6.1.1 as problematic and 18.7.1.1 as incompatible with SCCM 2603 and earlier. Do not generalize that every version after 18.6.1 is broken. Confirm exact requirements and installer signatures before use.

Installer cache names and extraction directories must distinguish media versions. Check the installed version and downloaded content, not just whether a file exists. Replace misleading 2303 filenames used for 2403 downloads. Keep advanced installer URL/checksum overrides documented and validate that the supplied media matches the planned release.

For the existing secondary SQL instance, plan an SP3 update before SQL Server 2022 Express. Follow Microsoft's SQL upgrade procedure and verify the secondary database and replication afterward. Do not assume an SCCM update upgrades an existing SQL instance just because its new-site installation media contains a newer Express installer.

### One final hierarchy update role

Add one coordinating role at the top-level site after all required installation roles have really finished. Wire its prerequisites in `new-config.yml` so CAS expansion, provider installation, passive-server installation, and secondary-site creation cannot race it. Also document standalone-primary usage without assuming that CAS, a passive server, or SEC exists.

For each release hop:

1. Verify health, required backups/recovery arrangements, and prerequisite checks. Record maintenance settings before temporary changes.
2. Refresh the servicing catalog, obtain the intended package, and wait for download completion.
3. Start the update at CAS (or the standalone primary), using Microsoft's supported management commands.
4. Wait for the primary sites, passive servers, and affected remote roles to finish. Verify actual builds and readiness.
5. Initiate each secondary-site upgrade after its parent finishes and wait for completion.
6. Verify replication before starting another release hop.

Handle long-running work with bounded waits, progress messages, and useful failure evidence. A timeout must report the affected site, current stage, and relevant log locations. On a rerun, inspect current state and continue safely. Never route an existing-site upgrade through the fresh-install retry/uninstall logic.

Use one resolved target throughout the run. Never start concurrent hierarchy updates from every site server.

### Actual completion, fixes, consoles, clients, and boot images

Correct the secondary and passive installation roles, which currently write SUCCESS after submitting the installation request. Site presence and a running SMS_EXECUTIVE service do not establish installation success, requested version, or readiness.

When requested, select applicable updates for the chosen release, account for superseded packages and required installation order, and refresh after each installed fix. Use applicability rather than assuming that every KB listed online belongs on every lab.

Update installed consoles using the corresponding site's supported console installer. Upgrade reachable clients and verify their expected versions. Record failures and unreachable devices rather than silently omitting them. Refresh and redistribute used boot images and verify distribution completion.

Preserve intentional lab settings. Microsoft's security changes may remove older research behavior: 2603 changes access to Network Access Account information. Document changed behavior and compare collector results rather than treating every changed graph count as a collector failure.

## Delivery order and progress

- [x] Inspect the repository and existing lab read-only; agree on release selection, hotfix switch, full completion scope, and installation-check fixes.
- [x] Save this complete plan in the repository.
- [x] Implement and test the release-selection and upgrade-path foundation (36 offline tests and a live Microsoft document read; actual Ansible execution remains pending on Linux).
- [x] Connect selected baseline media and version-aware prerequisite/cache handling to installation roles (implementation; host validation pending).
- [x] Correct secondary and passive installation completion checks (implementation and offline behavior checks).
- [x] Implement and wire the final hierarchy update role, including state-aware reruns (live rerun validation pending).
- [x] Write applicable hotfix, console, client, boot-image, and final-report operations (live validation pending).
- [x] Update README and development/upgrade instructions; add review evidence and proposed Git commands.
- [ ] Validate a fresh deployment and rerun in an isolated authorized lab copy on the owner's test branch.
- [ ] Validate the existing-lab upgrade after recovery arrangements and the live execution window are agreed.

Update this progress section and the implementation notes as work proceeds. Do not mark live validation complete based on offline checks.

### First implementation checkpoint, 2026-10-21

The read-only planner, optional `plan_sccm_version` role, controller action,
CLI preview, focused tests, and implementation guide now exist. See
[docs/version-selection.md](docs/version-selection.md) for how they work,
limitations, exact verification commands, and the proposed owner review/commit
commands. The normal installation roles and `new-config.yml` have not been
switched to version selection. The hotfix policy is recorded but not applied.
No live lab mutation, staging, commit, or push has been performed.

### Host-test implementation checkpoint, 2026-10-22

The preparation/install roles and sample configuration now use version selection.
The root servicing role and Windows helpers are written, including component
updates, real secondary/passive completion checks, recovery material, and JSON
reporting. Local checks passed: 40 Python tests, 22 PowerShell behavior checks,
YAML/module-help and PowerShell parsing, focused Python checks, and whitespace
checks. These are offline checks, not evidence of a completed lab upgrade.

No Linux controller was available. At the owner's request, the next agent has
a [Ludus-host handoff](docs/LUDUS_HOST_HANDOFF.md) with build, Ansible checks,
artifact installation, test cases, concrete uncertainties and recovery evidence.
In particular, media extraction, multi-role target sharing in Ludus, vendor
installer behavior and live component servicing need host testing. No lab
upgrade, Git staging, commit or push was performed.

## Validation and acceptance

### Offline checks

Use focused tests under `tests/` for explicit/latest selection, early-release exclusion, malformed/unavailable release data, numeric build ordering, missing intermediate paths, downgrade rejection, and per-run target consistency. Test mixed-version/in-progress hierarchy handling, hotfix filtering, stale caches, prerequisite differences, and ready-vs-started installation states as those pieces are implemented.

Run PowerShell parsing and relevant PowerShell behavior checks on Windows. Use Ansible syntax/build checks on a supported Linux controller. Ansible is not installed on this workstation at plan creation; identify a suitable controller or an isolated Linux validation environment before claiming those checks passed. Do not change the collector's Python environment.

### Live checks

Before changes: record configuration and collector results; verify healthy file/database replication, backups and recovery files, free space, restart state, and installer access. Arrange a coordinated lab recovery point. Existing remote roles and clients must be included in the inventory.

Test fresh deployment at a historical supported target and at `latest`, both hotfix policies, and a second run of the same configuration. Exercise a failed/interrupted update without destroying the existing lab. Validate the existing 2403 hierarchy through its supported path separately. Confirm CAS expansion, passive readiness, SEC readiness, all expected site/role builds, replication, client policy and inventory, content delivery, console access, and boot-image distribution. Compare collector results and investigate unexplained losses.

A deployment passes only when requested components are ready at their expected versions. List unreachable clients separately. A reachable component that failed to update makes the result incomplete. A no-hotfix run must not apply optional fixes, and a rerun must not downgrade or reinstall working sites.

### Recovery

Preserve SCCM-supported site/database recovery material and customized files. Verify Proxmox access, backup storage, and a coordinated recovery procedure before live execution. Do not assume that reverting one database VM while the rest of a replicated hierarchy continues running is a valid rollback. Reverting an entire isolated research range is a lab operation requiring an agreed recovery point, including domain state where relevant. Preserve development files outside guest snapshots before restoring them.

## Documentation and review deliverables

README: new settings, placement in the Ludus configuration, supported release choices, fresh-vs-existing behavior, hotfix semantics, expected duration and internet requirements, and limitations. Provide examples using mayyhem.com without publishing credentials in test evidence.

Upgrade/development notes: problem, selected approach, alternatives, exact responsibilities of changed files, dependencies/licenses, downstream effects, test commands/results, manual verification, and known uncertainties. Document recovery and the distinction between submitted work and finished installation.

After implementation, recommend a concise commit message and exact staging/commit commands for the owner's review. Do not execute them. Do not push. The owner may use a new branch for live validation before merging.

## Authoritative references

- SCCM baseline and update versions: https://learn.microsoft.com/en-us/intune/configmgr/core/servers/manage/updates
- 2509 checklist: https://learn.microsoft.com/en-us/intune/configmgr/core/servers/manage/checklist-for-installing-update-2509
- 2603 checklist and broad availability: https://learn.microsoft.com/en-us/intune/configmgr/core/servers/manage/checklist-for-installing-update-2603
- 2609 checklist and early-release status: https://learn.microsoft.com/en-us/intune/configmgr/core/servers/manage/checklist-for-installing-update-2609
- Evaluation media: https://www.microsoft.com/en-us/evalcenter/download-microsoft-endpoint-configuration-manager
- SQL support and compatibility levels: https://learn.microsoft.com/en-us/intune/configmgr/core/plan-design/configs/support-for-sql-server-versions
- SQL 2022 upgrade requirements: https://learn.microsoft.com/en-us/sql/database-engine/install-windows/supported-version-and-edition-upgrades-2022?view=sql-server-ver16
- Infrastructure upgrades: https://learn.microsoft.com/en-us/intune/configmgr/core/servers/manage/upgrade-on-premises-infrastructure
- ADK support: https://learn.microsoft.com/en-us/intune/configmgr/core/plan-design/configs/support-for-windows-adk
- Prerequisite checks and ODBC restrictions: https://learn.microsoft.com/en-us/intune/configmgr/core/servers/deploy/install/list-of-prerequisite-checks
- Hierarchy update procedure: https://learn.microsoft.com/en-us/intune/configmgr/core/servers/manage/install-in-console-updates
- Passive-server servicing: https://learn.microsoft.com/en-us/intune/configmgr/core/servers/deploy/configure/site-server-high-availability
- Backup material: https://learn.microsoft.com/en-us/intune/configmgr/core/servers/manage/backup-and-recovery
- 2603 behavior changes: https://learn.microsoft.com/en-us/intune/configmgr/core/plan-design/changes/whats-new-in-version-2603
- Supported update management commands: https://learn.microsoft.com/en-us/powershell/module/configurationmanager/install-cmsiteupdate?view=sccm-ps
