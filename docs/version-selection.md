# Selecting and servicing an SCCM lab release

Assisted host validation passed on October 27, 2026 in the authorized isolated cthompson range: no lab -> baseline 2509 -> broadly available 2609. CAS, PS1, SEC, the passive server, twelve installed clients, both consoles and the deployed boot image passed verification. MP HTTP, one-block TFTP delivery, fresh DEV inventory and post-recovery SEC integrity checks passed. The final component rerun changed no components. The final source has not yet passed a new clean rebuild from zero; native restart/resume handling is now integrated and clean validation is in progress. Controller/build checks, 119 isolated PowerShell behaviors and three live client-detection cases also passed. Existing research-lab upgrades and other fresh topologies remain untested. See the [host handoff](LUDUS_HOST_HANDOFF.md) for the exact evidence and retained incident disclosure, and the [full plan](../UPGRADE_PLAN.md) for scope. Earlier deployment notes below are historical.

## Choose the result

Edit the shared settings on the first VM in `new-config.yml`:

```yaml
role_vars: &sccm_version_settings
  ludus_sccm_target_version: "latest"
  ludus_sccm_install_hotfixes: true
```

Keep the `ludus_sccm_component_hosts` list below those settings. Every other VM merges the shared settings using `<<: *sccm_version_settings`. Change the two values once, keeping release numbers quoted. For example, `"2509"` and `false` select 2509 without adding optional hotfixes. False never removes an installed fix or a fix bundled into installation media.

| Selection | Fresh installation | Existing installation |
| --- | --- | --- |
| `"2403"` | 2403 baseline | Verify 2403; refuse a downgrade |
| `"2409"` | 2403, then 2409 | Follow the permitted release route |
| `"2503"` | 2403, then 2503 | Follow the permitted release route |
| `"2509"` | 2509 baseline | Update from 2403 or later |
| `"2603"` | 2509, then 2603 | From the observed 2403 lab: 2509, then 2603 |
| `"2609"` | 2509, then 2609 | Update from 2503 or later; from 2403 use 2509 first |
| `"latest"` | Resolve Microsoft's broad release, then choose baseline and route | Resolve the same way, then use actual site versions |

On October 22, 2026, Microsoft's documentation identified 2603 as globally available and 2609 as early release. The live Microsoft Learn Markdown endpoint announced 2609 broad availability on October 26 while a cached web response still described early access. The existing resolver correctly stopped when the newly broad release was not understood; the catalog now includes reviewed 2609 requirements. These are dated observations. The planner rejects an unknown future release until its installation path and prerequisites have been reviewed. Unreadable or ambiguous release evidence stops planning instead of silently selecting an older release. Explicit historical selections work without release-document internet access, although installation still needs downloads.

## Problem, solution, and alternatives

Previously the roles downloaded 2403 and could stop after starting installation. The new code distinguishes the requested final release, installation media, installed site versions, and finished component updates. Microsoft Learn proves broad availability; SCCM's normal servicing catalog supplies applicable updates. The highest update currently visible to an old site does not establish the latest release it can eventually reach.

A fixed latest release would contradict automatic selection. Guessing from a release date could select an early release. Reinstalling an existing site would discard lab state. Those approaches were rejected. The chosen approach keeps the installation roles and adds one coordinating servicing role.

```mermaid
flowchart TD
    A[Resolve requested release] --> B[Prepare supported prerequisites]
    B --> C{Site installed?}
    C -->|No| D[Install selected baseline and hierarchy roles]
    C -->|Yes| E[Keep existing site installation]
    D --> F[One servicing coordinator at CAS]
    E --> F
    F --> G[Apply required releases in order]
    G --> H[Finish secondary and passive updates]
    H --> I[Apply applicable hotfixes when enabled]
    I --> J[Update installed consoles and reachable clients]
    J --> K[Refresh used boot images and verify distribution]
    K --> L[Write completion report]
```

## Where the behavior lives

