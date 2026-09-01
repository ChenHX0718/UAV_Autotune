function A = load_xflr5_aero_data(dataDir)
%LOAD_XFLR5_AERO_DATA Build the aerodynamic parameter structure from the
% exported XFLR5 CSV files supplied with this project.
%
% The derivative model uses the neutral-control point of the primary
% stability configuration. Static table mode uses the fixed-speed viscous
% polars of the same aircraft. Elevator, rudder and differential-aileron
% control derivatives are taken from their dedicated stability cases.

configFile = fullfile(dataDir, "00_model_configurations.csv");
polarFile = fullfile(dataDir, "01_aerodynamic_polars.csv");
derivativeFile = fullfile(dataDir, "02_stability_derivatives_nondimensional.csv");
if ~isfile(configFile) || ~isfile(polarFile) || ~isfile(derivativeFile)
    error("UAV:AeroDataMissing", ...
        "XFLR5 aero-data CSV files are missing from %s", dataDir);
end

C = readtable(configFile, "TextType", "string", ...
    "VariableNamingRule", "preserve");
T = readtable(polarFile, "TextType", "string", ...
    "VariableNamingRule", "preserve");
D = readtable(derivativeFile, "TextType", "string", ...
    "VariableNamingRule", "preserve");

primaryMask = strcmpi(string(C.is_primary), "true") | string(C.is_primary) == "1";
if ~any(primaryMask)
    error("UAV:AeroPrimaryMissing", ...
        "No is_primary=true stability configuration was found.");
end
primaryConfig = C(find(primaryMask, 1), :);
primaryId = string(primaryConfig.config_id);
primaryPlane = string(primaryConfig.plane_name);

Dp = D(string(D.config_id) == primaryId, :);
[~, iNeutral] = min(abs(Dp.control_parameter));
r = Dp(iNeutral, :);

A.source = "XFLR5 exported stability derivatives and polars";
A.primary_config_id = primaryId;
A.reference_alpha = deg2rad(r.alpha_deg);
A.reference_speed = r.speed_m_s;
A.CL_ref = r.CL_trim;
A.CD_ref = r.CD_trim;
A.Cm_ref = r.Cm_trim;

% Static angle derivatives at the neutral-control reference point.
A.CL_alpha = r.CLa;
A.Cm_alpha = r.Cma;
% Convert XFLR5 stability-axis CX_alpha to a local drag slope. This keeps
% derivative mode self-consistent with the same Type-7 operating point.
a0 = A.reference_alpha;
A.CD_alpha = (r.CD_trim*sin(a0) + r.CLa*sin(a0) + ...
    r.CL_trim*cos(a0) - r.CXa) / max(cos(a0), 1e-6);

% Dynamic stability derivatives. XFLR5 uses p*b/(2V), q*c/(2V), r*b/(2V),
% exactly matching uav_aero_sfunc.m.
A.CL_q = r.CLq;
A.Cm_q = r.Cmq;
A.CY_beta = r.CYb;
A.CY_p = r.CYp;
A.CY_r = r.CYr;
A.Cl_beta = r.Clb;
A.Cl_p = r.Clp;
A.Cl_r = r.Clr;
A.Cn_beta = r.Cnb;
A.Cn_p = r.Cnp;
A.Cn_r = r.Cnr;

% Elevator control derivative from the primary 0;1 case. XFLR5 supplies
% CX_delta and CZ_delta in stability axes; convert them to lift/drag.
A.CL_de = sin(a0)*r.CXd - cos(a0)*r.CZd;
A.CD_de = -cos(a0)*r.CXd - sin(a0)*r.CZd;
A.Cm_de = r.Cmd;

% Rudder: dedicated stability case whose aircraft name contains 算方向.
rudderCfg = C(contains(string(C.plane_name), "算方向") & ...
    string(C.polar_type) == "stability", :);
if isempty(rudderCfg)
    error("UAV:AeroRudderCaseMissing", "No rudder stability case was found.");
