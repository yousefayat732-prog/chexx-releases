// Temporary GitHub Windows runner only: exercise real GithubSource 0.9.1 -> 0.9.2.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import {createRequire} from 'node:module';
import {connectCDP} from '../../source/scripts/cdp-qa-helpers.mjs';
const require=createRequire(import.meta.url);
const {DataStore}=require('../../source/electron/data-store.cjs');
const appData=process.env.APPDATA;
if(!appData)throw Error('Windows APPDATA unavailable');
const dir=path.join(appData,'chexx-academy-V25-GITHUB-QA');
const baselineFile=path.resolve('v25-github-qa-baseline.json');
const store=new DataStore(dir);
const mode=process.argv[2];
if(mode==='seed'){
 if(store.exists())throw Error('GitHub test runner profile is not isolated/empty');
 const sample={schemaVersion:2,xp:4237,profileName:'GITHUB-TEST-ONLY',completed:['1-1','1-2'],
  practiced:['1-1'],wins:{qa_bot:3},losses:1,draws:0,
  awardedKeys:['QA_ONLY'],board:'classic',pieces:'cburnett',unlockedBoards:['classic'],
  unlockedPieces:['cburnett'],soundTheme:'metal',soundVolume:0.37,
  gameHistory:[],botStats:{qa_bot:{wins:3,losses:1}},sync:{version:1,pending:[{id:'githubsource-pending-qa',type:'qa'}],lastSyncedAt:null},
  qaMarker:'GHQA_E2E_NEVER_REAL_PROFILE'};
 store.save(sample);
 const baseline=store.load();
 assert.equal(baseline.xp,4237);
 fs.writeFileSync(baselineFile,JSON.stringify(baseline,null,2));
 console.log('GITHUB_QA_E2E_TEST_PROFILE_CREATED='+dir);
}else if(mode==='update'){
 const client=await connectCDP(9797);
 try{
  const status=await client.evaluate('window.chexx.status()');
  assert.equal(status.version,'0.9.1');
  assert.ok(status.dataDir.endsWith('chexx-academy-V25-GITHUB-QA'));
  const update=await client.evaluate('window.chexx.checkUpdate()');
  console.log('GITHUB_QA_REMOTE_UPDATE_CHECK='+JSON.stringify(update));
  assert.equal(update.available,true);
  assert.equal(update.targetVersion,'0.9.2');
  assert.ok(update.downloadSize>10000000);
  const backup=await client.evaluate('window.chexx.prepareUpdateBackup()');
  assert.equal(backup.verified,true);
  assert.equal(backup.targetVersion,'0.9.2');
  console.log('GITHUB_QA_BACKUP_ID='+backup.id);
  const dl=await client.evaluate('window.chexx.downloadUpdate()');
  assert.equal(dl.verifiedBy,'velopack');
  assert.ok(dl.bytes>10000000);
  console.log('GITHUB_QA_0_9_2_DOWNLOADED_BYTES='+dl.bytes);
  // The chess UI deterministically adds level-earned unlocks after reading a new profile.
  // Snapshot the actual persisted state immediately before the update, not the raw
  // artificial seed, so additive unlocks are not mislabeled as updater corruption.
  const profileBefore=await client.evaluate('window.chexx.load()');
  assert.equal(profileBefore.qaMarker,'GHQA_E2E_NEVER_REAL_PROFILE');
  fs.writeFileSync(baselineFile,JSON.stringify(profileBefore,null,2));
  console.log('GITHUB_QA_PREUPDATE_PROFILE_SNAPSHOT='+JSON.stringify({
    xp:profileBefore.xp,unlockedBoards:profileBefore.unlockedBoards?.length,
    unlockedPieces:profileBefore.unlockedPieces?.length,
    pending:profileBefore.sync?.pending?.length
  }));
  const dispatched=await client.evaluate("(()=>{window._qaStatus='PENDING';window.chexx.installUpdate(true).then(()=>window._qaStatus='SCHEDULED').catch(e=>{window._qaStatus='ERROR: '+e.message;console.error(window._qaStatus)});return true})()");
  assert.equal(dispatched,true);
  console.log('GITHUB_QA_APPLY_REQUEST_DISPATCHED');
 } finally {client.close()}
}else if(mode==='verify'){
 const baseline=JSON.parse(fs.readFileSync(baselineFile,'utf8'));
 const current=store.load();
 const report=JSON.parse(fs.readFileSync(path.join(dir,'velopack-last-update-report.json'),'utf8'));
 assert.equal(report.state,'PASS');
 assert.equal(report.oldVersion,'0.9.1');
 assert.equal(report.installedVersion,'0.9.2');
 assert.deepEqual(report.differences,[]);
 const keys=['xp','profileName','completed','practiced','wins','losses','draws','awardedKeys','board','pieces','unlockedBoards','unlockedPieces','soundTheme','soundVolume','gameHistory','botStats','sync','qaMarker'];
 for(const k of keys)assert.deepEqual(current[k],baseline[k],'Diverged field '+k);
 console.log('GITHUBSOURCE_REAL_0_9_1_TO_0_9_2_PASS '+keys.length+' PROFILE FIELDS, NO MISMATCH');
}else throw Error('Specify seed, update or verify mode');
