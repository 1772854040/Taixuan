param([int]$Port=5500,[string]$Root=(Get-Location).Path)

$prefix = "http://localhost:$Port/"
Write-Output "PREVIEW_URL:$prefix"

$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Clear(); $listener.Prefixes.Add($prefix); $listener.Start()

$contentTypes = @{
  ".html" = "text/html; charset=utf-8"
  ".css"  = "text/css; charset=utf-8"
  ".js"   = "application/javascript; charset=utf-8"
  ".json" = "application/json; charset=utf-8"
  ".svg"  = "image/svg+xml"
  ".png"  = "image/png"
  ".jpg"  = "image/jpeg"
  ".jpeg" = "image/jpeg"
  ".gif"  = "image/gif"
  ".ico"  = "image/x-icon"
}
$defaultContentType = "application/octet-stream"

$cacheControls = @{
  ".html" = "no-cache"
  ".json" = "no-cache"
  ".css"  = "public, max-age=604800" # 7天
  ".js"   = "public, max-age=604800"
  ".png"  = "public, max-age=604800"
  ".jpg"  = "public, max-age=604800"
  ".jpeg" = "public, max-age=604800"
  ".gif"  = "public, max-age=604800"
  ".svg"  = "public, max-age=604800"
  ".ico"  = "public, max-age=604800"
}
$defaultCacheControl = "public, max-age=86400" # 1天

while($true){
  $ctx = $listener.GetContext()
  try{
    $req = $ctx.Request
    $res = $ctx.Response
    $urlPath = $req.Url.AbsolutePath.TrimStart('/')
    if([string]::IsNullOrWhiteSpace($urlPath)){ $urlPath = "1.html" }
    $file = Join-Path $Root $urlPath
    if(-not (Test-Path $file)){
      $res.StatusCode = 404
      $bytes = [Text.Encoding]::UTF8.GetBytes("Not Found")
      $res.ContentType = "text/plain; charset=utf-8"
      $res.ContentLength64 = $bytes.Length
      $res.OutputStream.Write($bytes,0,$bytes.Length)
      $res.OutputStream.Close()
      continue
    }
    $bytes = [IO.File]::ReadAllBytes($file)
    $ext = [IO.Path]::GetExtension($file).ToLower()
    $ctype = $defaultContentType
    if($contentTypes.ContainsKey($ext)){ $ctype = $contentTypes[$ext] }
    $cache = $defaultCacheControl
    if($cacheControls.ContainsKey($ext)){ $cache = $cacheControls[$ext] }
    $res.ContentType = $ctype
    $res.Headers["Cache-Control"] = $cache
    $res.Headers["Last-Modified"] = (Get-Item $file).LastWriteTimeUtc.ToString("r")
    $res.ContentLength64 = $bytes.Length
    $res.OutputStream.Write($bytes,0,$bytes.Length)
    $res.OutputStream.Close()
  }catch{
    try{ $ctx.Response.OutputStream.Close() }catch{}
  }
}