| File or role | Responsibility |
| --- | --- |
| `plugins/module_utils/sccm_versions.py` | Read release evidence, reject invalid selections and downgrades, choose supported update routes |
| `plugins/module_utils/sccm_deployment.py` | Baseline URLs, prerequisite downloads, release build numbers |
| `plugins/action/sccm_version_plan.py` | Run planning on the controller; Windows does not need Python |
| `roles/sccm_common` | Share the selection during an Ansible invocation, download files, provide Windows helpers |
| `roles/prepare_sccm` | Install and verify ODBC, Visual C++, and, where needed, ADK and WinPE; restart when required |
| `roles/prep_siteserver/tasks/media.yml` | Download/extract versioned media; verify Microsoft signatures and embedded setup build |
| `roles/install_primary_site` | Use selected media for fresh setup; an installed-site registry value keeps existing sites out of fresh-install retry/uninstall handling |
| `roles/install_secondary_site/tasks/verify.yml` | Wait for active provider state, installed version, and running SMS Executive |
| `roles/install_passive_site_server/tasks/verify.yml` | Wait for completed HA preparation, prerequisites, installation, post-installation, and installed version; never request promotion |
| `roles/service_hierarchy/tasks/main.yml` | Read actual versions, plan remaining work, run updates and final checks, fetch evidence even on failure |
| `roles/service_hierarchy/files/Update-SccmRelease.ps1` | Start or rejoin release updates at the root; save recovery material, finish secondaries/passive servers, wait for replication |
| `roles/service_hierarchy/files/Update-SccmHotfixes.ps1` | Apply registered applicable unsuperseded fixes and refresh after each update |
| `roles/service_hierarchy/files/Complete-SccmDeployment.ps1` | Verify sites/roles/providers; update installed consoles/clients; refresh distributed boot images; save the report |
| `roles/sccm_common/files/SccmDeployment.psm1` | Shared prerequisite, update-state, SQL, readiness, logging, and bounded-wait operations |

The secondary installation fallback now recognizes site type 1. The passive installation check recognizes the actual `SMS Site Server` role and uses a valid WMI namespace. Existing submission status files remain, but role success now also requires final readiness checks.

## Prerequisites, media, and recovery

The understood releases currently share ODBC 18.6.2.1, ADK 10.1.26100.9457 and the supported 26100 WinPE add-on. These replace old incompatible packages. Registry inventory avoids `Win32_Product`, which can repair software just by querying it. .NET Framework 4.8 is checked, not installed automatically. ADK preparation runs on site servers and SMS Provider hosts. ODBC preparation also runs on database and management-point hosts.

2609 requires SQL Server 2017 CU2 or newer at every site, including secondary
Express instances. The fresh test range already uses SQL 2022. Keep ODBC
18.6.2.1 while servicing the 2509 baseline: ODBC 18.7.1.1 blocks 2603 and earlier.
2609 setup supplies OLE DB 19.4.2.0 and newer Visual C++ components and removes
the Native Client dependency. Existing intentional client-approval settings are
preserved; review any resulting prerequisite warning before enabling warnings.
The reviewed requirements and live tests remain distinct: final 2609 acceptance
is pending.

Dedicated lab SQL databases and the SQL template database use compatibility 150 during baseline/intermediate installation. CAS/PS1 retain their existing SQL engines. The secondary's named SQL 2016 Express instance is backed up, patched to SP3, then upgraded to SQL 2022 Express using its parent's 2509-or-newer CD.Latest files. This may restart the secondary. Existing SQL 2017-or-newer instances are retained. Historical parents lacking newer Express media require an owner-managed SQL upgrade if needed. SCCM setup checks remain authoritative.

Before a new SCCM update, the code checks site active state, at least 50 GB free on site-server system disks, pending Windows update/CBS restart state, and replication readiness. It creates SQL COPY_ONLY backups with checksums and runs RESTORE VERIFYONLY. SQL backups remain in each SQL host's configured backup directory; after each new backup verifies, older `CM_<site>_ludus_<timestamp>.bak` files for that database are deleted, so only the newest lab backup is kept (about 2.5 GB per CAS/primary database). Other backup files are never touched, and a failed cleanup only logs a warning. CAS/primary CD.Latest copies go under `C:\ludus\sccm\recovery\<site>\<version>`. These checks supplement SCCM prerequisite checks and an agreed coordinated recovery point; they do not prove a full recovery restore.

Versioned cache files live under `/opt/ludus/resources/sccm` by default; `ludus_sccm_cache_directory` overrides the controller cache location. Set `ludus_sccm_download_on_guest: true` to download installers directly on each Windows guest when the Ludus worker cannot access the controller cache. This requires guest Internet access and retains the same signature/build verification. An optional checksum must be a literal `algorithm:hex` value. Guest media lives under `C:\ludus\sccm\media\<baseline>`. Optional `ludus_sccm_media_url` and `ludus_sccm_media_checksum` settings override the chosen baseline download. A checksum uses Ansible's `sha256:<hex>` form. Overrides still require valid Microsoft signatures and the expected setup build. Remove a damaged cached download before retrying. The existing installation roles still assume the default Windows work directory; changing `ludus_sccm_work_directory` across the whole lab is not supported in this change.

