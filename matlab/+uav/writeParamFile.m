function writeParamFile(filePath,parameters,options)
%WRITEPARAMFILE Write one independent, deterministic ArduPilot parameter file.
arguments
    filePath (1,1) string
    parameters table
    options.Header (1,1) string = ""
end
folder = fileparts(filePath);
if ~isfolder(folder), mkdir(folder); end
fid = fopen(filePath,"w");
if fid < 0, error("UAVV541:ParameterWrite","Cannot write %s",filePath); end
cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
if strlength(options.Header) > 0
    fprintf(fid,"# %s\n",options.Header);
end
for row = 1:height(parameters)
    fprintf(fid,"%s,%.12g\n",string(parameters.Name(row)), ...
        double(parameters.Value(row)));
end
end
