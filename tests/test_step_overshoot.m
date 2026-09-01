function results = test_step_overshoot()
%TEST_STEP_OVERSHOOT Deterministic regression cases for step overshoot.
root = fileparts(fileparts(mfilename("fullpath")));
outDir = fullfile(root,"results","v5_4_1","validation","overshoot");
if ~isfolder(outDir), mkdir(outDir); end

name = ["POSITIVE_0_TO_10";"NEGATIVE_0_TO_MINUS10";"NO_OVERSHOOT"];
desiredBefore = [0;0;-5]; desiredAfter = [10;-10;5];
peak = [12;-12;4.8]; expectedPercent = [20;20;0];
overshootAbsolute = zeros(3,1); overshootPercent = zeros(3,1);
for k = 1:3
    segment = [desiredBefore(k);desiredAfter(k);peak(k)];
    [overshootAbsolute(k),overshootPercent(k)] = ...
        uav.calculateStepOvershoot(desiredBefore(k),desiredAfter(k),segment);
end
pass = abs(overshootPercent-expectedPercent) < 1e-12;
results = table(name,desiredBefore,desiredAfter,peak,overshootAbsolute, ...
    overshootPercent,expectedPercent,pass, ...
    'VariableNames',{'Case','DesiredBefore','DesiredAfter','ActualPeak', ...
    'OvershootAbsolute','OvershootPercent','ExpectedPercent','Pass'});
writetable(results,fullfile(outDir,"overshoot_standard_signal_validation.csv"));

fig = figure("Visible","off","Color","w");
bar(categorical(name),[overshootPercent,expectedPercent]); grid on;
ylabel("Overshoot (%)"); legend("Calculated","Expected","Location","best");
exportgraphics(fig,fullfile(outDir,"overshoot_standard_signal_validation.png"), ...
    "Resolution",160); close(fig);
assert(all(pass),"UAVV541:OvershootRegression","Overshoot regression failed.");
disp(results);
end
