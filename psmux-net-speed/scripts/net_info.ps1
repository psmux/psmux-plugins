$ErrorActionPreference = 'SilentlyContinue'
$adapters = Get-NetAdapter -Physical | Where-Object { $_.Status -eq 'Up' }
if ($adapters) {
    $name = $adapters[0].Name
    $speed = $adapters[0].LinkSpeed
    $stats = Get-NetAdapterStatistics -Name $name
    $rx = [math]::Round($stats.ReceivedBytes / 1MB, 1)
    $tx = [math]::Round($stats.SentBytes / 1MB, 1)
    psmux display-message "Net: $name ($speed) | RX: ${rx}MB | TX: ${tx}MB"
} else {
    psmux display-message "No active network adapter found"
}
