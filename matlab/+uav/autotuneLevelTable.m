function tableOut = autotuneLevelTable()
%AUTOTUNELEVELTABLE Plane-4.7.0 commit 1511f271 source-derived mapping.

level = (0:10)';
rollTau = [NaN;1.00;0.90;0.80;0.70;0.60;0.50;0.30;0.20;0.15;0.10];
targetRate = [NaN;20;30;40;50;60;75;90;120;160;210];
pitchTau = 1.5*rollTau;
behavior = repmat("PREDEFINED_DYNAMIC_TARGET",numel(level),1);
behavior(1) = "FIXED_CURRENT_RMAX_TCONST_PID_RETUNE";
source = repmat("CURRENT_SOURCE_CODE",numel(level),1);
commit = repmat("1511f27194f1dcc3728270883047bdf022b3fd53",numel(level),1);
tableOut = table(level,targetRate,rollTau,pitchTau,behavior,source,commit, ...
    'VariableNames',{'Level','TargetRate_deg_s','RollYawTCONST_s', ...
    'PitchTCONST_s','Behavior','DataSource','FirmwareCommit'});
end
