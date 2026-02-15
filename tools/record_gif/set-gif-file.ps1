$response = Invoke-RestMethod -Uri "http://localhost:9222/json" -TimeoutSec 5
$wsUrl = ($response | Where-Object { $_.url -like "*itch.io*edit*" } | Select-Object -First 1).webSocketDebuggerUrl
if (-not $wsUrl) { $wsUrl = ($response | Where-Object { $_.url -like "*itch.io*" } | Select-Object -First 1).webSocketDebuggerUrl }

$ws = New-Object System.Net.WebSockets.ClientWebSocket
$ct = [Threading.CancellationToken]::None
$ws.ConnectAsync([Uri]$wsUrl, $ct).Wait()

function Send-CDP($msg) {
    $bytes = [Text.Encoding]::UTF8.GetBytes($msg)
    $segment = [ArraySegment[byte]]::new($bytes)
    $ws.SendAsync($segment, [Net.WebSockets.WebSocketMessageType]::Text, $true, $ct).Wait()
}

function Recv-CDP {
    $buf = New-Object byte[] 1048576
    $result = ""
    do {
        $seg = [ArraySegment[byte]]::new($buf)
        $recv = $ws.ReceiveAsync($seg, $ct).Result
        $result += [Text.Encoding]::UTF8.GetString($buf, 0, $recv.Count)
    } while (-not $recv.EndOfMessage)
    return $result
}

# Get document
Send-CDP '{"id":1,"method":"DOM.getDocument","params":{"depth":-1}}'
$r = Recv-CDP
Write-Output "Got document"

# Find the file input
Send-CDP '{"id":2,"method":"DOM.querySelector","params":{"nodeId":1,"selector":"input.pick_files_input[type=file]"}}'
$r = Recv-CDP
Write-Output "querySelector result: $($r.Substring(0, [Math]::Min($r.Length, 200)))"

$json = $r | ConvertFrom-Json
$nodeId = $json.result.nodeId
Write-Output "Node ID: $nodeId"

if ($nodeId -gt 0) {
    $filePath = "\\\\wsl.localhost\\Ubuntu\\home\\namakusa\\projects\\spell-cascade\\marketing\\gameplay.gif"
    Send-CDP "{`"id`":3,`"method`":`"DOM.setFileInputFiles`",`"params`":{`"nodeId`":$nodeId,`"files`":[`"$filePath`"]}}"
    $r = Recv-CDP
    Write-Output "SetFile result: $($r.Substring(0, [Math]::Min($r.Length, 300)))"
} else {
    Write-Output "ERROR: Could not find file input node"
}

Start-Sleep -Seconds 5

# Check upload state
$checkJs = '(function(){var sl=document.querySelector(".screenshot_list");return sl?sl.innerHTML.substring(0,500):"NOT FOUND";})()'
$escapedJs = $checkJs -replace '"', '\"'
Send-CDP "{`"id`":4,`"method`":`"Runtime.evaluate`",`"params`":{`"expression`":`"$escapedJs`"}}"
$r = Recv-CDP
Write-Output "Screenshot state: $($r.Substring(0, [Math]::Min($r.Length, 500)))"

try { $ws.CloseAsync([Net.WebSockets.WebSocketCloseStatus]::NormalClosure, "", $ct).Wait() } catch {}
