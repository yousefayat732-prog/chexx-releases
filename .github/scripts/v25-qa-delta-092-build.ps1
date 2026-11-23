$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$repo='yousefayat732-prog/chexx-releases'
if($env:GITHUB_REPOSITORY -ne $repo){throw 'Wrong GitHub repository'}
$dir=Join-Path $env:GITHUB_WORKSPACE 'delta-qa-092'
New-Item -ItemType Directory -Path $dir -Force|Out-Null
$identity='app.chexx.academy.v25githubqa'
$channel='win-x64-beta'
$old='app.chexx.academy.v25githubqa-0.9.1-win-x64-beta-full.nupkg'
$new='app.chexx.academy.v25githubqa-0.9.2-win-x64-beta-full.nupkg'
$delta='app.chexx.academy.v25githubqa-0.9.2-win-x64-beta-delta.nupkg'
$shaOld='4150018895dbc386cb6e7a93eb55daf75d2c98cb918ea7b7321b028ad7f60c17'
$shaNew='cb502451b7171a1e03633f56b9fb4846c4586a4e43db800b026dce4246432ffb'
function Assert-Exit([string]$stage){if($LASTEXITCODE -ne 0){throw ('FAILED_STAGE '+$stage+' EXIT '+$LASTEXITCODE)}}
function Sha([string]$file){return (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash.ToLowerInvariant()}
function NoBom([string]$file,[string]$data){[IO.File]::WriteAllText($file,$data,[Text.UTF8Encoding]::new($false))}
Push-Location $dir
try {
 & gh release download v25-github-qa-0.9.1 --repo $repo --pattern $old
 Assert-Exit 'download-original-A'
 & gh release download v25-github-qa-0.9.2 --repo $repo --pattern $new
 Assert-Exit 'download-original-B'
 & gh release download v25-github-qa-0.9.2 --repo $repo --pattern 'releases.win-x64-beta.json' --pattern 'assets.win-x64-beta.json' --pattern 'RELEASES-win-x64-beta'
 Assert-Exit 'download-qa-release-metadata'
 if((Sha $old) -ne $shaOld -or (Sha $new) -ne $shaNew){throw 'Source full packages differ from verified published GitHub digests'}
 $feed=Get-Content 'releases.win-x64-beta.json' -Raw|ConvertFrom-Json
 $fulls=@($feed.Assets)
 if($fulls.Count -ne 1 -or $fulls[0].Type -ne 'Full' -or $fulls[0].Version -ne '0.9.2' -or $fulls[0].PackageId -ne $identity -or $fulls[0].FileName -ne $new){throw 'Unexpected V25 QA full release manifest'}
 $oldRemote=gh api ('repos/'+$repo+'/releases/tags/v25-github-qa-0.9.2')|ConvertFrom-Json
 Assert-Exit 'remote-release-check'
 if(!$oldRemote.prerelease -or $oldRemote.draft){throw 'Not a published QA prerelease'}
 if(@($oldRemote.assets|Where-Object{$_.name -eq $delta}).Count -gt 0){throw 'Delta already uploaded; refusing duplicate'}
 & vpk delta generate --base $old --new $new --output $delta --mode BestSpeed
 Assert-Exit 'generate-velopack-delta'
 if(!(Test-Path $delta)){throw 'Official Velopack delta missing'}
 $deltaSize=(Get-Item $delta).Length
 $fullSize=(Get-Item $new).Length
 if($deltaSize -lt 1024 -or $deltaSize -gt ($fullSize*0.55)){throw ('Delta is not an improvement; refusing to publish. Delta='+$deltaSize+' Full='+$fullSize)}
 $reconstructed='reconstructed-v25-qa-0.9.2-full.nupkg'
 & vpk delta patch --base $old --patch $delta --output $reconstructed
 Assert-Exit 'reconstruct-velopack-patch'
 if((Sha $reconstructed) -ne $shaNew){throw 'PATCH_RECONSTRUCTION_SHA256_MISMATCH'}
 Remove-Item -LiteralPath $reconstructed -Force
 $dFile=Get-Item $delta
 $deltaSha1=(Get-FileHash $delta -Algorithm SHA1).Hash
 $deltaSha256=(Get-FileHash $delta -Algorithm SHA256).Hash
 $deltaAsset=[ordered]@{
  PackageId=$identity;Version='0.9.2';Type='Delta';FileName=$delta
  SHA1=$deltaSha1;SHA256=$deltaSha256;Size=$dFile.Length
 }
 $fullAsset=$fulls[0]
 $feedUpdated=[ordered]@{Assets=@($fullAsset,$deltaAsset)}
 NoBom 'releases.win-x64-beta-fast.json' ($feedUpdated|ConvertTo-Json -Depth 15 -Compress)
 $assets=Get-Content 'assets.win-x64-beta.json' -Raw|ConvertFrom-Json
 if(@($assets).Count -lt 1){throw 'Unexpected assets list'}
 $newAssets=@($assets)+@([ordered]@{RelativeFileName=$delta;Type='Delta'})
 NoBom 'assets.win-x64-beta-fast.json' ($newAssets|ConvertTo-Json -Depth 10 -Compress)
 $legacy=Get-Content 'RELEASES-win-x64-beta' -Raw
 NoBom 'RELEASES-win-x64-beta-fast' ($legacy.TrimEnd()+[Environment]::NewLine+$deltaSha1+' '+$delta+' '+$dFile.Length+[Environment]::NewLine)
 NoBom ($delta+'.sha256') ($deltaSha256.ToLowerInvariant()+'  '+$delta+[Environment]::NewLine)
 $evidence=[ordered]@{base='0.9.1';target='0.9.2';channel=$channel;appId=$identity
  fullBytes=$fullSize;deltaBytes=$deltaSize;reductionPercent=[math]::Round((1-$deltaSize/$fullSize)*100,2)
  fullSha256=$shaNew;deltaSha256=$deltaSha256.ToLowerInvariant();patchReconstructedByteExact=$true
  originalRelease='v25-github-qa-0.9.2';originalReleaseUntouched=$true}
 NoBom 'fast-qa-proof.json' ($evidence|ConvertTo-Json -Depth 10)
 Write-Output ('VELOPACK_QA_DELTA_BUILD_AND_RECONSTRUCT_PASS '+($evidence|ConvertTo-Json -Compress))
} finally {Pop-Location}
