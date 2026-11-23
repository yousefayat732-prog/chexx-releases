# Publish verified official Velopack delta ONLY to existing V25 prerelease 0.9.2.
# Does not touch stable latest or 0.9.1 installer; no user computer access.
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$repo='yousefayat732-prog/chexx-releases'
if($env:GITHUB_REPOSITORY -ne $repo){throw 'Wrong repository'}
$dir=Join-Path $env:GITHUB_WORKSPACE 'downloaded-delta'
$backupDir=Join-Path $dir 'old-release-metadata'
New-Item -ItemType Directory $backupDir -Force|Out-Null
$tag='v25-github-qa-0.9.2'
$expectedIdentity='app.chexx.academy.v25githubqa'
$deltaName='app.chexx.academy.v25githubqa-0.9.2-win-x64-beta-delta.nupkg'
$shaDelta='2af180aed6fcf41131d9374c9a78d1c89b852a8629d1dac2a829bddb87f9dfe1'
$shaFull='cb502451b7171a1e03633f56b9fb4846c4586a4e43db800b026dce4246432ffb'
$known=@{
 'releases.win-x64-beta.json'='cd9ddac266d8d4d0cbe23e5bc05c88bcee028196b5cd06d4ebf2e57adab85760'
 'assets.win-x64-beta.json'='5df1581cd088813167e1550376f82527e59a8e4e8537ee2f3090a7f9bec8ff10'
 'RELEASES-win-x64-beta'='d69e17bfcc1d1fbd4bc660a3374ae43b0f65fb726a50ffc2356e1c509ae46882'
}
function Assert-Exit([string]$stage){if($LASTEXITCODE -ne 0){throw ('GITHUB_API_FAILURE '+$stage+' EXIT '+$LASTEXITCODE)}}
function Hash([string]$file){return (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash.ToLowerInvariant()}
$delta=Join-Path $dir $deltaName
$proof=Join-Path $dir 'fast-qa-proof.json'
$sidecar=$delta+'.sha256'
foreach($file in @($delta,$proof,$sidecar)){
 if(!(Test-Path -LiteralPath $file -PathType Leaf)){throw ('Missing verified candidate artifact '+$file)}
}
$proofJson=Get-Content $proof -Raw|ConvertFrom-Json
if($proofJson.base -ne '0.9.1' -or $proofJson.target -ne '0.9.2' -or
  $proofJson.appId -ne $expectedIdentity -or !$proofJson.patchReconstructedByteExact -or
  [long]$proofJson.deltaBytes -ne (Get-Item $delta).Length -or
  [long]$proofJson.fullBytes -ne 427116231 -or
  $proofJson.deltaSha256 -ne $shaDelta -or
  $proofJson.fullSha256 -ne $shaFull -or
  (Hash $delta) -ne $shaDelta -or
  ((Get-Content $sidecar -Raw).Trim().Split(' ')[0]) -ne $shaDelta){
 throw 'Candidate delta verification mismatch; refusing publication'
}
if($proofJson.deltaBytes -gt (427116231 * 0.55)){throw 'Not significantly smaller than full package'}
$updatedAssets=Join-Path $dir 'assets.win-x64-beta-fast.json'
$updatedFeed=Join-Path $dir 'releases.win-x64-beta-fast.json'
$updatedLegacy=Join-Path $dir 'RELEASES-win-x64-beta-fast'
foreach($f in @($updatedAssets,$updatedFeed,$updatedLegacy)){if(!(Test-Path $f)){throw ('Candidate feed missing '+$f)}}
$feed=Get-Content $updatedFeed -Raw | ConvertFrom-Json
$feedAssets=@($feed.Assets)
if($feedAssets.Count -ne 2 -or @($feedAssets|Where-Object{$_.Type -eq 'Delta' -and $_.PackageId -eq $expectedIdentity -and $_.Version -eq '0.9.2' -and $_.SHA256.ToLowerInvariant() -eq $shaDelta}).Count -ne 1 -or
 @($feedAssets|Where-Object{$_.Type -eq 'Full' -and $_.SHA256.ToLowerInvariant() -eq $shaFull}).Count -ne 1){
 throw 'New Velopack feed invalid'
}
$latestBefore=gh api ('repos/'+$repo+'/releases/latest')|ConvertFrom-Json
Assert-Exit 'stable-latest-before'
if($latestBefore.tag_name -ne 'v0.8.8' -or $latestBefore.prerelease){throw 'Unexpected stable release: fail closed'}
$release=gh api ('repos/'+$repo+'/releases/tags/'+$tag)|ConvertFrom-Json
Assert-Exit 'v25-tag'
if(!$release.id -or !$release.prerelease -or $release.draft -or $release.tag_name -ne $tag){
 throw 'Cannot publish to non-QA release'
}
if(@($release.assets|Where-Object{$_.name -eq $deltaName -or $_.name -eq ($deltaName+'.sha256')}).Count -ne 0){
 throw 'New delta already exists; refusing duplicate publication'
}
foreach($name in $known.Keys){
 $asset=@($release.assets|Where-Object{$_.name -eq $name -and $_.state -eq 'uploaded'})
 if($asset.Count -ne 1 -or $asset[0].digest -ne ('sha256:'+$known[$name])){throw ('Metadata not as approved '+$name)}
 gh release download $tag --repo $repo --pattern $name --dir $backupDir|Out-Null
 Assert-Exit ('metadata-backup-'+$name)
 if((Hash (Join-Path $backupDir $name)) -ne $known[$name]){throw ('Metadata backup changed '+$name)}
}
$oldAssets=@{}
foreach($name in $known.Keys){$oldAssets[$name]=@($release.assets|Where-Object{$_.name -eq $name})[0].id}
$uploadBase=([string]$release.upload_url).Split('{')[0]
$expectedBase='https://uploads.github.com/repos/'+$repo+'/releases/'+$release.id+'/assets'
if($uploadBase -ne $expectedBase){throw 'Unapproved GitHub upload API'}
function Upload-Asset([string]$file,[string]$name){
 $url=$uploadBase+'?name='+[Uri]::EscapeDataString($name)
 $result=gh api -X POST $url --input $file --header 'Content-Type: application/octet-stream' | ConvertFrom-Json
 Assert-Exit ('upload-'+$name)
 if(!$result.id -or $result.state -ne 'uploaded' -or
  [long]$result.size -ne (Get-Item $file).Length -or
  ($result.digest -and $result.digest -ne ('sha256:'+(Hash $file)))){
  throw ('Uploaded GitHub asset unverified '+$name)
 }
 Write-Output ('V25_QA_ASSET_VERIFIED='+$name+' BYTES='+$result.size)
}
Upload-Asset $delta $deltaName
Upload-Asset $sidecar ($deltaName+'.sha256')
# Only now activate delta discovery through the official Velopack feed.
$updated=@{
 'releases.win-x64-beta.json'=$updatedFeed
 'assets.win-x64-beta.json'=$updatedAssets
 'RELEASES-win-x64-beta'=$updatedLegacy
}
$changed=@()
try {
 foreach($name in @('releases.win-x64-beta.json','assets.win-x64-beta.json','RELEASES-win-x64-beta')){
  gh api -X DELETE ('repos/'+$repo+'/releases/assets/'+$oldAssets[$name])|Out-Null
  Assert-Exit ('delete-old-metadata-'+$name)
  $changed+=@($name)
  Upload-Asset $updated[$name] $name
 }
}catch{
 Write-Warning ('Publishing QA feed failed; attempting metadata restoration. '+$_.Exception.Message)
 foreach($name in $changed){
  $current=gh api ('repos/'+$repo+'/releases/'+$release.id)|ConvertFrom-Json
  foreach($asset in @($current.assets|Where-Object{$_.name -eq $name})){
   gh api -X DELETE ('repos/'+$repo+'/releases/assets/'+$asset.id)|Out-Null
  }
  try{Upload-Asset (Join-Path $backupDir $name) $name}
  catch{Write-Warning ('Recovery failed '+$name+' '+$_.Exception.Message)}
 }
 throw 'QA metadata publication failed; see recovery logs'
}
$after=gh api ('repos/'+$repo+'/releases/'+$release.id)|ConvertFrom-Json
Assert-Exit 'final-release-check'
foreach($name in @($deltaName,($deltaName+'.sha256'),'releases.win-x64-beta.json','assets.win-x64-beta.json','RELEASES-win-x64-beta')){
 if(@($after.assets|Where-Object{$_.name -eq $name -and $_.state -eq 'uploaded'}).Count -ne 1){throw ('QA release asset missing after publish '+$name)}
}
$stable=gh api ('repos/'+$repo+'/releases/latest')|ConvertFrom-Json
Assert-Exit 'final-stable'
if($stable.tag_name -ne $latestBefore.tag_name -or $stable.prerelease){throw 'Stable channel changed unexpectedly'}
Write-Output ('V25_GITHUB_QA_FAST_DELTA_RELEASE_CONFIRMED='+$after.html_url)
Write-Output ('V25_GITHUB_QA_FULL_BYTES='+$proofJson.fullBytes+' DELTA_BYTES='+$proofJson.deltaBytes+' SAVINGS_PERCENT='+$proofJson.reductionPercent)
Write-Output ('V25_STABLE_RELEASE_UNTOUCHED='+$stable.tag_name)
