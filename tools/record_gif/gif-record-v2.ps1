# Phase 1: Click to start the game
$response = Invoke-RestMethod -Uri "http://localhost:9222/json" -TimeoutSec 5
$wsUrl = ($response | Where-Object { $_.url -like "*localhost:808*" } | Select-Object -First 1).webSocketDebuggerUrl
if (-not $wsUrl) { $wsUrl = $response[0].webSocketDebuggerUrl }

$ws = New-Object System.Net.WebSockets.ClientWebSocket
$ct = [Threading.CancellationToken]::None
$ws.ConnectAsync([Uri]$wsUrl, $ct).Wait()

function Send-CDP($ws, $msg) {
    $bytes = [Text.Encoding]::UTF8.GetBytes($msg)
    $segment = [ArraySegment[byte]]::new($bytes)
    $ws.SendAsync($segment, [Net.WebSockets.WebSocketMessageType]::Text, $true, $ct).Wait()
}

function Recv-CDP($ws) {
    $buf = New-Object byte[] 10485760
    $result = ""
    do {
        $seg = [ArraySegment[byte]]::new($buf)
        $recv = $ws.ReceiveAsync($seg, $ct).Result
        $result += [Text.Encoding]::UTF8.GetString($buf, 0, $recv.Count)
    } while (-not $recv.EndOfMessage)
    return $result
}

# Click "Start Game" button
$clickJs = @"
(function() {
    var canvas = document.querySelector('canvas');
    if (!canvas) return 'no canvas';
    var rect = canvas.getBoundingClientRect();
    // Click Start Game button position (center, slightly above middle)
    var cx = rect.width / 2;
    var cy = rect.height * 0.54;
    canvas.dispatchEvent(new MouseEvent('mousedown', {clientX: cx, clientY: cy, bubbles: true}));
    canvas.dispatchEvent(new MouseEvent('mouseup', {clientX: cx, clientY: cy, bubbles: true}));
    canvas.dispatchEvent(new MouseEvent('click', {clientX: cx, clientY: cy, bubbles: true}));
    return 'clicked start at ' + Math.round(cx) + ',' + Math.round(cy);
})()
"@

$escapedJs = $clickJs -replace '"', '\"' -replace "`n", '\n' -replace "`r", ''
Send-CDP $ws "{`"id`":1,`"method`":`"Runtime.evaluate`",`"params`":{`"expression`":`"$escapedJs`"}}"
$r = Recv-CDP $ws
Write-Output "Start click: $($r.Substring(0, [Math]::Min($r.Length, 200)))"

# Wait 2 seconds for game to start
Start-Sleep -Seconds 2

# Setup auto-clicker for upgrades
$autoJs = @"
(function() {
    if (window._ac) clearInterval(window._ac);
    window._ac = setInterval(function() {
        var c = document.querySelector('canvas');
        if (!c) return;
        var r = c.getBoundingClientRect();
        c.dispatchEvent(new MouseEvent('mousedown', {clientX: r.width/2, clientY: r.height*0.37, bubbles: true}));
        c.dispatchEvent(new MouseEvent('mouseup', {clientX: r.width/2, clientY: r.height*0.37, bubbles: true}));
        c.dispatchEvent(new MouseEvent('click', {clientX: r.width/2, clientY: r.height*0.37, bubbles: true}));
    }, 1500);
    setTimeout(function() { clearInterval(window._ac); }, 60000);
    return 'auto-clicker on';
})()
"@

$escapedJs2 = $autoJs -replace '"', '\"' -replace "`n", '\n' -replace "`r", ''
Send-CDP $ws "{`"id`":2,`"method`":`"Runtime.evaluate`",`"params`":{`"expression`":`"$escapedJs2`"}}"
$r = Recv-CDP $ws
Write-Output "Auto-clicker: $($r.Substring(0, [Math]::Min($r.Length, 200)))"

# Wait 15 seconds for gameplay to develop (level-ups, combat)
Write-Output "Waiting 15s for gameplay to develop..."
Start-Sleep -Seconds 15

$ws.CloseAsync([Net.WebSockets.WebSocketCloseStatus]::NormalClosure, "", $ct).Wait()

# Phase 2: Capture frames
Write-Output "Starting frame capture..."

$outDir = "\\wsl.localhost\Ubuntu\tmp\gif-frames-v2"
New-Item -ItemType Directory -Force -Path $outDir | Out-Null

$response2 = Invoke-RestMethod -Uri "http://localhost:9222/json" -TimeoutSec 5
$wsUrl2 = ($response2 | Where-Object { $_.url -like "*localhost:808*" } | Select-Object -First 1).webSocketDebuggerUrl
if (-not $wsUrl2) { $wsUrl2 = $response2[0].webSocketDebuggerUrl }

$ws2 = New-Object System.Net.WebSockets.ClientWebSocket
$ws2.ConnectAsync([Uri]$wsUrl2, $ct).Wait()

for ($i = 0; $i -lt 40; $i++) {
    $msg = '{"id":' + ($i+10) + ',"method":"Page.captureScreenshot","params":{"format":"png"}}'
    Send-CDP $ws2 $msg
    $r = Recv-CDP $ws2

    $json = $r | ConvertFrom-Json
    if ($json.result -and $json.result.data) {
        $framePath = "$outDir\frame_$($i.ToString('D3')).png"
        [IO.File]::WriteAllBytes($framePath, [Convert]::FromBase64String($json.result.data))
    }

    if ($i % 10 -eq 0) { Write-Output "Frame $i captured" }
    Start-Sleep -Milliseconds 250
}

$ws2.CloseAsync([Net.WebSockets.WebSocketCloseStatus]::NormalClosure, "", $ct).Wait()
Write-Output "Done! 40 frames captured"
