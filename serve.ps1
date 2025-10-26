$prefix = "http://localhost:5500/"
$root = (Get-Location).Path
$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add($prefix)
$listener.Start()
Write-Host "Serving $root at $prefix"

function Get-ContentType($path) {
  switch -regex ($path) {
    '\.html$' { return 'text/html' }
    '\.htm$' { return 'text/html' }
    '\.css$' { return 'text/css' }
    '\.js$' { return 'application/javascript' }
    '\.json$' { return 'application/json' }
    '\.png$' { return 'image/png' }
    '\.jpg$' { return 'image/jpeg' }
    '\.jpeg$' { return 'image/jpeg' }
    '\.gif$' { return 'image/gif' }
    '\.svg$' { return 'image/svg+xml' }
    '\.ico$' { return 'image/x-icon' }
    '\.mp3$' { return 'audio/mpeg' }
    default { return 'application/octet-stream' }
  }
}

while ($true) {
  try {
    $ctx = $listener.GetContext()
    $rel = $ctx.Request.Url.AbsolutePath.TrimStart('/')
    if ([string]::IsNullOrEmpty($rel)) { $rel = 'index.html' }
    $path = Join-Path $root $rel

    if (Test-Path $path -PathType Leaf) {
      $bytes = [System.IO.File]::ReadAllBytes($path)
      $ctx.Response.ContentType = Get-ContentType $path
      $ctx.Response.ContentLength64 = $bytes.Length
      $ctx.Response.OutputStream.Write($bytes, 0, $bytes.Length)
      $ctx.Response.OutputStream.Close()
    } else {
      $ctx.Response.StatusCode = 404
      $writer = New-Object System.IO.StreamWriter($ctx.Response.OutputStream)
      $writer.Write("Not Found: $rel")
      $writer.Flush()
      $ctx.Response.OutputStream.Close()
    }
  } catch {
    Write-Warning "Request error: $_"
  }
}