## Updates, retries, and completion

One root coordinator waits for CAS expansion, provider installation, passive installation, and secondary installation. For a standalone primary, place `mayyhem.ludus_sccm.service_hierarchy` after all role-installation work and set `ludus_sccm_sitecode` to that primary's code.

The coordinator reads actual versions. It can plan from the oldest site in an interrupted hierarchy, but refuses a different running update. A matching active update is observed without another setup request. Failed update states require correcting the cause and using the console's supported retry. No database state reset is performed. Native site-update, Windows prerequisite, console and client restart checkpoints leave the phase incomplete. Ansible validates the target against the current range inventory, waits for idle installers, performs a normal serial restart, verifies the native post-boot state and resumes the phase. Restart rounds are bounded; see the [servicing role settings](../roles/service_hierarchy/README.md). Fresh-install retries remain separate from servicing.

Prerequisite errors always stop. Warnings stop by default. After examining ConfigMgrPrereq.log, an owner can set `ludus_sccm_allow_prerequisite_warnings: true` in the shared settings. This permits warnings only and never skips errors.

The hotfix switch covers fixes registered in SCCM servicing, including already imported fixes. It does not download arbitrary out-of-band hotfix tools or import every KB mentioned online. Supersedence only hides a fix when its replacement is available. Two scans without an eligible fix finish discovery; live testing must verify synchronization timing.

Final checks require all site versions to match the chosen root release/revision, healthy summarized MP/DP/site-server state, current provider builds, and passive readiness. Console versions come from the site's advertised console version. Client versions come from the assigned primary's production client baseline, cross-checked against its MSI release; they need not equal the site version. Source files are copied to each endpoint before execution, avoiding credentials forwarded to a third host. A console/client newer than the selected source produces a failure instead of a downgrade.

Installed console identity comes from native `AdminConsoleVersion` in
`ConfigMgr10\Setup`, after verifying its MSI registration and registered
executable. MSI `DisplayVersion` can retain an earlier revision: fresh 2509 has
MSI 5.2509.1036.1000 while its native product version is 5.2509.1036.1200.
Individual console DLLs also have their own component versions. None of those
substitute for the exact native product version advertised by the site.

Passive installation allows five minutes for native substage 0xe000c to retry
initial site validation after stages 11–13 complete. Other failed substages stop
immediately. The helper changes no HA state or site keys; both completed native
stages and the installed version are still required before deployment proceeds.

Registered nonobsolete clients, site systems, and `ludus_sccm_component_hosts` are inspected. The sample list includes ps1-dev so consoles are found before client discovery. Machines without a client/console are not given one. Unreachable management endpoints are listed separately. Unreachable management endpoints and reachable component failures prevent completion. WinRM availability defines whether endpoint operations can run.

Distributed boot images are reloaded through the supported distribution-point command. All assigned distribution points must report the new source version installed. Undistributed images are logged and skipped. A saved journal lets a successful rerun verify images without rebuilding them again. Unsupported old custom images may need owner repair before reload succeeds.

## Read the results

The root server writes logs and JSON under `C:\ludus\sccm`:

- `hierarchy-update.log`: release/hotfix progress.
- `deployment-verification.log`: final component work and failures.
- `deployment-report.json`: completion, versions, endpoints, and failures.
- `database-backups.json` and `hotfix-database-backups.json`: SQL backup locations.
- `boot-image-journal.json`: completed image refreshes.

Ansible fetches root logs/reports to `/opt/ludus/resources/sccm/reports/<range_id>/<inventory_hostname>/`. A failed fetch remains visible and does not replace the original failure. Prerequisite/readiness logs remain on their respective guests. SQL backups and recovery media are not automatically copied to the controller.

`Complete: true` describes these component checks. Independently test console access, client policy/inventory, content delivery, PXE, and collector behavior after a live deployment. Microsoft's 2603 changes to Network Access Account information can change research/collector results.

## Dependencies and validation status

No new Python runtime package, extraction utility, Ansible collection, or PowerShell module is added. Existing Ansible Windows/AD collections remain required. Microsoft installers carry their own terms. This lab collection already uses GPL-3.0-or-later. Offline YAML validation uses PyYAML 6.0.3 (MIT); Ruff 0.17.1 and ty 0.0.90 (MIT) are validation tools only.

