# Plan an SCCM version

This role prints a read-only version plan. It does not install, upgrade, or
inspect SCCM. Run it once at the intended hierarchy coordinator, with Python
3.8 or newer on the Ansible controller. The existing lab configuration does
not call this role automatically yet.

See [the implementation guide](../../docs/version-selection.md) for the
settings, examples, supported planning choices, limitations, and test commands.
