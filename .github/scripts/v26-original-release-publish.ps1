# Publish the exact CI-tested v0.8.9 NSIS candidate only after isolated 0.8.8->0.8.9 Windows QA.
# Stable product identity unchanged. Never expose any user's private profile or audio clips.
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$repo='yousefayat732-prog/chexx-releases'
$sourceSha='46486e5fee157c96df09d52f1d69a93a5516c4ef'
$version='0.8.9'
$tag='v'+$version
$candidateRunId=45250760020
if($env:GITHUB_REPOSITORY -ne $repo){throw 'Unexpected release repo'}
$source=Join-Path $env:GITHUB_WORKSPACE 'source'
$dir=Join-Path $env:GITHUB_WORKSPACE 'candidate'
$build=Join-Path $env:GITHUB_WORKSPACE 'verified-release-v0.8.9'
New-Item -Path $build -ItemType Directory -Force|Out-Null
function ExitOk([string]$stage){if($LASTEXITCODE -ne 0){throw ('RELEASE_FAILED_'+$stage+' Exit='+$LASTEXITCODE)}}
function Sha([string]$file){return (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash.ToLowerInvariant()}
function WriteUtf8([string]$file,[string]$data){[IO.File]::WriteAllText($file,$data,[Text.UTF8Encoding]::new($false))}
function ExactlyOne([string]$folder,[string]$name){
 $found=@(Get-ChildItem -LiteralPath $folder -Recurse -File|Where-Object{$_.Name -eq $name})
 if($found.Count -ne 1){throw ('Expected one '+$name+'; found '+$found.Count)}
 return $found[0]
}
$run=gh api ('repos/'+$repo+'/actions/runs/'+$candidateRunId)|ConvertFrom-Json
ExitOk 'CANDIDATE_RUN_STATUS'
if($run.conclusion -ne 'success' -or $run.status -ne 'completed' -or
   $run.name -ne 'Charli Chexx V26 ORIGINAL 0.8.9 — Candidate and isolated NSIS upgrade QA'){
 throw 'NSIS candidate Windows upgrade gate not proven PASS'
}
$commit=(& git -C $source rev-parse HEAD).Trim()
ExitOk 'SOURCE_SHA'
if($commit -ne $sourceSha){throw 'Pinned source SHA mismatch'}
$pkg=Get-Content (Join-Path $source 'package.json') -Raw|ConvertFrom-Json
if($pkg.version -ne $version -or $pkg.build.appId -ne 'app.chexx.academy' -or
   $pkg.build.win.target -ne 'nsis'){throw 'Wrong NSIS product identity'}
$latest=gh api ('repos/'+$repo+'/releases/latest')|ConvertFrom-Json
ExitOk 'LATEST_BEFORE'
if($latest.tag_name -ne 'v0.8.8' -or $latest.prerelease){throw 'Stable channel not at expected 0.8.8'}
$existing=@(gh api ('repos/'+$repo+'/releases?per_page=100')|ConvertFrom-Json)
ExitOk 'EXISTING_RELEASES'
if(@($existing|Where-Object{$_.tag_name -eq $tag}).Count -ne 0){throw 'Refuse to overwrite existing v0.8.9'}
$exe=(ExactlyOne $dir 'CHEXX Setup 0.8.9.exe').FullName
$side=(ExactlyOne $dir 'CHEXX Setup 0.8.9.exe.sha256').FullName
$qa=(ExactlyOne $dir 'RELEASE_QA_MANIFEST.json').FullName
$sha=Sha $exe
$sideText=(Get-Content $side -Raw).Trim()
if($sha -ne $sideText.Substring(0,64).ToLowerInvariant() -or
   $sideText -notmatch 'CHEXX Setup 0\.8\.9\.exe$'){throw 'Installer SHA256 mismatch'}
$qaManifest=Get-Content $qa -Raw|ConvertFrom-Json
if($qaManifest.version -ne $version -or $qaManifest.status -ne 'REVIEW_NOT_PUBLIC' -or
   $qaManifest.boardsVerified -ne 10 -or $qaManifest.piecesVerified -ne 240 -or
   $qaManifest.solarPreviewsVerified -ne 8 -or $qaManifest.privateAudioBundled -or
   !$qaManifest.updateHelperPackaged -or !$qaManifest.updateLauncherPackaged -or
   [long]$qaManifest.installerBytes -ne (Get-Item $exe).Length -or
   $qaManifest.installerSha256.ToLowerInvariant() -ne $sha){
 throw 'Candidate QA manifest inconsistent with tested installer'
}
$qaManifest.status='ISOLATED_WINDOWS_NSIS_0_8_8_TO_0_8_9_PASS_LIVE_GITHUB_UPDATE_PENDING'
$qaPublish=Join-Path $build 'RELEASE_QA_MANIFEST.json'
WriteUtf8 $qaPublish (($qaManifest|ConvertTo-Json -Depth 10)+[Environment]::NewLine)
$sourceArchive=Join-Path $build ('CHEXX-'+$version+'-source.zip')
& git -C $source archive --format=zip HEAD -o $sourceArchive
ExitOk 'SOURCE_ARCHIVE'
if(!(Test-Path $sourceArchive)){throw 'Source archive missing'}
$sourceSum=$sourceArchive+'.sha256'
WriteUtf8 $sourceSum ((Sha $sourceArchive)+'  '+[IO.Path]::GetFileName($sourceArchive)+[Environment]::NewLine)
$notes=@'
Charli Chexx v0.8.9 — ORIGINAL Windows version (NSIS), accelerated safe downloader:
• Up to 8 parallel HTTPS byte-range downloads for future stable updates when the GitHub CDN supports byte ranges.
• Verifies each completed part before safe reuse after interruptions; retries transient errors; falls back to verified single-stream download.
• Never starts an installer before the entire official GitHub file's SHA-256 and size exactly match its release.
• Existing mandatory red backup warning, profile integrity checks, NSIS helper and Windows installation identity are unchanged.
• Preserves all v0.8.8 game content: bot clocks, training, 240 chess pieces, 10 boards, 8 planets and offline rewards.
• Does not ship private original Chess.com-derived WAVs. Existing personal audio files remain private.
• Verified by 123/123 Windows source tests, a packaged installer QA gate, and an isolated real 0.8.8 -> 0.8.9 Windows NSIS update including a verified profile backup.
• This is an NSIS-compatible stable update, NOT the separate Velopack Beta. 50KB Velopack delta updates only work after a tested one-time installer migration. Existing 0.8.8 must still acquire this first full installer.
• Unsigned Windows installer may trigger Windows SmartScreen. No paid external services or credentials required.
• Full private-source snapshot with license notices is provided as an archive.
'@
$payload=Join-Path $build 'create-release.json'
WriteUtf8 $payload (@{tag_name=$tag;target_commitish='main';name='Charli Chexx 0.8.9 — schneller sicherer Original-Updater';draft=$true;prerelease=$false;body=$notes}|ConvertTo-Json -Compress)
$draft=gh api -X POST ('repos/'+$repo+'/releases') --input $payload|ConvertFrom-Json
ExitOk 'CREATE_STABLE_DRAFT'
if(!$draft.id -or !$draft.draft -or $draft.prerelease){throw 'Stable release draft creation invalid'}
$id=[long]$draft.id
$uploadBase=([string]$draft.upload_url).Split('{')[0]
if($uploadBase -ne ('https://uploads.github.com/repos/'+$repo+'/releases/'+$id+'/assets')){
 throw 'Unapproved upload destination'
}
$files=@($exe,$side,$sourceArchive,$sourceSum,$qaPublish)
$names=@('CHEXX.Setup.0.8.9.exe','CHEXX.Setup.0.8.9.exe.sha256',
  'CHEXX-0.8.9-source.zip','CHEXX-0.8.9-source.zip.sha256','RELEASE_QA_MANIFEST.json')
foreach($file in $files){
 $name=[IO.Path]::GetFileName($file)
 $url=$uploadBase+'?name='+[Uri]::EscapeDataString($name)
 $asset=gh api -X POST $url --input $file --header 'Content-Type: application/octet-stream'|ConvertFrom-Json
 ExitOk ('UPLOAD_'+$name)
 if(!$asset.id -or $asset.state -ne 'uploaded' -or
    [long]$asset.size -ne (Get-Item $file).Length -or
    ($asset.digest -and $asset.digest -ne ('sha256:'+(Sha $file)))){
  throw ('GitHub asset upload verification failed '+$name)
 }
 Write-Output ('V26_STABLE_DRAFT_ASSET_VERIFIED='+$asset.name+' BYTES='+$asset.size)
}
$check=gh api ('repos/'+$repo+'/releases/'+$id)|ConvertFrom-Json
ExitOk 'RECHECK_DRAFT'
if(!$check.draft -or $check.prerelease){throw 'Release prematurely published'}
foreach($name in $names){
 if(@($check.assets|Where-Object{$_.name -eq $name -and $_.state -eq 'uploaded'}).Count -ne 1){
  throw ('Missing verified draft asset '+$name)
 }
}
$pubPath=Join-Path $build 'publish.json'
WriteUtf8 $pubPath (@{draft=$false;prerelease=$false;body=$notes}|ConvertTo-Json -Compress)
$published=gh api -X PATCH ('repos/'+$repo+'/releases/'+$id) --input $pubPath|ConvertFrom-Json
ExitOk 'PUBLISH'
if(!$published.id -or $published.draft -or $published.prerelease -or $published.tag_name -ne $tag){
 throw 'Stable release publish did not confirm'
}
$after=gh api ('repos/'+$repo+'/releases/latest')|ConvertFrom-Json
ExitOk 'LATEST_AFTER'
if($after.tag_name -ne $tag -or $after.draft -or $after.prerelease){throw 'Latest stable was not v0.8.9'}
Write-Output ('V26_ORIGINAL_STABLE_RELEASE_VERIFIED=https://github.com/'+$repo+'/releases/tag/'+$tag)
Write-Output ('V26_ORIGINAL_RELEASE_SHA256='+$sha)
