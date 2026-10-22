# Prepare SCCM supporting software

Installs and verifies the selected supported ODBC driver and Visual C++ runtime.
With `ludus_sccm_prepare_adk: true`, it also replaces incompatible ADK/WinPE
packages. Checks .NET 4.8, logs progress and restarts after installer requests.
Preparation roles call it before SCCM setup or servicing.

See [version selection](../../docs/version-selection.md) and the
[host-test handoff](../../docs/LUDUS_HOST_HANDOFF.md). Vendor installer behavior
still requires live validation.
