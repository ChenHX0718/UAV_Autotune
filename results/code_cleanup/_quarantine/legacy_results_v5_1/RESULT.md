# V5.1 Result

## Environment

- Windows + WSL2 Ubuntu 24.04 LTS
- ArduPlane Plane-4.7.0, commit `1511f27194f1dcc3728270883047bdf022b3fd53`
- build target `sitl/plane`
- MATLAB R2024b
- formal model step 0.005 s; JSON/log step 0.02 s

The historical V5.1 human-readable reports were consolidated into this file; no standalone V5.1 log bundle was present in the audited package. Any absolute paths quoted by old evidence described the original machine and were not treated as current-environment proof.

## Interface and platform acceptance

V5.1 WSL SITL status was **COMPLETE** for its defined scope:

| Item | Result | Key evidence |
|---|---|---|
| source-built WSL SITL | PASS | exact commit and binary identity |
| bidirectional UDP | PASS | zero lost/invalid in formal headless run |
| command mapping | PASS | +5° design → RC1 1625 μs → `ATT.DesRoll≈4.99°` |
| sign tests | PASS | Roll/Pitch command→target→PWM→surface→state |
| parameter read-back | PASS | 101/101 |
| dynamics sanity | PASS | finite state and configured bounds |
| FBWA Roll/Pitch response | PASS | defined baseline/scale tests |
| repeatability | PASS | three runs, recorded metric ranges 0 |
| headless/portability | PASS | Mission Planner closed; active code path portable |

## Important observations

- Standard sequential −5° Roll platform had state-dependent tracking failure, while an independent −5° scale case passed. This was retained rather than hidden by PID changes.
- Mission Planner parameter download increased wall-clock jitter but did not change zero-loss mapping/control; formal batch work therefore keeps Mission Planner closed.
- Reliability was verified through 5× speedup; no claim was made for 10×.

## Final conclusion

V5.1 established the reproducible WSL/SITL and evidence foundation. Its acceptance does not imply later Native AUTOTUNE candidates are safe or complete.