end
[~, ir] = max(rudderCfg.control_count);
rudderId = string(rudderCfg.config_id(ir));
Dr = D(string(D.config_id) == rudderId, :);
[~, ir0] = min(abs(Dr.control_parameter));
rr = Dr(ir0, :);
A.CY_dr = rr.CYd;
A.Cl_dr = rr.Cld;
A.Cn_dr = rr.Cnd;
A.rudder_config_id = rudderId;

% Differential aileron: dedicated stability case whose aircraft name
% contains 算副翼. control_gains=...;1;-1 maps directly to
% deltaA=(deltaLT-deltaRT)/2 in the plant.
aileronCfg = C(contains(string(C.plane_name), "算副翼") & ...
    string(C.polar_type) == "stability", :);
if isempty(aileronCfg)
    error("UAV:AeroAileronCaseMissing", "No aileron stability case was found.");
end
[~, ia] = max(aileronCfg.control_count);
aileronId = string(aileronCfg.config_id(ia));
Da = D(string(D.config_id) == aileronId, :);
[~, ia0] = min(abs(Da.control_parameter));
ra = Da(ia0, :);
A.CY_da = ra.CYd;
A.Cl_da = ra.Cld;
A.Cn_da = ra.Cnd;
A.aileron_config_id = aileronId;

% There is no independent symmetric left/right-tip sweep in the supplied
% data. Do not invent flaperon lift/pitch derivatives.
A.CL_ds = 0;
A.Cm_ds = 0;

% Keep only a modest generic quadratic control-drag term. It can be replaced
% later by dedicated alpha x control-surface sweeps.
A.CD_ctrl = 0.010;

% Build the static lookup table from fixed-speed, viscous PANEL4 polars of
% the same aircraft. In this data package those are the 12 and 13 m/s cases.
baseMask = string(C.plane_name) == primaryPlane & ...
    string(C.polar_type) == "fixed_speed" & ...
    string(C.analysis_method) == "PANEL4" & ...
    (strcmpi(string(C.viscous), "true") | string(C.viscous) == "1");
baseCfg = C(baseMask, :);
if isempty(baseCfg)
    error("UAV:AeroStaticTableMissing", ...
        "No fixed-speed viscous polar was found for the primary aircraft.");
end
[~, order] = sort(baseCfg.speed_spec_m_s);
baseCfg = baseCfg(order, :);

firstId = string(baseCfg.config_id(1));
firstPolar = T(string(T.config_id) == firstId, :);
[firstAlphaDeg, alphaOrder] = sort(firstPolar.alpha_deg);
alphaGrid = deg2rad(firstAlphaDeg(:)');

nV = height(baseCfg);
nA = numel(alphaGrid);
CLtable = zeros(nV, nA);
CDtable = zeros(nV, nA);
Cmtable = zeros(nV, nA);
speedGrid = zeros(nV, 1);
for k = 1:nV
    id = string(baseCfg.config_id(k));
    Tk = T(string(T.config_id) == id, :);
    [alphaDeg, idx] = sort(Tk.alpha_deg);
    speedGrid(k) = median(Tk.speed_m_s);
    CLtable(k,:) = interp1(deg2rad(alphaDeg), Tk.CL(idx), ...
        alphaGrid, "linear");
    CDtable(k,:) = interp1(deg2rad(alphaDeg), Tk.CD_total(idx), ...
        alphaGrid, "linear");
    Cmtable(k,:) = interp1(deg2rad(alphaDeg), Tk.Cm(idx), ...
        alphaGrid, "linear");
end

A.alpha_grid = alphaGrid;
A.speed_grid = speedGrid;
A.CL_table = CLtable;
A.CD_table = CDtable;
A.Cm_table = Cmtable;
A.table_alpha_min = min(alphaGrid);
A.table_alpha_max = max(alphaGrid);
A.table_speed_min = min(speedGrid);
A.table_speed_max = max(speedGrid);

% Overall protection limits. The lookup itself is clamped to its measured
% range; derivative mode is deliberately kept inside a small-disturbance
% envelope because XFLR5 does not model stall/separation faithfully.
A.alpha_limit = deg2rad(12);
A.beta_limit = deg2rad(15);
end
