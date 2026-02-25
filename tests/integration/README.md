# Integration Tests

Integration tests run in a Windows VM and require administrator privileges.
They are NOT part of CI — run manually before releases.

## Setup

1. Create a Windows 10/11 VM snapshot (clean state)
2. Copy the `dist/` folder into the VM
3. Run tests as Administrator

## Test Checklist

- [ ] Full Tune-Up completes without errors
- [ ] System Restore Point created
- [ ] Registry backup created
- [ ] Privacy tweaks apply and undo correctly
- [ ] Performance tweaks apply and undo correctly
- [ ] QuickClean preview shows correct sizes
- [ ] Startup Manager lists programs with publisher info
- [ ] Security Check reports correct status
- [ ] System Report captures before/after snapshots
- [ ] Network Reset displays appropriate warnings
- [ ] CLI flags (-Profile, -WhatIf, -Undo) work correctly
