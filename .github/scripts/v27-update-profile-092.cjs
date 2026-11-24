'use strict';
// CI-only isolated Windows runner. Never run against a human's computer/profile.
const fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto');
const src=path.resolve('source');
const {DataStore}=require(path.join(src,'electron','data-store.cjs'));
const {UpdateService,createBaseline,baselineDiff}=require(path.join(src,'electron','update-service.cjs'));
const {BackupInstallGuard}=require(path.join(src,'electron','backup-install-guard.cjs'));
const dir=path.join(process.env.APPDATA,'chexx-academy');
const proof=path.resolve('v27-isolated-upgrade-profile-baseline.json');
const store=new DataStore(dir);
const mode=process.argv[2],installer=process.argv[3];
if(!process.env.GITHUB_ACTIONS||process.env.RUNNER_OS!=='Windows')throw Error('Only disposable GitHub Windows runner allowed');
if(mode==='seed'){
 if(store.exists())throw Error('CI profile already present; refusing overwrite');
 const profile={
  schemaVersion:2,xp:4237,level:8,profileName:'ISOLATED-CI-TEST-ONLY',
  completed:['1-1','1-2'],practiced:['1-1'],awardedKeys:['qa-marker'],wins:{bot:3},
  losses:1,draws:1,gameHistory:[],board:'classic',pieces:'cburnett',
  unlockedBoards:['classic'],unlockedPieces:['cburnett'],soundTheme:'metal',
  soundVolume:0.36,lessonPosition:2,botStatistics:{bot:{wins:3,losses:1}},
  sync:{version:1,pending:[{id:'pending-offline-ci',type:'qa'}],lastSyncedAt:null},
  qaMarker:'DO_NOT_USE_WITH_REAL_CHEXX_PROFILE'
 };
 store.save(profile);
 const again=store.load();
 if(again.qaMarker!==profile.qaMarker||again.xp!==profile.xp)throw Error('Test profile seed mismatch');
 console.log('CI_ISOLATED_PROFILE_SEED_PASS='+JSON.stringify({dir,xp:again.xp,pending:again.sync.pending.length}));
}else if(mode==='arm'){
 if(!installer||!fs.existsSync(installer))throw Error('Candidate NSIS installer absent');
 const stat=fs.statSync(installer),sha=crypto.createHash('sha256').update(fs.readFileSync(installer)).digest('hex');
 const test=new UpdateService({dataDir:dir,version:'0.9.1',profileStore:store,channel:{owner:'yousefayat732-prog',repo:'chexx-releases'}});
 test.candidate={version:'0.9.2',bytes:stat.size,sha256:sha};
 test.downloaded={path:installer,version:'0.9.2',sha256:sha,bytes:stat.size};
 const guard=new BackupInstallGuard({profileStore:store,getUpdater:()=>test});
 const receipt=guard.createBackup();
 if(!receipt.verified||receipt.targetVersion!=='0.9.2')throw Error('Profile backup not verified');
 guard.verifyBeforeInstall(true);
 const pending=test.prepareInstall();
 if(pending.targetVersion!=='0.9.2'||!pending.backupId)throw Error('Profile pending task not armed');
 const baseline=store.load();
 fs.writeFileSync(proof,JSON.stringify(baseline,null,2),{flag:'wx'});
 console.log('CI_NSIS_UPGRADE_BACKUP_ARMED='+JSON.stringify({id:receipt.id,from:'0.9.1',to:'0.9.2',sha256:sha,bytes:stat.size}));
}else if(mode==='verify'){
 if(!fs.existsSync(proof))throw Error('No baseline proof');
 const baseline=JSON.parse(fs.readFileSync(proof,'utf8'));
 const after=store.load();
 const diff=baselineDiff(createBaseline(baseline),after);
 if(diff.length)throw Error('CI_USER_DATA_MISMATCH='+JSON.stringify(diff));
 const svc=new UpdateService({dataDir:dir,version:'0.9.2',profileStore:store,channel:null});
 const result=svc.verifyAfterRestart('0.9.2',after);
 if(result.state!=='PASS'||result.differences.length)throw Error('NSIS upgrade verification not PASS: '+JSON.stringify(result));
 if(store.load().qaMarker!=='DO_NOT_USE_WITH_REAL_CHEXX_PROFILE'||store.load().xp!==4237)
  throw Error('Game profile data lost');
 console.log('V27_NSIS_0_9_1_TO_0_9_2_ISOLATED_INSTALL_AND_PROFILE_PASS='+JSON.stringify({
  from:'0.9.1',to:'0.9.2',profileFields:Object.keys(baseline).length,
  xp:after.xp,offlineQueue:after.sync.pending.length,differences:result.differences.length,
  backupId:result.backupId
 }));
}else throw Error('Use seed|arm|verify');
