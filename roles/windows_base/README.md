This role is part of https://github.com/Mayyhem/ludus_sccm adapted from https://github.com/Synzack/ludus_sccm

Optional OS servicing uses `ludus_sccm_windows_update_accept_list`, an empty list
by default. Supply exact KB identifiers to install only those security updates
from Microsoft Windows Update, including required normal reboots. This runs
outside the base-role completion marker so existing guests can be serviced.
Ansible check mode searches without installing or rebooting. Other update
categories and unlisted KBs are excluded; Configuration Manager servicing still
uses `service_hierarchy`.
