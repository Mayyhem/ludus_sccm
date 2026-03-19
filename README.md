# Ludus SCCM Hierarchy Lab

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
- A second primary site (`PS2`) that can be manually joined to `CAS` to share a hierarchy with `PS1` (I’d like to automate this in the future) with the following site systems:
  - standalone primary site server with co-hosted site database (`PS2-PSS`)
- A second, independent hierarchy (`HI2`) with the following site systems:
  - standalone primary site server with co-hosted site database (`HI2-PSS`)

In `CAS` and `PS1`, each of the site system roles are installed on a system that is remote from the primary site server and other site system roles, allowing each role’s functions and telemetry to be isolated to facilitate research and development. All domain-joined systems (including the ones that serve `HI2`) become SCCM client devices in the PS1 primary site via automatic client push installation.

Installation occurs in roughly the following order:
- All systems are stood up with firewall and Defender disabled and WebClient running
- A domain controller (`DC`) with Active Directory Certificate Services (`ADCS`) is installed
- The primary site server for the CAS primary site (`CAS-PSS`) is added to the local admins group on the other systems in `CAS`
- The primary site server for the `PS1` primary site (`PS1-PSS`) is added to the local admins group on the other systems in `PS1`
- Systems are prepped for site system role installation
- MSSQL is installed on `PS1-DB`, `CAS-DB`, and `PS1-PSV`
- The `CAS-PSS` primary site server is added to the sysadmin MSSQL server role on the the `CAS` site database (`CAS-DB`)
- The `PS1-PSS` primary site server is added to the sysadmin MSSQL server role on the the `PS1` site databases (`PS1-DB`, `PS1-PSV`)
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
- A second primary site (`PS2`) is installed on a standalone primary site server (`PS2-PSS`)
- A second, independent hierarchy (`HI2`) is installed on a standalone primary site server (`HI2-PSS`)

This lab is susceptible to ALL attack techniques and subtechniques detailed in Misconfiguration Manager at the time of this writing with the exception of ELEVATE-4 and ELEVATE-5 (because PKI certs are not required for client authentication in the lab) and TAKEOVER-9 (because I didn’t need to link databases with sysadmin privileges for the collector testing and writing Ansible roles is time consuming).

If you’d like to customize the lab, changes can be made to new-config.yml to add/remove servers and roles and tweak settings.

In the future, I’d like to add a second child primary site of `CAS`, but I haven’t been able to get SCCM's unattended setup script file to respect the `ParentSiteCode` and `ParentSiteServer` options during installation (https://learn.microsoft.com/en-us/intune/configmgr/core/servers/deploy/install/command-line-script-file) and haven’t been able to find any examples online. If you have any ideas for how to accomplish this, please let me know!

## System Requirements

This lab is beefy. I’ve been successful standing it up on my laptop that has 16 CPU cores, 64GB RAM, and 256GB free disk space, but I’ve had the best results with more resources. You may need to reduce the `cpu` and `ram_gb` allocated to each system in `new-config.yml` depending on your available resources.

You can also comment out VMs in the Ludus configuration file that you don’t think you’ll use to consume fewer resources (e.g., PS2-PSS, HI2-PSS, CAS-SCP).

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

## Building the Collection from Source

If you'd prefer to build from source rather than fetch the collection from Ansible Galaxy, run:

```
git clone https://github.com/Mayyhem/ludus_sccm
cd ludus_sccm
ansible-galaxy collection build --force
```

Next, copy the resulting file to the Ludus host, stand up an HTTP server, and add the collection:

```
scp Mayyhem-ludus_sccm-1.0.0.tar.gz <username>@<ludus_host>:/<path>
python3 -m http.server 80
ludus ansible collection add http://<network ip>/Mayyhem-ludus_sccm-1.0.0.tar.gz
```

## Troubleshooting

The majority of range deployment errors can be corrected by executing:

```
ludus power off -n all && sleep 300 && ludus power on -n all && ludus range deploy && ludus range logs -f
```

This will reboot everything and try again.

If you've already passed the initial setup of the VMs and reach deployment of the Ansible roles defined in this project, you can run `ludus range deploy` with the `-t user-defined-roles` option to skip setup.

If that doesn’t work, hit me up with your logs and I’ll do my best to help you resolve the issue:

```
ludus range logs
ludus range errors
```