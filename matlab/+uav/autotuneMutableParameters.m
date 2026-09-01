function names = autotuneMutableParameters(axisName)
%AUTOTUNEMUTABLEPARAMETERS Exact parameter families saved by AP_AutoTune.
arguments
    axisName (1,1) string
end
switch lower(axisName)
    case "roll"
        prefix = "RLL";
        outer = ["RLL2SRV_TCONST","RLL2SRV_RMAX"];
    case "pitch"
        prefix = "PTCH";
        outer = ["PTCH2SRV_TCONST","PTCH2SRV_RMAX_UP", ...
            "PTCH2SRV_RMAX_DN"];
    otherwise
        names = strings(0,1); return
end
names = [prefix+"_RATE_FF",prefix+"_RATE_P",prefix+"_RATE_I", ...
    prefix+"_RATE_D",prefix+"_RATE_IMAX",prefix+"_RATE_FLTT", ...
    prefix+"_RATE_FLTE",prefix+"_RATE_FLTD",prefix+"_RATE_SMAX",outer]';
end
