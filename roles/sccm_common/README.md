# Shared SCCM deployment operations

Internal role used by preparation, installation completion checks and hierarchy
servicing. It resolves the shared release selection, copies the Windows helper
module and supplies a controller download task. Importing the helper does not
change a guest. Individual functions perform the operations chosen by callers.

See [version selection](../../docs/version-selection.md) for settings, code
responsibilities, recovery locations and validation limits.
