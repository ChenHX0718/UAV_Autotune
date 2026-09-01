function voltage = battery_terminal_voltage(P, soc, currentA)
%BATTERY_TERMINAL_VOLTAGE Simple SOC/current/temperature pack model.
soc = min(max(double(soc),0),1);
currentA = max(double(currentA),0);
ocvCell = interp1(P.battery.soc_grid, P.battery.ocv_per_cell_V, ...
    soc, "pchip", "extrap");
temperatureDrop = max(P.battery.reference_temperature_C - ...
    P.battery.temperature_C,0);
resistance = P.battery.internal_resistance_ohm * ...
    (1 + P.battery.resistance_temp_coefficient*temperatureDrop);
voltage = P.battery.series_cells*ocvCell - currentA*resistance;
voltage = min(max(voltage,P.battery.min_voltage_V), ...
    P.battery.max_voltage_V);
end
