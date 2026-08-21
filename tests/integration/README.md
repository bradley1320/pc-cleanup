# Integration Tests

Integration tests run in a Windows VM and require administrator privileges.
They are NOT part of CI — run manually before releases.

## Setup

1. Create a Windows 10/11 VM snapshot (clean state)
2. Copy the `dist/` folder into the VM
3. Run tests as Administrator

## Test Checklist

- [x] Full Tune-Up completes without errors
- [x] System Restore Point created
- [x] Registry backup created
- [x] Privacy tweaks apply and undo correctly
- [x] Performance tweaks apply and undo correctly
- [x] QuickClean preview shows correct sizes
- [x] Startup Manager lists programs with publisher info
- [x] Security Check reports correct status
- [x] System Report captures before/after snapshots
- [x] Network Reset displays appropriate warnings
- [x] CLI flags (-Profile, -WhatIf, -Undo) work correctly
