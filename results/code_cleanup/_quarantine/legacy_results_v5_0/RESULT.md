# V5.0 Result

## Environment and scope

V5.0 was the pre-WSL/interface-audit baseline. Its purpose in the current package is historical: it explains why later versions strengthened command semantics, parameter identity and acceptance gates.

## Interface and control result

- The main smoke criterion was approximately roll motion >0.3° plus PWM variation >0.5 μs with no simulation exception.
- It did not require external target versus ArduPlane internal target, parameter read-back, packet integrity, sign, overshoot, settling or saturation to pass.
- A nominal 5° external command could produce an internal target above 20° because desired attitude and RC-stick semantics were mixed.

## Problems found

- “Aircraft moved” could be accepted without proving command scale.
- Windows executable and absolute-path assumptions limited portability.
- Firmware/parameter identity and DataFlash evidence were insufficiently strict.

## Final conclusion

V5.0 is not an accepted current baseline. Its key legacy is the decision to move to exact-commit WSL SITL, explicit RC semantics and layered evidence gates.
