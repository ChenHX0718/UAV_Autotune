function [overshootAbsolute,overshootPercent] = calculateStepOvershoot( ...
        desiredBefore,desiredAfter,actualSegment)
%CALCULATESTEPOVERSHOOT Direction-aware overshoot using desired step size.
stepAmplitude = double(desiredAfter)-double(desiredBefore);
if ~isfinite(stepAmplitude) || abs(stepAmplitude) <= eps
    overshootAbsolute = NaN; overshootPercent = NaN; return
end
actualSegment = double(actualSegment(:));
actualSegment = actualSegment(isfinite(actualSegment));
if isempty(actualSegment)
    overshootAbsolute = NaN; overshootPercent = NaN; return
end
directedBeyond = sign(stepAmplitude)*(actualSegment-double(desiredAfter));
overshootAbsolute = max(0,max(directedBeyond));
overshootPercent = 100*overshootAbsolute/abs(stepAmplitude);
end