Local Windows validation on October 22, 2026: 40 Python unit tests and 22 PowerShell behavior checks passed. YAML/module-help parsing, PowerShell parsing, focused Python lint/format/type checks and `git diff --check` passed. No lab upgrade, staging, commit, or push was performed at that checkpoint.

Linux validation on October 23 passed the 40 Python unit tests, YAML checks, collection build and isolated installation, installed module documentation, planner integration execution in normal/check mode, and deployment-role syntax checks. The authorized live run uses only range/user `cthompson`, with `latest` and hotfixes enabled. All 15 VMs were provisioned, domain joins and DNS were verified, and collection base roles began. The owner requested resumption after an unexpected host reboot; the full deployment is running again against the same guests. Optional Chocolatey utilities were removed from the test copy because the host's shared Nexus dependency is outside the authorized range. Vendor extraction, site installation, release servicing, and final component checks have not passed yet. See the plan for evidence and platform failures encountered during provisioning.

The resumed run completed SQL setup and reached 2509 media extraction. Its
Microsoft-signed executable uses 7-Zip SFX switches (`-y -o"<directory>"`), so
the task now detects that format instead of passing the legacy switches.
Extraction has a 30-minute limit and a completion marker written after setup
signature/build verification. Older media keeps its original switches. The
fix passed 27 Windows PowerShell behavior checks and parsing of 61 files;
actual extraction/signature/build verification passed with `5.0.9141.1002`.
The new archive has `SMSSETUP` at its root, so it is extracted into
`cd.retail.LN` to preserve the collection's shared media path. Deployment
resumes on the existing guests; site/servicing acceptance remains pending.

The first primary setup exposed a missing x86 Visual C++ runtime required by
the vendor's OLE DB 19 installer. Prerequisite preparation now downloads and
verifies both x86/x64 runtimes independently of the installed ODBC version,
retains newer runtime versions, and checks registration after execution. The
fix passed 31 PowerShell behavior checks and the previously failing OLE DB MSI
installed successfully on PS1 after repair. Deployment resumed following its
restart; site/servicing acceptance remains pending.

PS1 baseline setup subsequently completed with its console and running SMS
Executive. Remote scheduled-task activation for computer-policy refresh failed
with Access Denied. The policy module now refreshes the local computer directly
and remote computers through WinRM, reports per-computer results, and honors
check mode. A live scoped check listed exactly 13 intended member computers
without changes, then successfully refreshed all 13. Offline Windows checks now
pass 34 behavior scenarios and 62 parses. Remaining hierarchy/servicing
acceptance is pending.

Important sources:

- [Release/baseline versions](https://learn.microsoft.com/en-us/intune/configmgr/core/servers/manage/updates)
- [2509 checklist](https://learn.microsoft.com/en-us/intune/configmgr/core/servers/manage/checklist-for-installing-update-2509)
- [2603 checklist](https://learn.microsoft.com/en-us/intune/configmgr/core/servers/manage/checklist-for-installing-update-2603)
- [2609 checklist](https://learn.microsoft.com/en-us/intune/configmgr/core/servers/manage/checklist-for-installing-update-2609?accept=text/markdown)
- [ADK support](https://learn.microsoft.com/en-us/intune/configmgr/core/plan-design/configs/support-for-windows-adk)
- [Prerequisite checks](https://learn.microsoft.com/en-us/intune/configmgr/core/servers/deploy/install/list-of-prerequisite-checks)
- [Update states](https://learn.microsoft.com/en-us/troubleshoot/mem/configmgr/setup-migrate-backup-recovery/understand-troubleshoot-updates-servicing)
- [Client installer arguments/exit codes](https://learn.microsoft.com/en-us/intune/configmgr/core/clients/deploy/about-client-installation-properties)
- [SQL upgrade paths](https://learn.microsoft.com/en-us/sql/database-engine/install-windows/supported-version-and-edition-upgrades-2022?view=sql-server-ver16)
- [Ludus CLI](https://docs.ludus.cloud/docs/cli)

Network media copies explicitly use PowerShell's FileSystem provider while the
CMSite drive remains active. The optional Windows integration check
`tests/powershell/Test-SccmFileSystemContext.ps1` exercises real console-provider
context with small file fixtures; run it only on an explicitly selected lab site
server as an SCCM administrator, passing its `-SiteCode` and `-Provider`.
