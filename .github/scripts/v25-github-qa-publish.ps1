# V25 GithubSource QA only. Never touches the user's PC or stable CHEXX.
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$repo=$env:GITHUB_REPOSITORY
if($repo -ne 'yousefayat732-prog/chexx-releases'){throw 'Wrong release repository'}
$src=Join-Path $env:GITHUB_WORKSPACE 'source'
$out=Join-Path $env:GITHUB_WORKSPACE 'v25-github-qa-output'
$identity='app.chexx.academy.v25githubqa'
$tagBase='v25-github-qa-'
$versions=@('0.9.1','0.9.2')
New-Item -ItemType Directory -Path $out -Force | Out-Null
function Check-Exit([string]$stage){if($LASTEXITCODE -ne 0){throw ('FAIL '+$stage+' code='+$LASTEXITCODE)}}
function NoBom([string]$file,[string]$value){[IO.File]::WriteAllText($file,$value,[Text.UTF8Encoding]::new($false))}
function One([string]$dir,[string]$pattern){
 $result=@(Get-ChildItem -LiteralPath $dir -File -Filter $pattern)
 if($result.Count -ne 1){throw ('Expected one '+$pattern+' in '+$dir+', actual='+$result.Count)}
 return $result[0]
}
$sha=(& git -C $src rev-parse HEAD).Trim()
Check-Exit 'git-head'
if($sha -ne '3db41ad08c4f96858417ce6aedbc957f7a303a07'){throw 'Wrong pinned V25 source'}
$cfg=Get-Content (Join-Path $src 'package.json') -Raw|ConvertFrom-Json
if($cfg.version -ne '0.9.0' -or $cfg.build.appId -ne 'app.chexx.academy' -or $cfg.dependencies.velopack -ne '1.2.161'){throw 'Wrong source package'}
$oldLatest=gh api ('repos/'+$repo+'/releases/latest')|ConvertFrom-Json
Check-Exit 'stable-latest-before'
if(!$oldLatest.tag_name -or $oldLatest.prerelease){throw 'Stable release missing'}
$existing=@(gh api ('repos/'+$repo+'/releases?per_page=100')|ConvertFrom-Json)
Check-Exit 'inspect-releases'
foreach($v in $versions){
 if(@($existing|Where-Object{$_.tag_name -eq ($tagBase+$v)}).Count -ne 0){throw ('Refuse overwriting beta tag '+$tagBase+$v)}
}
Push-Location $src
try {
 & npm.cmd ci; Check-Exit 'npm-ci'
 & npm.cmd test; Check-Exit 'npm-test'
 & node scripts/v25-github-beta-prepare.mjs 0.9.1; Check-Exit 'isolate-qa-app'
 & node --check electron/main.cjs; Check-Exit 'main-syntax'
 & node --check electron/velopack-service.cjs; Check-Exit 'adapter-syntax'
 & npm.cmd run dist:v25-stage; Check-Exit 'electron-A'
 $stage=Join-Path $src 'release-v25-github-qa-A/win-unpacked'
 if(!(Test-Path (Join-Path $stage 'CHEXX.exe'))){throw 'QA A executable missing'}
 $native=Join-Path $stage 'resources/app.asar.unpacked'
 if(!(Test-Path $native) -or @((Get-ChildItem $native -Recurse -File -Filter '*.node')).Count -lt 1){throw 'Native module missing'}
 if(@((Get-ChildItem $stage -Recurse -File -Filter '*.wav')).Count -gt 0){throw 'Private WAV was packaged'}
 & vpk pack --packId $identity --packVersion '0.9.1' --packDir $stage --mainExe CHEXX.exe --packTitle 'Charli Chexx V25 GITHUB TEST' --channel win-x64-beta --outputDir (Join-Path $out '0.9.1')
 Check-Exit 'vpk-A'
 $diff=(& git diff --binary -- electron/main.cjs electron/velopack-service.cjs package.json) -join [Environment]::NewLine
 NoBom (Join-Path $out 'V25-GITHUB-QA-0.9.1.patch') ($diff+[Environment]::NewLine)
 $pkg=Get-Content 'package.json' -Raw|ConvertFrom-Json -AsHashtable
 if($pkg.version -ne '0.9.1' -or $pkg.build.appId -ne $identity){throw 'QA identity altered'}
 $pkg.version='0.9.2'
 $pkg.build.directories.output='release-v25-github-qa-B'
 NoBom (Join-Path $src 'package.json') (($pkg|ConvertTo-Json -Depth 30)+[Environment]::NewLine)
 & npm.cmd run dist:v25-stage; Check-Exit 'electron-B'
 $stage=Join-Path $src 'release-v25-github-qa-B/win-unpacked'
 if(!(Test-Path (Join-Path $stage 'CHEXX.exe'))){throw 'QA B executable missing'}
 if(!(Test-Path (Join-Path $stage 'resources/app.asar.unpacked'))){throw 'Native module missing in B'}
 if(@((Get-ChildItem $stage -Recurse -File -Filter '*.wav')).Count -gt 0){throw 'Private WAV was packaged in B'}
 & vpk pack --packId $identity --packVersion '0.9.2' --packDir $stage --mainExe CHEXX.exe --packTitle 'Charli Chexx V25 GITHUB TEST' --channel win-x64-beta --outputDir (Join-Path $out '0.9.2')
 Check-Exit 'vpk-B'
 $diff=(& git diff --binary -- electron/main.cjs electron/velopack-service.cjs package.json) -join [Environment]::NewLine
 NoBom (Join-Path $out 'V25-GITHUB-QA-0.9.2.patch') ($diff+[Environment]::NewLine)
 & git archive --format=zip HEAD -o (Join-Path $out 'CHEXX-V25-GITHUB-QA-source.zip')
 Check-Exit 'source-archive'
} finally {Pop-Location}

