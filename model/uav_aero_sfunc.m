function uav_aero_sfunc(block)
%UAV_AERO_SFUNC Parameterized nonlinear aerodynamic forces and moments.
setup(block);
end

function setup(block)
block.NumDialogPrms = 1;
block.NumInputPorts = 6;
block.NumOutputPorts = 3;
for k = 1:3
    block.InputPort(k).Dimensions = 3;
end
block.InputPort(4).Dimensions = 5;
block.InputPort(5).Dimensions = 1;
block.InputPort(6).Dimensions = 3;
for k = 1:6
    block.InputPort(k).DirectFeedthrough = true;
end
block.OutputPort(1).Dimensions = 3;
block.OutputPort(2).Dimensions = 3;
block.OutputPort(3).Dimensions = 3;
block.SampleTimes = [0 0];
block.SimStateCompliance = "DefaultSimState";
block.RegBlockMethod("Outputs", @outputs);
end

function outputs(block)
P = block.DialogPrm(1).Data;
velocityBody = block.InputPort(1).Data;
rates = block.InputPort(2).Data;
euler = block.InputPort(3).Data;
actuator = block.InputPort(4).Data;
rho = max(block.InputPort(5).Data, 0.1);
windNed = block.InputPort(6).Data;

windBody = rotationNedToBody(euler) * windNed;
airVelocity = velocityBody - windBody;
Va = max(norm(airVelocity), 0.5);
alphaRaw = atan2(airVelocity(3), airVelocity(1));
betaRaw = asin(min(max(airVelocity(2)/Va, -1), 1));
alpha = min(max(alphaRaw, -P.aero.alpha_limit), P.aero.alpha_limit);
beta = min(max(betaRaw, -P.aero.beta_limit), P.aero.beta_limit);

deltaLT = actuator(2);
deltaRT = actuator(3);
deltaE = actuator(4);
deltaR = actuator(5);
deltaA = 0.5 * (deltaLT - deltaRT);
deltaS = 0.5 * (deltaLT + deltaRT);

pHat = rates(1) * P.geometry.span / (2*Va);
qHat = rates(2) * P.geometry.chord / (2*Va);
rHat = rates(3) * P.geometry.span / (2*Va);

[CLBase, CDBase, CmBase] = staticAeroCoefficients(P, alpha, Va);

% Static alpha dependence comes from either the local derivative model or
% the lookup table. Dynamic-rate and control increments always use the
% dedicated Type-7 stability/control derivatives.
CL = CLBase + P.aero.CL_q*qHat + P.aero.CL_de*deltaE + ...
    P.aero.CL_ds*deltaS;
CD = CDBase + P.aero.CD_de*deltaE + P.aero.CD_ctrl * ...
    (deltaA^2 + deltaS^2 + deltaE^2 + deltaR^2);
CY = P.aero.CY_beta*beta + P.aero.CY_p*pHat + ...
    P.aero.CY_r*rHat + P.aero.CY_da*deltaA + P.aero.CY_dr*deltaR;
Cl = P.aero.Cl_beta*beta + P.aero.Cl_p*pHat + ...
    P.aero.Cl_r*rHat + P.aero.Cl_da*deltaA + P.aero.Cl_dr*deltaR;
Cm = CmBase + P.aero.Cm_q*qHat + P.aero.Cm_de*deltaE + ...
    P.aero.Cm_ds*deltaS;
Cn = P.aero.Cn_beta*beta + P.aero.Cn_p*pHat + ...
    P.aero.Cn_r*rHat + P.aero.Cn_da*deltaA + P.aero.Cn_dr*deltaR;

qbar = 0.5 * rho * Va^2;
lift = qbar * P.geometry.area * CL;
drag = qbar * P.geometry.area * max(CD, 0.003);
side = qbar * P.geometry.area * CY;
forceBody = [-drag*cos(alpha) + lift*sin(alpha); side; ...
    -drag*sin(alpha) - lift*cos(alpha)];
momentAtReference = qbar * P.geometry.area * ...
    [P.geometry.span*Cl; P.geometry.chord*Cm; P.geometry.span*Cn];

% XFLR5 coefficients are referenced to the CG used during the aerodynamic
% analysis. The 6DOF equations and supplied inertia are about the current CG.
% Translate only when the current CG is changed (payload/battery movement):
% M_cg = M_ref - r(ref->cg) x F. With the supplied CG the offset is zero,
% avoiding the common mistake of applying the CG correction twice.
rReferenceToCg = P.geometry.cg_body(:) - ...
    P.aero.moment_reference_body(:);
momentBody = momentAtReference - cross(rReferenceToCg,forceBody);

block.OutputPort(1).Data = forceBody;
block.OutputPort(2).Data = momentBody;
block.OutputPort(3).Data = [alphaRaw; betaRaw; Va];
end

function [CL, CD, Cm] = staticAeroCoefficients(P, alpha, Va)
if strcmpi(P.aero.mode, "table")
    % Never extrapolate XFLR5 tables beyond the supplied alpha/speed range.
    a = min(max(alpha, P.aero.table_alpha_min), P.aero.table_alpha_max);
    v = min(max(Va, P.aero.table_speed_min), P.aero.table_speed_max);
    nV = numel(P.aero.speed_grid);
    clv = zeros(nV,1); cdv = zeros(nV,1); cmv = zeros(nV,1);
    for k = 1:nV
        clv(k) = interp1(P.aero.alpha_grid, P.aero.CL_table(k,:), a, "linear");
        cdv(k) = interp1(P.aero.alpha_grid, P.aero.CD_table(k,:), a, "linear");
        cmv(k) = interp1(P.aero.alpha_grid, P.aero.Cm_table(k,:), a, "linear");
    end
    if nV == 1
        CL = clv(1); CD = cdv(1); Cm = cmv(1);
    else
        CL = interp1(P.aero.speed_grid, clv, v, "linear");
        CD = interp1(P.aero.speed_grid, cdv, v, "linear");
        Cm = interp1(P.aero.speed_grid, cmv, v, "linear");
    end
else
    da = alpha - P.aero.reference_alpha;
    CL = P.aero.CL_ref + P.aero.CL_alpha*da;
    CD = P.aero.CD_ref + P.aero.CD_alpha*da;
    Cm = P.aero.Cm_ref + P.aero.Cm_alpha*da;
end
end

function C = rotationNedToBody(euler)
phi = euler(1); theta = euler(2); psi = euler(3);
cPhi = cos(phi); sPhi = sin(phi);
cTheta = cos(theta); sTheta = sin(theta);
cPsi = cos(psi); sPsi = sin(psi);
C = [cTheta*cPsi, cTheta*sPsi, -sTheta; ...
    sPhi*sTheta*cPsi-cPhi*sPsi, sPhi*sTheta*sPsi+cPhi*cPsi, sPhi*cTheta; ...
    cPhi*sTheta*cPsi+sPhi*sPsi, cPhi*sTheta*sPsi-sPhi*cPsi, cPhi*cTheta];
end
