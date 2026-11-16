# Finish the requested SCCM release

Run once on the CAS or standalone primary after every site and remote role has
finished installation. Set `ludus_sccm_sitecode` to that root's code. The sample
configuration already provides the CAS assignment and role dependencies.

The root console is matched to its provider before management cmdlets load.
Each release first updates the parents, then refreshes the console in a separate
PowerShell process before secondary/passive reconciliation. Hotfix console
updates are also applied before final verification. Native restart requests return an incomplete checkpoint before the coordinator
exits. Ansible restarts the identified guest and resumes the same phase.

This role plans from installed versions, services releases/hotfixes, reconciles
secondary/passive servers, updates installed consoles and reachable installed
clients, reloads distributed boot images and writes/fetches completion evidence.
It uses domain-admin runas credentials supplied by Ludus. It may restart SEC
while upgrading its SQL prerequisite. Native site, prerequisite, client and
console restart checkpoints use normal serial guest restarts with identity,
installer-idle and post-boot readiness checks.

Settings include `ludus_sccm_target_version`, `ludus_sccm_install_hotfixes`,
`ludus_sccm_component_hosts`, `ludus_sccm_allow_prerequisite_warnings` (false),
`ludus_sccm_update_timeout_minutes` (180 per wait),
`ludus_sccm_client_timeout_minutes` (90 per client),
`ludus_sccm_catalog_settle_seconds` (120) and
`ludus_sccm_artifacts_directory` (controller report destination; checked before
copying, a folder the Ludus service cannot create only warns, and `''` turns the
copy off).

After completion the role can add lab RBAC and user device affinity, all off by
default. `ludus_sccm_custom_security_roles` copies built-in roles
(`[{name: Custom Role, copy_from: Read-only Analyst}]`).
`ludus_sccm_administrative_users` adds SCCM administrators with every object
and both default collections in scope (`[{user: roanalyst, roles: [Read-only
Analyst], password: ...}]`). An entry with a password creates the domain account
first; without one, the account must already exist. `ludus_sccm_primary_users`
sets primary users of client devices (`[{device: PS1-DEV, user: domainuser}]`).
Bare account names use the lab domain. Each step skips what already exists, only
adds missing roles to an existing administrator and never removes anything, and
fails if the result cannot be read back. The sample sets all three on the CAS so
ConfigManBearPig's integration tests find the admin users, custom role and
primary user they expect.

`ludus_sccm_enable_enhanced_http` defaults to false, preserving existing site
communication settings. The sample enables it: the coordinator uses Microsoft's
`Set-CMSite -UseSmsGeneratedCert $true` independently at each CAS/primary that
needs it. The 2509 cmdlet skips CAS communication writes, so CAS uses the
documented site-control SDK to save only the generated-certificate bit. HTTPS-only sites and already enabled sites remain unchanged. Anonymous
distribution-point access must be disabled first; an active update blocks new
communication changes. Network Access Accounts and client-approval settings are
retained. After reviewing native prerequisite warnings, the explicit warning
option uses the installer's native continue-on-warning flag; both provider and
package states must already show completed prerequisites. Errors still stop.
Native certificate configuration can take up to 30 minutes. See
[Enhanced HTTP](https://learn.microsoft.com/en-us/intune/configmgr/core/plan-design/hierarchy/enhanced-http).

See [the implementation guide](../../docs/version-selection.md) and
[Ludus-host handoff](../../docs/LUDUS_HOST_HANDOFF.md). Assisted 2509 -> 2609
validation passed in the authorized cthompson hierarchy on October 27, 2026,
including components and functional probes. A new clean rebuild of the final
source remains unverified; integrated restart/resume validation is in progress. Existing-lab upgrades remain untested.

Secondary updates use two native paths. A lower release build uses
`Invoke-CMSecondarySiteUpgrade`. At the same build, a native secondary update
status of zero means parent update records are missing; the standard upgrade
cmdlet refuses that equal-build site. After replication initializes, the role
re-reads its status and uses the supported Recover Secondary Site workflow when
still required. It takes and verifies a fresh COPY_ONLY database backup before
one prerequisite-enabled site-control request. SCCM performs the reinstallation
and database reinitialization, retaining secondary configuration and the SQL
instance. The helper never stops or kills SQL, edits installed-package records,
or skips the final native up-to-date check. Its separate preview returns before
backups and provider writes. Existing pending setup/recovery is only observed.

Before same-build recovery, the helper also compares the installed package GUIDs
in both site databases. If the secondary already has every parent package
locally, it waits for native parent reporting and never submits another recovery.

Completion verifies storage summary status and accessibility, and probes each
management point's MP-list endpoint. The default MP AvailabilityState of zero
is not treated as a failure by itself. Client expectations come from the unique
production SMS_ClientBaseline and must match the installation media release;
the MSI product version alone can omit the production client patch revision.
The shared completion task is reusable after independently verified servicing
and hotfix checkpoints.

Client completion requires the expected production version, assigned site,
running CcmExec service and no active CCMSetup. A native return code 7 written
since the last guest boot returns an incomplete restart checkpoint. Native
setup applies only the client patches valid for the installed level, so with a
hotfix rollup plus a later hotfix one run can finish cleanly below the
production version. When the setup service run (not its launcher) has exited
with code 0 after this launch and the client is still lower, completion runs
setup again, at most three runs per client, instead of waiting out the timeout. The normal
deployment restarts that inventory guest, verifies its post-boot state, then
rechecks component versions and readiness before boot-image work.
`playbooks/restart_pending_clients.yml` remains available for separate maintenance.
The coordinator does not overwrite its own loaded helper.

Remote component work sets PowerShell execution policy only at process scope
before loading the copied helper, so reachable Windows clients with Restricted
defaults can run the automation without changing machine or user policy.

Installed-client detection queries SMS_Client and handles only a missing class
or namespace as absence. A management point can run CcmExec from SMS_CCM without
an installed client; that agent service alone never enrolls it in client scope.
Other WMI errors remain failures.

Local component checks reuse the already-loaded helper and preserve the
coordinator log; fresh remote processes initialize their own component log.

Automatic restart settings (shared across SCCM roles):

- `ludus_sccm_automatic_reboots: true`: allow only identified native checkpoints.
  False stops at the checkpoint for owner-managed maintenance.
- `ludus_sccm_max_restart_rounds: 3`: bound restart/resume cycles per phase.
- `ludus_sccm_restart_timeout_seconds: 900`: timeout for each normal guest restart.
- `ludus_sccm_restart_inventory_map: {}`: optional FQDN or lowercase short name
  to inventory-host mapping when VM names differ from `<range_id>-<hostname>`.

Targets must be Windows guests in the current range inventory. Active installers
block a restart. Console MSI 3010 is retained in an automation-owned journal tied
to the guest boot time; no vendor queue or update status is changed. A checkpoint
is never reported as successful completion.
