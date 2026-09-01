function channels = servo_channels(P)
%SERVO_CHANNELS Return ordered V5.4.1 servo configuration structures.

channels = {P.servo.throttle,P.servo.aileron_left, ...
    P.servo.aileron_right,P.servo.elevator,P.servo.rudder};
end
