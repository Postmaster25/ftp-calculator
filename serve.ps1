param(
    [int]$Port = 8123
)

$root = $PSScriptRoot
$prefix = "http://localhost:$Port/"

# If a server is already running here (e.g. a previous window), just open the browser.
$existing = netsh http show servicestate view=requestq 2>$null | Select-String ([regex]::Escape($prefix.ToUpper()))
if ($existing) {
    Write-Host "Already running at $prefix - opening it in your browser."
    Start-Process $prefix
    exit 0
}

$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add($prefix)

try {
    $listener.Start()
} catch {
    Write-Host "Could not start the server on $prefix"
    Write-Host $_.Exception.Message
    Write-Host "If this keeps happening, close any other windows running this script, or run with a different port, e.g.: -Port 8124"
    Read-Host "Press Enter to close"
    exit 1
}

Write-Host "Serving $root"
Write-Host "Open $prefix on this laptop, or from your phone (same Wi-Fi) using this PC's LAN IP instead of 'localhost'."
Write-Host "Leave this window open while you use the app. Close it (or press Ctrl+C) to stop the server."
Start-Process $prefix

$mime = @{
    ".html" = "text/html; charset=utf-8"
    ".js"   = "application/javascript; charset=utf-8"
    ".json" = "application/json; charset=utf-8"
    ".png"  = "image/png"
    ".svg"  = "image/svg+xml"
    ".ico"  = "image/x-icon"
}

try {
    while ($listener.IsListening) {
        $context = $listener.GetContext()
        $req = $context.Request
        $res = $context.Response
        try {
            $path = $req.Url.AbsolutePath.TrimStart("/")
            if ([string]::IsNullOrEmpty($path)) { $path = "index.html" }
            $filePath = Join-Path $root $path

            if (Test-Path $filePath -PathType Leaf) {
                $ext = [System.IO.Path]::GetExtension($filePath)
                $contentType = $mime[$ext]
                if (-not $contentType) { $contentType = "application/octet-stream" }
                $bytes = [System.IO.File]::ReadAllBytes($filePath)
                $res.ContentType = $contentType
                $res.ContentLength64 = $bytes.Length
                $res.OutputStream.Write($bytes, 0, $bytes.Length)
            } else {
                $res.StatusCode = 404
                $msg = [System.Text.Encoding]::UTF8.GetBytes("404 Not Found: $path")
                $res.OutputStream.Write($msg, 0, $msg.Length)
            }
        } catch {
            $res.StatusCode = 500
        } finally {
            $res.OutputStream.Close()
        }
    }
} finally {
    # Ensures Windows releases the port registration even if this window is closed or Ctrl+C is pressed,
    # so the next launch doesn't hit a stale "conflicts with an existing registration" error.
    $listener.Stop()
    $listener.Close()
}
