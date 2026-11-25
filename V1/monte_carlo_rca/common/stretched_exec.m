function exec = stretched_exec(execTime, queueCount, delta, nomCap)
% STRETCHED_EXEC  Execution time once queueCount exceeds nominal capacity.
exec = execTime;
if queueCount > nomCap && delta > 0
    exec = execTime / delta;
end
end
