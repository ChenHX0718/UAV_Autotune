function uav_wind_sfunc(block)
%UAV_WIND_SFUNC Reproducible mean wind plus multi-sine gust.
setup(block);
end

function setup(block)
block.NumDialogPrms = 1;
block.NumInputPorts = 0;
block.NumOutputPorts = 1;
block.OutputPort(1).Dimensions = 3;
block.OutputPort(1).SamplingMode = "Sample";
block.SampleTimes = [0 0];
block.SimStateCompliance = "DefaultSimState";
block.RegBlockMethod("Outputs", @outputs);
end

function outputs(block)
P = block.DialogPrm(1).Data;
gust = zeros(3,1);
if P.env.gust_enable
    gust = P.env.gust_amplitude(:) .* sin(2*pi*P.env.gust_frequency(:) .* ...
        block.CurrentTime + P.env.gust_phase(:));
end
block.OutputPort(1).Data = P.env.wind_ned(:) + gust;
end
