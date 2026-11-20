param(
  [Parameter(Mandatory = $true)]
  [string] $SourcePng,
  [Parameter(Mandatory = $true)]
  [string] $DestinationIco
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$source = [Drawing.Image]::FromFile([IO.Path]::GetFullPath($SourcePng))
$output = $null
$writer = $null
try {
  $sizes = @(16, 24, 32, 48, 64, 128, 256)
  $images = foreach ($size in $sizes) {
    $bitmap = New-Object Drawing.Bitmap($size, $size)
    $graphics = [Drawing.Graphics]::FromImage($bitmap)
    $stream = New-Object IO.MemoryStream
    try {
      $graphics.Clear([Drawing.Color]::Transparent)
      $graphics.InterpolationMode = [Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
      $graphics.PixelOffsetMode = [Drawing.Drawing2D.PixelOffsetMode]::HighQuality
      $graphics.CompositingQuality = [Drawing.Drawing2D.CompositingQuality]::HighQuality
      $scale = [Math]::Min($size / $source.Width, $size / $source.Height)
      $width = [int][Math]::Round($source.Width * $scale)
      $height = [int][Math]::Round($source.Height * $scale)
      $graphics.DrawImage($source, [int](($size - $width) / 2), [int](($size - $height) / 2), $width, $height)
      $bitmap.Save($stream, [Drawing.Imaging.ImageFormat]::Png)
      [pscustomobject]@{ Size = $size; Bytes = $stream.ToArray() }
    } finally {
      $stream.Dispose()
      $graphics.Dispose()
      $bitmap.Dispose()
    }
  }

  $output = [IO.File]::Create([IO.Path]::GetFullPath($DestinationIco))
  $writer = New-Object IO.BinaryWriter($output)
  $writer.Write([uint16]0)
  $writer.Write([uint16]1)
  $writer.Write([uint16]$images.Count)
  $offset = 6 + 16 * $images.Count
  foreach ($image in $images) {
    $dimension = [byte]($image.Size % 256)
    $writer.Write($dimension)
    $writer.Write($dimension)
    $writer.Write([byte]0)
    $writer.Write([byte]0)
    $writer.Write([uint16]1)
    $writer.Write([uint16]32)
    $writer.Write([uint32]$image.Bytes.Length)
    $writer.Write([uint32]$offset)
    $offset += $image.Bytes.Length
  }
  foreach ($image in $images) { $writer.Write([byte[]]$image.Bytes) }
} finally {
  if ($writer) { $writer.Dispose() }
  if ($output) { $output.Dispose() }
  $source.Dispose()
}
