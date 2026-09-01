# V5.2 Result

## Architecture

V5.2 separated interface correctness from control performance and introduced five executable Bus contracts: `RCCommandBus`, `ActuatorCommandBus`, `SurfaceStateBus`, `TruthStateBus` and `SensorBus`.

The bridge transports raw servo PWM; `uav_actuator_sfunc` owns the sole PWM-to-physical conversion. This removed the earlier hidden normalize/round-trip behavior.

## Interface acceptance

Platform/interface and headless operation were **PASS** for the formal V5.2 suite:

| Check | Result | Historical observation |
|---|---|---|
| WSL SITL/DataFlash | PASS | exact Plane 4.7.0 commit |
| RC transport/value | PASS | sent RC1 vs RCIN max error 0 μs |
| FBWA mapping | PASS | ±5° design mapping max error 0.01° |
| ArduPilot target trace | PASS | `ATT.DesRoll` present |
| Servo transport | PASS | raw packet vs RCOU within asynchronous tolerance |
| Actuator mapping | PASS | unique PWM→physical mapping |
| Truth feedback/time sync | PASS | monotonic 0.02 s JSON time |
| Packet continuity | PASS | formal traces had zero drop/invalid |
| Parameter read-back | PASS | 101/101 |
| Headless | PASS | no Mission Planner dependency |

## Roll candidate foundation

The legacy three-candidate Roll search changed only `RLL_RATE_P/I/D/FF` and `RLL2SRV_TCONST`, with legal/read-back/interface gates and a transparent five-component score. It selected `candidate_fast` with a small objective improvement, but the result remained labelled **UNTUNED / infrastructure proof**, not a flight-ready baseline.

Machine-readable root copies from the old workflow are retained in `data/`; old per-run artifacts were not present in this delivery and are not reconstructed.

## Final conclusion

V5.2 is the accepted interface-contract foundation reused by later versions. Its MATLAB candidate experiment must not be confused with ArduPilot Native AUTOTUNE.
