function value = deterministic_gaussian(sampleIndex,seed,channel)
%DETERMINISTIC_GAUSSIAN Reproducible stateless unit Gaussian sample.

phase1 = (double(sampleIndex)+1)*(double(channel)+1)*12.9898 + ...
    (double(seed)+1)*78.233;
phase2 = (double(sampleIndex)+1)*(double(channel)+3)*39.3467 + ...
    (double(seed)+1)*11.135;
u1 = max(mod(sin(phase1)*43758.5453,1),1e-12);
u2 = mod(sin(phase2)*24634.6345,1);
value = sqrt(-2*log(u1))*cos(2*pi*u2);
end
