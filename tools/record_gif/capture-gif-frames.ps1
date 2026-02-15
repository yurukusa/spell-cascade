# Capture 50 frames at ~200ms intervals (10 seconds of gameplay)
$numFrames = 50
$interval = 200  # milliseconds

# Create output directory
$outDir = "\\wsl.localhost\Ubuntu\tmp\gif-frames"
New-Item -ItemType Directory -Force -Path $outDir | Out-Null

$response = Invoke-RestMethod -Uri "http://localhost:9222/json" -TimeoutSec 5
$wsUrl = ($response | Where-Object { $_.url -like "*localhost:808*" } | Select-Object -First 1).webSocketDebuggerUrl
if (-not $wsUrl) { $wsUrl = $response[0].webSocketDebuggerUrl }

$ws = New-Object System.Net.WebSockets.ClientWebSocket
$ct = [Threading.CancellationToken]::None
$ws.ConnectAsync([Uri]$wsUrl, $ct).Wait()

Write-Output "Connected. Capturing $numFrames frames..."

for ($i = 0; $i -lt $numFrames; $i++) {
    try {
        $msg = '{"id":' + ($i+1) + ',"method":"Page.captureScreenshot","params":{"format":"png","quality":80}}'
        $bytes = [Text.Encoding]::UTF8.GetBytes($msg)
        $segment = [ArraySegment[byte]]::new($bytes)
        $ws.SendAsync($segment, [Net.WebSockets.WebSocketMessageType]::Text, $true, $ct).Wait()

        $buf = New-Object byte[] 10485760
        $result = ""
        do {
            $seg = [ArraySegment[byte]]::new($buf)
            $recv = $ws.ReceiveAsync($seg, $ct).Result
            $result += [Text.Encoding]::UTF8.GetString($buf, 0, $recv.Count)
        } while (-not $recv.EndOfMessage)

        $json = $result | ConvertFrom-Json
        $b64 = $json.result.data
        $framePath = "$outDir\frame_$($i.ToString('D3')).png"
        [IO.File]::WriteAllBytes($framePath, [Convert]::FromBase64String($b64))

        if ($i % 10 -eq 0) { Write-Output "Frame $i captured" }

        Start-Sleep -Milliseconds $interval
    } catch {
        Write-Output "Error on frame $i : $_"
    }
}

$ws.CloseAsync([Net.WebSockets.WebSocketCloseStatus]::NormalClosure, "", $ct).Wait()
Write-Output "Done! $numFrames frames captured to $outDir"
