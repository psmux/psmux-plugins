$ErrorActionPreference = 'SilentlyContinue'
$c = (Get-CimInstance Win32_Processor).LoadPercentage
$o = Get-CimInstance Win32_OperatingSystem
$m = [math]::Round(($o.TotalVisibleMemorySize - $o.FreePhysicalMemory) / 1MB, 1)
$t = [math]::Round($o.TotalVisibleMemorySize / 1MB, 1)
psmux display-message "CPU: ${c}%  |  RAM: ${m}G / ${t}G"