# Fail closed if any binary is not exactly the expected Velopack test identity/version.
foreach($v in $versions){
 $dir=Join-Path $out $v
 $full=One $dir '*-full.nupkg'
 $setup=One $dir '*-Setup.exe'
 $manifest=Get-Content (Join-Path $dir 'releases.win-x64-beta.json') -Raw|ConvertFrom-Json
 $assets=@($manifest.Assets)
 if($assets.Count -ne 1 -or $assets[0].PackageId -ne $identity -or $assets[0].Version -ne $v -or
    $assets[0].Type -ne 'Full' -or $assets[0].FileName -ne $full.Name){throw ('Invalid Velopack metadata '+$v)}
 $hash=(Get-FileHash $full.FullName -Algorithm SHA256).Hash
 if($assets[0].SHA256 -ne $hash -or [long]$assets[0].Size -ne $full.Length){throw ('Tampered package '+$v)}
 if($full.Length -lt 10000000 -or $setup.Length -lt 10000000){throw ('Unexpected package size '+$v)}
 foreach($required in @('assets.win-x64-beta.json','RELEASES-win-x64-beta')){
  if(!(Test-Path (Join-Path $dir $required))){throw ('Missing Velopack feed '+$v+'/'+$required)}
 }
 NoBom ($full.FullName+'.sha256') ($hash.ToLowerInvariant()+'  '+$full.Name+[Environment]::NewLine)
 $setupHash=(Get-FileHash $setup.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
 NoBom ($setup.FullName+'.sha256') ($setupHash+'  '+$setup.Name+[Environment]::NewLine)
 Write-Host ('VERIFIED_QA_RELEASE='+$v+' FULL_SHA256='+$hash+' BYTES='+$full.Length)
}
# A real installer smoke check runs only on the temporary GitHub Windows runner.
$bootstrap=One (Join-Path $out '0.9.1') '*-Setup.exe'
$qaDir=Join-Path $env:RUNNER_TEMP 'CharliChexx-V25-GithubTest'
$installer=Start-Process -FilePath $bootstrap.FullName -ArgumentList ('--silent --installto "'+$qaDir+'"') -PassThru -Wait
if($installer.ExitCode -ne 0 -or !(Test-Path (Join-Path $qaDir 'current/CHEXX.exe')) -or
   !(Test-Path (Join-Path $qaDir 'Update.exe'))){throw 'GitHub beta bootstrap installation smoke failed'}
Write-Host 'GITHUB_QA_BOOTSTRAP_INSTALL_SMOKE_PASS'

# Only after BOTH packages pass, create two drafts then upload and publish as PRE-RELEASES.
$ids=@{}
foreach($v in $versions){
 $tag=$tagBase+$v
 $explain=if($v -eq '0.9.1'){'BOOTSTRAP: install once to enable public GithubSource test updates to 0.9.2.'}else{'UPDATE: use V25 GITHUB TEST 0.9.1 Settings > Updates to download/install 0.9.2.'}
 $body='EXPERIMENTAL CHARLI CHEXX V25 GITHUB TEST ONLY. '+$explain+' Isolated packId app.chexx.academy.v25githubqa; isolated profile chexx-academy-V25-GITHUB-QA. Existing locally installed V25 TEST 0.9.1 uses FileSource and will NOT detect these online packages: first install the separate 0.9.1 GITHUB TEST setup. Stable Charli Chexx 0.8.8 remains unchanged. Windows installer is unsigned; original private WAV recordings are excluded. Corresponding source: CHEXX-V25-GITHUB-QA-source.zip plus matching QA patch.'
 $json=Join-Path $out ('draft-'+$v+'.json')
 NoBom $json (@{tag_name=$tag;target_commitish='main';name=('Charli Chexx V25 GITHUB TEST '+$v);draft=$true;prerelease=$true;body=$body}|ConvertTo-Json -Compress)
 $draft=gh api -X POST ('repos/'+$repo+'/releases') --input $json|ConvertFrom-Json
 Check-Exit ('create-draft-'+$v)
 if(!$draft.id -or !$draft.draft -or !$draft.prerelease){throw ('Invalid draft '+$v)}
 $ids[$v]=[long]$draft.id
}
foreach($v in $versions){
 $dir=Join-Path $out $v
 $full=One $dir '*-full.nupkg'
 $setup=One $dir '*-Setup.exe'
 $files=@($full.FullName,$setup.FullName,($full.FullName+'.sha256'),($setup.FullName+'.sha256'),
   (Join-Path $dir 'releases.win-x64-beta.json'),(Join-Path $dir 'assets.win-x64-beta.json'),
   (Join-Path $dir 'RELEASES-win-x64-beta'),(Join-Path $out 'CHEXX-V25-GITHUB-QA-source.zip'),
   (Join-Path $out ('V25-GITHUB-QA-'+$v+'.patch')))
 $id=$ids[$v]
 $release=gh api ('repos/'+$repo+'/releases/'+$id)|ConvertFrom-Json
 Check-Exit ('get-draft-'+$v)
 if(!$release.draft){throw 'Draft prematurely published'}
 $urlBase=([string]$release.upload_url).Split('{')[0]
 if($urlBase -ne ('https://uploads.github.com/repos/'+$repo+'/releases/'+$id+'/assets')){throw 'Unapproved GitHub upload destination'}
 foreach($file in $files){
  if(!(Test-Path -LiteralPath $file -PathType Leaf)){throw ('Asset missing '+$file)}
  $n=[IO.Path]::GetFileName($file)
  $url=$urlBase+'?name='+[Uri]::EscapeDataString($n)
  $response=gh api -X POST $url --input $file --header 'Content-Type: application/octet-stream'|ConvertFrom-Json
  Check-Exit ('upload '+$n)
  if(!$response.id -or $response.state -ne 'uploaded' -or [long]$response.size -ne (Get-Item $file).Length){
   throw ('GitHub asset upload did not verify '+$n)
  }
  if($response.digest -and $response.digest -ne ('sha256:'+(Get-FileHash $file -Algorithm SHA256).Hash.ToLowerInvariant())){throw ('GitHub asset digest mismatch '+$n)}
  Write-Host ('UPLOADED_BETA='+$v+'/'+$n)
 }
 $verify=gh api ('repos/'+$repo+'/releases/'+$id)|ConvertFrom-Json
 Check-Exit ('verify-assets-'+$v)
 foreach($file in $files){
  $n=[IO.Path]::GetFileName($file)
  if(@($verify.assets|Where-Object{$_.name -eq $n -and $_.state -eq 'uploaded'}).Count -ne 1){throw ('Missing remote asset '+$n)}
 }
 Write-Host ('BETA_DRAFT_VERIFIED='+$v)
}
foreach($v in $versions){
 $id=$ids[$v]
 $p=Join-Path $out ('publish-'+$v+'.json')
 NoBom $p (@{draft=$false;prerelease=$true}|ConvertTo-Json -Compress)
 $published=gh api -X PATCH ('repos/'+$repo+'/releases/'+$id) --input $p|ConvertFrom-Json
 Check-Exit ('publish-'+$v)
 if($published.draft -or !$published.prerelease -or $published.tag_name -ne ($tagBase+$v)){throw ('Bad prerelease state '+$v)}
 Write-Host ('V25_QA_RELEASE_PUBLISHED='+$published.html_url)
}
$stableAfter=gh api ('repos/'+$repo+'/releases/latest')|ConvertFrom-Json
Check-Exit 'stable-latest-after'
if($stableAfter.tag_name -ne $oldLatest.tag_name -or $stableAfter.prerelease){throw 'Stable latest release was altered'}
Write-Host ('V25_GITHUB_QA_TWO_PRERELEASES_PASS_STABLE_UNCHANGED='+$stableAfter.tag_name)
