# Finish the requested SCCM release

Run once on the CAS or standalone primary after every site and remote role has
finished installation. Set `ludus_sccm_sitecode` to that root's code. The sample
configuration already provides the CAS assignment and role dependencies.

This role plans from installed versions, services releases/hotfixes, reconciles
secondary/passive servers, updates installed consoles and reachable installed
clients, reloads distributed boot images and writes/fetches completion evidence.
It uses domain-admin runas credentials supplied by Ludus. It may restart SEC
while upgrading its SQL prerequisite. SCCM site-update restart requests stop for
an owner restart before rerunning.

Settings include `ludus_sccm_target_version`, `ludus_sccm_install_hotfixes`,
`ludus_sccm_component_hosts`, `ludus_sccm_allow_prerequisite_warnings` (false),
`ludus_sccm_update_timeout_minutes` (180 per wait),
`ludus_sccm_client_timeout_minutes` (90 per client),
`ludus_sccm_catalog_settle_seconds` (120) and
`ludus_sccm_artifacts_directory` (controller report destination).

See [the implementation guide](../../docs/version-selection.md) and
[Ludus-host handoff](../../docs/LUDUS_HOST_HANDOFF.md). Offline checks have run;
Linux Ansible and live servicing checks remain pending.
