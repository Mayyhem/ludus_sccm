# Native SCP component retry

`retry_scp_component_installation.yml` requests one normal restart of the
site component manager after a completed site upgrade leaves a stopped, older
SCP Executive awaiting its next installation retry. The play requires an idle
component manager, no active local update, no bootstrap/installer activity,
healthy remote domain trust and the expected LocalSystem service identities.
The native component manager performs reinstallation; the play then verifies
the target executable build and running service.

Supply an authorized inventory and a JSON/YAML extra-vars file containing
`retry_site_host`, `retry_scp_host`, `retry_site_computer`, `retry_scp_computer`,
`retry_sql_server`, `retry_database`, `retry_package_guid`, and
`retry_target_build`. The site must already have the collection helper at
`C:\ludus\sccm\SccmDeployment.psm1`. Machine-account SQL access and SYSTEM
runas must be available, as in the Ludus installation.

Preview is the default (`retry_preview: true`). Run the same play with
`retry_preview: false` only for the intended native retry. It changes only the
component-manager service state; SQL state, queues, credentials and permissions
are preserved. Verification tolerates a temporarily absent service or executable
during native replacement. A rerun makes no restart when the remote service is
already current and running.

```shell
ansible-playbook -i <authorized-inventory> playbooks/retry_scp_component_installation.yml -e @<variables.json>
```

`retry_secondary_reporting.yml` previews one normal SMS_EXECUTIVE restart after
secondary recovery. It requires an exact computer/UUID, exited setup, the
selected package installed locally, and all three latest initialization groups
at 100%. Apply creates and verifies a new COPY_ONLY backup before the service
restart. It never stops SQL, terminates SQL sessions, or changes identities or
queues. Pass explicit scope variables and `secondary_reporting_preview=false`
only after reviewing the preview; a failed normal stop has no force fallback.
