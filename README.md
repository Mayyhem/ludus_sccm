# Ludus SCCM Hierarchy Lab

## Choose the SCCM release

The [full upgrade plan](UPGRADE_PLAN.md) covers selectable SCCM releases,
automatic selection of the newest broadly available release, an additional
hotfix switch, and complete hierarchy/client verification.

The deployment roles now accept a release selection and an additional hotfix
switch. Edit these shared values on the first VM in `new-config.yml`; the other
VMs inherit them through its YAML anchor:

```yaml
ludus_sccm_target_version: "latest"  # Or "2403", "2409", "2503", "2509", "2603", "2609"
ludus_sccm_install_hotfixes: true
ludus_sccm_enable_enhanced_http: true
```

`latest` discovers Microsoft's newest globally available current-branch release
and excludes early releases. An explicit release stops there. False skips
additional hotfixes and never removes existing or bundled fixes. New releases
with unreviewed requirements stop clearly until support is added. An existing
site is serviced through supported updates; selecting an older release requires
a fresh lab.

The sample enables Enhanced HTTP separately at CAS and each primary using
Configuration Manager generated certificates. The role default preserves existing
settings (`ludus_sccm_enable_enhanced_http: false`); enable the option when the
target release requires HTTPS or Enhanced HTTP and the lab has no PKI deployment.
CAS uses the documented site-control SDK because the 2509 cmdlet skips CAS
communication writes. It retains the Network Access Account and client-approval settings. Anonymous DP
access must already be disabled. Allow up to 30 minutes for native certificate
configuration before evaluating management-point readiness. See Microsoft's
[Enhanced HTTP documentation](https://learn.microsoft.com/en-us/intune/configmgr/core/plan-design/hierarchy/enhanced-http).

The final role updates the hierarchy, applicable registered fixes, installed
consoles and reachable installed clients, then verifies readiness and distributed
boot images. It writes `C:\ludus\sccm\deployment-report.json` on CAS-PSS and
fetches logs/reports to `/opt/ludus/resources/sccm/reports/<range_id>/`.

**Assisted host validation passed on October 27, 2026:** the isolated cthompson
range completed baseline 2509 through 2609, including hierarchy, passive server,
12 installed clients, two consoles and the deployed boot image. MP, TFTP and fresh
inventory probes passed. A clean rebuild using the final source remains unverified;
Native client, console, site-update and Windows prerequisite restart checkpoints
now use bounded serial Ansible restarts and resume the interrupted phase; clean
end-to-end validation is in progress.
Existing research-lab upgrades remain untested. Build
this source rather than installing the published Galaxy collection to test
these unmerged changes. The sample config pins OS cumulative updates on PSS and
LIB before SCCM setup: the old Server 2022 image produced native remote-library
sharing errors that cleared after updating both SMB endpoints. Optional OS
servicing is documented in [the Windows base role](roles/windows_base/README.md).
Use the [Ludus-host agent handoff](docs/LUDUS_HOST_HANDOFF.md) for exact build,
installation, test, recovery, and failure-investigation instructions.

See [version selection and testing](docs/version-selection.md) for copyable
mayyhem.com examples, the optional Ansible role, planning choices, test evidence,
and validation limits. Keep its component-host list current if you rename VMs.

This project builds on Zach Stein's ([@synzack21](https://x.com/synzack21)) and [Erik Hunstad](https://github.com/kernel-sanders)'s excellent [Ludus](https://ludus.cloud) SCCM project (https://github.com/Synzack/ludus_sccm) to expand the standalone primary site (`PS1`) to a parent central administration site (`CAS`) and child secondary site (`SEC`), resulting in a three-tiered SCCM hierarchy.

## Ludus

To install Ludus, follow the instructions at https://docs.ludus.cloud/docs/intro/.

## Lab Systems

The SCCM environment contains:
- A domain controller (`DC`)
- A central administration site (`CAS`) with the following site system roles:
- site database (`CAS-DB`)
- service connection point (`CAS-SCP`)
- A child primary site (`PS1`) under `CAS` with the following site system roles installed on separate systems:
  - site database (`PS1-DB`)
  - SMS Provider (`PS1-SMS`)
  - management point (`PS1-MP`)
  - distribution point (`PS1-DP`)
  - content library (`PS1-LIB`)
  - passive site server (`PS1-PSV`)
  - development workstation (`PS1-DEV`)
- A child secondary site (`SEC`) under `PS1` with a secondary site server (`PS1-SEC`) hosting the management point and distribution point site system roles

In `CAS` and `PS1`, each of the site system roles are installed on a system that is remote from the primary site server and other site system roles, allowing each role’s functions and telemetry to be isolated to facilitate research and development. All domain-joined systems become SCCM client devices in the `PS1` primary site via automatic client push installation.

Installation occurs in roughly the following order:
- All systems are stood up with firewall and Defender disabled and WebClient running
- A domain controller (`DC`) with Active Directory Certificate Services (`ADCS`) is installed
- The primary site server for the CAS primary site (`CAS-PSS`) is added to the local admins group on the other systems in `CAS`
- The primary site server for the `PS1` primary site (`PS1-PSS`) is added to the local admins group on the other systems in `PS1`
- Systems are prepped for site system role installation
- MSSQL is installed on `PS1-DB` and `CAS-DB`
- The `CAS-PSS` primary site server is added to the sysadmin MSSQL server role in the the `CAS` site database (`CAS-DB`)
- The `PS1-PSS` primary site server is added to the sysadmin MSSQL server role in the the `PS1` site database (`PS1-DB`)
- The `PS1` primary site is installed on `PS1-PSS` with:
  - a network access account
  - Active Directory system/user/group discovery
  - automatic site assignment and site-wide client push installation
  - a PXE-enabled distribution point
- The `PS1` primary site is extended to a parent central administration site (`CAS`)
- The content library is moved from `PS1-PSS` to `PS1-LIB` to support a passive site
- The passive site server for `PS1` (`PS1-PSV`) is added to the local admins group on relevant systems
- The passive site server is installed for `PS1`
- A child secondary site is installed under `PS1` (`SEC`)
- After the hierarchy is serviced and its clients verified, the CAS adds collector-testing RBAC and user device affinity:
  - a custom security role (`Custom Role`, a copy of Read-only Analyst)
  - `networkaccess` as a Full Administrator and a new `roanalyst` account as a Read-only Analyst
  - `domainuser` as the primary user of `PS1-DEV`

This lab is susceptible to ALL attack techniques and subtechniques detailed in Misconfiguration Manager at the time of this writing with the exception of ELEVATE-4 and ELEVATE-5 (because PKI certs are not required for client authentication in the lab) and TAKEOVER-9 (because I didn’t need to link databases with sysadmin privileges for the collector testing and writing Ansible roles is time consuming).

If you’d like to customize the lab, changes can be made to new-config.yml to add/remove servers and roles and tweak settings.

In the future, I’d like to add a second child primary site of `CAS`, but I haven’t been able to get SCCM's unattended setup script file to respect the `ParentSiteCode` and `ParentSiteServer` options during installation (https://learn.microsoft.com/en-us/intune/configmgr/core/servers/deploy/install/command-line-script-file) and haven’t been able to find any examples online. If you have any ideas for how to accomplish this, please let me know!

## System Requirements

This lab is beefy. I’ve been successful standing it up on my laptop that has 16 CPU cores, 64GB RAM, and 256GB free disk space, but I’ve had the best results with more resources. You may need to reduce the `cpu` and `ram_gb` allocated to each system in `new-config.yml` depending on your available resources.

You can also comment out VMs in the Ludus configuration file that you don’t think you’ll use to consume fewer resources (e.g., `CAS-SCP`).

Due to unknown issues with SCCM, *.local* domain suffixes will not work properly. Zach and Erik recommended using something else such as *.domain* or *.lab* for your domain suffix.

NetBIOS names must be 15 characters or less in Active Directory.

## Setup and Deployment

To deploy the lab via [Ansible Galaxy](https://galaxy.ansible.com/ui/repo/published/mayyhem/ludus_sccm/), clone the repository to a system where Ludus CLI is installed, then run:

```
ludus ansible collection add mayyhem.ludus_sccm
```

Next, set the configuration file for the range and deploy it:

```
ludus range config set -f new-config.yml
ludus range deploy
```

PXE setup can download its Windows ISO directly on the site server. Set
`ludus_sccm_pxe_iso_url` and `ludus_sccm_pxe_iso_checksum` (the exact SHA-256)
in that VM's `role_vars`. The role verifies the download and reuses a matching
file on subsequent runs. With no URL, it retains the controller ISO source
configured by `ludus_iso_path` and `ludus_sccm_pxe_iso_filename`. Changing the ISO
after an OS image is cached requires updating that image through Configuration
Manager; the role stops instead of silently reusing the old WIM.

## Building the Collection from Source

If you'd prefer to build from source rather than fetch the collection from Ansible Galaxy, run:

```
git clone https://github.com/Mayyhem/ludus_sccm
cd ludus_sccm
ansible-galaxy collection build --force
```

Build on the Ludus host, serve the artifact in one terminal, and install it in
another terminal on that host. Use `--force` because this working copy retains
collection version 1.0.6:

```
# First terminal, from the repository containing the built archive:
python3 -m http.server 8000 --bind 127.0.0.1
# Second terminal on the Ludus host:
ludus ansible collection add --force http://127.0.0.1:8000/mayyhem-ludus_sccm-1.0.6.tar.gz
ludus range config set -f new-config.yml
# Start this only in the range chosen for your deployment test:
ludus range deploy
```

## Troubleshooting

The majority of range deployment errors can be corrected by executing:

```
ludus power off -n all && sleep 300 && ludus power on -n all && sleep 300 && ludus range deploy && ludus range logs -f
```

This will reboot everything and try again.

If you've already passed the initial setup of the VMs and reach deployment of the Ansible roles defined in this project, you can run `ludus range deploy` with the `-t user-defined-roles` option to skip setup.

### A VM fails Ludus's Sysprep step

Ludus runs Sysprep on each cloned VM so every machine gets its own identity.
Windows 11 Sysprep occasionally fails when a built-in Store app (for example
`Microsoft.WidgetsPlatformRuntime`) updates itself for one user. The error says
"Sysprep failed!" and names the package. Ludus may already remove the package and
retry; if Sysprep still fails, that VM is left out of the rest of the deploy and
the final SCCM step stops because the machine is unreachable. Other VMs keep
their progress. To recover without a teardown:

```
ludus range deploy --limit <range_id>-ps1-dev
ludus range deploy -t user-defined-roles --limit <range_id>-cas-pss --only-roles mayyhem.ludus_sccm.service_hierarchy
```

The first command re-runs Sysprep, domain join and that VM's own roles. The
second re-runs the final SCCM step on the CAS, which installs the client and
verifies the whole hierarchy. Use the failed VM's name in place of `ps1-dev`.
Keep Sysprep enabled on servers: without it clones share the template's
machine identity, which collides with the domain's identity and breaks software
update reporting.

### Report copy

At the end, the final SCCM step copies its logs and `deployment-report.json` to
`ludus_sccm_artifacts_directory` on the Ludus host. If the Ludus service cannot
create that folder, the step prints one warning and the deploy continues; the
reports stay in `C:\ludus\sccm` on the CAS. Set the variable to `''` to turn
the copy off.

If that doesn’t work, try tearing it down and rebuilding. If that doesn't work either, pleasehit me up with your logs and I’ll do my best to help you resolve the issue:

```
ludus range logs
ludus range errors
```
