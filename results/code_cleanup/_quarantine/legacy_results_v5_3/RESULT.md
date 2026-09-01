# V5.3 Result

## Environment and scope

V5.3 kept the V5.2 `.slx`/Bus boundary and introduced ArduPilot Native AUTOTUNE at Plane-4.7.0 commit `1511f27194f1dcc3728270883047bdf022b3fd53`. MATLAB supplied RC excitation and analyzed evidence; it did not search PID gains.

Historical frozen-model manifests and DataFlash/interface evidence are retained in `data/`.

## Native AUTOTUNE integration

- Roll and Pitch isolated Native AUTOTUNE integrations produced official completion evidence in V5.3-era runs.
- `AUTOTUNE_AXES` selected one axis per fresh SITL run; Yaw was not enabled because the baseline used `YAW_RATE_ENABLE=0` and the coordinated `YAW2SRV_*` path.
- Exact ATRP/MSG evidence, parameter export and restart read-back were required.

## Mode-gate correction

An early post-tune report classified candidates unsafe while its scoring window was predominantly MANUAL. The root cause was a weak mode check that accepted any later FBWA occurrence. The correction introduced:

- `SITL_READY` based on Heartbeats, continuous FDM/state, alignment and parameter read-back;
- stable requested-mode Heartbeats before commands;
- live dropout monitoring;
- 100% DataFlash mode coverage over the explicit scoring window.

After the correction, saved Native parameters replayed with 100% FBWA coverage. The corrected historical benchmark reported Roll RMSE 1.4488° and Pitch RMSE 4.8263° with safety PASS; Pitch remained a performance warning. The earlier MANUAL-contaminated `FAILED_SAFETY_GATE` conclusion was superseded.

## Remaining result boundary

Baseline and V5.2 custom-candidate revalidation were not completed in the corrected campaign. V5.3 integration success does not override V5.4.1 physical-capability and repeatability requirements.

## Final conclusion

V5.3 proved Native AUTOTUNE integration and established the corrected mode Gate. Current release decisions must use V5.4.1 `RESULT.md`, not isolated V5.3 completion reports.
