function feasibility = generateLevelFeasibility()
%GENERATELEVELFEASIBILITY Compare firmware targets to plant limits.
root = uav.projectRoot();
addpath(fullfile(root,"model"),"-begin");
baseDir = fullfile(root,"results","v5_4_1");
roll = readtable(fullfile(baseDir,"physical_control_authority","roll", ...
    "roll_capability_summary.csv"),"TextType","string");
pitch = readtable(fullfile(baseDir,"physical_control_authority","pitch", ...
    "pitch_capability_summary.csv"),"TextType","string");
outDir = fullfile(baseDir,"autotune_level_feasibility");
if ~isfolder(outDir), mkdir(outDir); end

P = uav_config("UAV_A",13);
rollCapability = min(double(roll.p_op_max_deg_s),[],"omitnan");
qUp = min(double(pitch.q_op_max_deg_s(pitch.Direction == "PITCH_UP")), ...
    [],"omitnan");
qDown = min(double(pitch.q_op_max_deg_s(pitch.Direction == "PITCH_DOWN")), ...
    [],"omitnan");
target = [20;30;40;50;60;75;90;120;160;210];
level = (1:10)';
rollRatio = target/rollCapability;
pitchUpRatio = target/qUp; pitchDownRatio = target/qDown;
governingRatio = max([rollRatio,pitchUpRatio,pitchDownRatio],[],2);
classification = strings(10,1);
threshold = P.control_authority.feasibility_thresholds;
for k = 1:10
    if governingRatio(k) <= threshold.comfortable_max
        classification(k) = "COMFORTABLE";
    elseif governingRatio(k) <= threshold.matched_max
        classification(k) = "MATCHED";
    elseif governingRatio(k) <= threshold.boundary_max
        classification(k) = "BOUNDARY";
    else
        classification(k) = "BEYOND_OPERATIONAL_CAPABILITY";
    end
end
ruleSource = repmat("V5.4.1_PROJECT_SCREENING_RULE_NOT_ARDUPILOT",10,1);
feasibility = table(level,target,repmat(rollCapability,10,1),rollRatio, ...
    target,repmat(qUp,10,1),repmat(qDown,10,1),pitchUpRatio, ...
    pitchDownRatio,governingRatio,classification,ruleSource, ...
    'VariableNames',{'Level','RollTarget_deg_s','p_op_max_deg_s', ...
    'RollRatio','PitchTarget_deg_s','q_up_deg_s','q_down_deg_s', ...
    'PitchUpRatio','PitchDownRatio','GoverningRatio','Classification', ...
    'RuleSource'});
writetable(feasibility,fullfile(outDir,"autotune_level_feasibility.csv"));

invalidated = table(["V5.4_ROLL_0p6s_CAPABILITY"; ...
    "V5.4_LEVEL_1_2_3_CONCLUSION"], ...
    ["INVALIDATED_BY_V5_4_1";"INVALIDATED_PENDING_V5_4_1"], ...
    'VariableNames',{'PriorConclusion','Status'});
writetable(invalidated,fullfile(outDir,"invalidated_v54_conclusions.csv"));

% Exact-commit Yaw audit.  This deliberately records source facts instead
% of inventing a Yaw AUTOTUNE_LEVEL target-rate relationship.
sourceCommit = repmat("1511f27194f1dcc3728270883047bdf022b3fd53",4,1);
sourceFile = ["ArduPlane/Attitude.cpp"; ...
    "libraries/APM_Control/AP_YawController.cpp"; ...
    "ArduPlane/Attitude.cpp";"config/autotune/baseline.param"];
finding = ["Plane starts the Yaw autotune hook when the axis mask requests Yaw"; ...
    "The Yaw tuner is allocated only when rate_control_enabled() is true"; ...
    "Coordinated-yaw tuning also requires ACRO_YAW_RATE > 0"; ...
    "The V5.4/V5.4.1 baseline explicitly sets YAW_RATE_ENABLE=0"];
conclusion = ["HOOK_EXISTS";"RATE_CONTROL_REQUIRED"; ...
    "ACRO_YAW_RATE_REQUIRED";"YAW_NATIVE_TUNING_DISABLED_IN_BASELINE"];
yawAudit = table(sourceCommit,sourceFile,finding,conclusion, ...
    'VariableNames',{'Commit','Source','Finding','Conclusion'});
writetable(yawAudit,fullfile(outDir,"yaw_autotune_source_audit.csv"));

fig = figure("Visible","off","Color","w");
plot(level,target,"-o","LineWidth",1.3,"DisplayName","Roll target"); hold on;
yline(rollCapability,"--","LineWidth",1.3,"DisplayName","Worst-case p op max");
grid on; xlabel("AUTOTUNE LEVEL"); ylabel("Roll rate (deg/s)"); legend("Location","best");
exportgraphics(fig,fullfile(outDir,"AUTOTUNE_Roll_Target_vs_p_op_max.png"), ...
    "Resolution",160); close(fig);

fig = figure("Visible","off","Color","w");
plot(level,target,"-o","LineWidth",1.3,"DisplayName","Pitch target"); hold on;
yline(qUp,"--","LineWidth",1.3,"DisplayName","Worst-case q up");
yline(qDown,":","LineWidth",1.5,"DisplayName","Worst-case q down");
grid on; xlabel("AUTOTUNE LEVEL"); ylabel("Pitch rate (deg/s)"); legend("Location","best");
exportgraphics(fig,fullfile(outDir,"AUTOTUNE_Pitch_Target_vs_q_op_max.png"), ...
    "Resolution",160); close(fig);
disp(feasibility);
end
