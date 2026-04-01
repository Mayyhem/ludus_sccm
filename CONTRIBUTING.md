# Contributing to Ludus SCCM Hierarchy Lab

Thanks for your interest in contributing! This Ansible collection builds a three-tiered SCCM hierarchy for [Ludus](https://ludus.cloud) cloud labs. See the [README](README.md) for full project details.

## Reporting Issues

Please open an issue on [GitHub Issues](https://github.com/Mayyhem/ludus_sccm/issues) and include:

- A description of the problem or unexpected behavior
- Output from `ludus range logs` and `ludus range errors`
- Your `new-config.yml` modifications (if any)
- System resources (CPU cores, RAM, disk space)
- Ludus and Ansible versions

## Submitting Changes

1. Fork the repository and create a branch from `main`
2. Make your changes
3. Test your changes by building and deploying the collection (see below)
4. Open a pull request against `main`

### Development Setup

Build the collection from source:

```
git clone https://github.com/<your-fork>/ludus_sccm
cd ludus_sccm
ansible-galaxy collection build --force
```

Deploy to a Ludus host for testing:

```
scp mayyhem-ludus_sccm-*.tar.gz <username>@<ludus_host>:/<path>
# On the Ludus host:
python3 -m http.server 80
ludus ansible collection add http://<network_ip>/mayyhem-ludus_sccm-<version>.tar.gz
ludus range config set -f new-config.yml
ludus range deploy
```

## Project Structure

| Path | Description |
|------|-------------|
| `roles/` | 14 Ansible roles for site server prep, installation, and configuration |
| `plugins/modules/` | Custom Ansible modules (paired `.py` and `.ps1` files) |
| `new-config.yml` | Ludus lab configuration (VM definitions, networking, role assignments) |
| `galaxy.yml` | Ansible Galaxy collection metadata |
| `.github/workflows/release.yml` | CI/CD pipeline for publishing to Ansible Galaxy |

## Module Development

Custom modules in `plugins/modules/` follow a dual-file convention:

- **`.py` file** - Ansible module wrapper with a required `DOCUMENTATION` string containing module docs, options, examples, and return values
- **`.ps1` file** - PowerShell implementation that performs the actual work on Windows targets

When adding or modifying a module, update both files to keep them in sync.

## Commit Messages

Use imperative mood and keep messages concise. Examples from this repo:

- `Add required README files for galaxy import`
- `Fix ODBC driver version pinning for compatibility`
- `Remove unnecessary dependency for passive site server database`

## License

This project is licensed under [GPL-3.0-or-later](LICENSE). By submitting a contribution, you agree that your changes will be licensed under the same terms.
