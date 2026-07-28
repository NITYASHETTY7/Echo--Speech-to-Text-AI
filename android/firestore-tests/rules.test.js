// Rules verification for Echo firestore.rules
// Run via: firebase emulators:exec --only firestore --project demo-echo "node rules.test.js"

const fs = require('fs');
const path = require('path');
const {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
} = require('@firebase/rules-unit-testing');
const {
  doc, getDoc, setDoc, deleteDoc,
  collection, query, where, getDocs,
} = require('firebase/firestore');

const UID_A = 'userAAA';
const UID_B = 'userBBB';

let pass = 0, fail = 0;
const results = [];

async function check(name, promise) {
  try {
    await promise;
    pass++; results.push(`  PASS  ${name}`);
  } catch (e) {
    fail++; results.push(`  FAIL  ${name}\n          ${e.message.split('\n')[0]}`);
  }
}

// ── Valid document payloads, mirroring SyncManagerImpl exactly ──────────────
const transcript = (owner, over = {}) => ({
  ownerUid: owner, id: 'tx1', text: 'hello world',
  timestamp: 1700000000000, model: 'whisper-large-v3-turbo',
  audioPath: null,                 // nullable in Kotlin
  userId: owner, syncVersion: 1, updatedAt: 1700000000000, deleted: false,
  ...over,
});

const version = (owner, over = {}) => ({
  ownerUid: owner, id: 'v1', transcriptId: 'tx1', versionType: 'Original',
  createdAt: 1700000000000, provider: 'Groq', model: 'llama-3.3-70b-versatile',
  content: 'hello world', metadataJson: '{}',
  syncVersion: 1, updatedAt: 1700000000000, deleted: false,
  ...over,
});

const aiJob = (owner, over = {}) => ({
  ownerUid: owner, id: 'j1', transcriptId: 'tx1', versionType: 'GrammarCorrected',
  promptTemplateId: null,          // nullable
  provider: 'Groq', model: 'llama-3.3-70b-versatile', status: 'COMPLETED',
  retryCount: 0, createdAt: 1700000000000,
  startedAt: null, completedAt: null, processingTimeMs: null, errorMessage: null,
  syncVersion: 1, updatedAt: 1700000000000, deleted: false,
  ...over,
});

const prefs = (owner, over = {}) => ({
  ownerUid: owner, grammarCorrectionEnabled: false,
  autoEnhanceAfterTranscription: false, defaultRewriteStyle: 'professional',
  defaultAiProvider: 'groq', language: 'en', theme: 'system',
  updatedAt: 1700000000000,
  ...over,
});

const user = (uid, over = {}) => ({
  uid, displayName: 'Nitya', email: 'n@example.com', photoUrl: null,
  lastLogin: 1700000000000, createdAt: 1699000000000,
  ...over,
});

(async () => {
  const testEnv = await initializeTestEnvironment({
    projectId: 'demo-echo',
    firestore: {
      rules: fs.readFileSync(path.resolve(__dirname, '..', 'firestore.rules'), 'utf8'),
      host: '127.0.0.1', port: 8080,
    },
  });

  const a = testEnv.authenticatedContext(UID_A).firestore();
  const b = testEnv.authenticatedContext(UID_B).firestore();
  const anon = testEnv.unauthenticatedContext().firestore();

  // Seed data bypassing rules so read/update tests have something to hit.
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, 'transcripts/tx_a'), transcript(UID_A));
    await setDoc(doc(db, 'transcripts/tx_b'), transcript(UID_B, { id: 'tx_b' }));
    await setDoc(doc(db, 'transcriptVersions/v_a'), version(UID_A));
    await setDoc(doc(db, 'transcriptVersions/v_b'), version(UID_B, { id: 'v_b' }));
    await setDoc(doc(db, 'aiJobs/j_a'), aiJob(UID_A));
    await setDoc(doc(db, 'userPreferences/' + UID_A), prefs(UID_A));
    await setDoc(doc(db, 'users/' + UID_A), user(UID_A));
  });

  results.push('\n── transcripts ──');
  await check('owner create',
    assertSucceeds(setDoc(doc(a, 'transcripts/new_a'), transcript(UID_A, { id: 'new_a' }), { merge: true })));
  await check('owner create with non-null audioPath',
    assertSucceeds(setDoc(doc(a, 'transcripts/new_a2'), transcript(UID_A, { id: 'new_a2', audioPath: '/data/x.m4a' }), { merge: true })));
  await check('create with FOREIGN ownerUid denied',
    assertFails(setDoc(doc(a, 'transcripts/steal'), transcript(UID_B, { id: 'steal' }), { merge: true })));
  await check('unauthenticated create denied',
    assertFails(setDoc(doc(anon, 'transcripts/anon'), transcript(UID_A, { id: 'anon' }), { merge: true })));
  await check('owner get',
    assertSucceeds(getDoc(doc(a, 'transcripts/tx_a'))));
  await check('other-user get denied',
    assertFails(getDoc(doc(b, 'transcripts/tx_a'))));
  await check('LIST with ownerUid filter (restoreRecentHistory shape)',
    assertSucceeds(getDocs(query(collection(a, 'transcripts'), where('ownerUid', '==', UID_A)))));
  await check('LIST without ownerUid filter denied',
    assertFails(getDocs(query(collection(a, 'transcripts')))));
  await check('LIST filtered to ANOTHER user denied',
    assertFails(getDocs(query(collection(a, 'transcripts'), where('ownerUid', '==', UID_B)))));
  await check('owner soft-delete update (deleted=true)',
    assertSucceeds(setDoc(doc(a, 'transcripts/tx_a'), transcript(UID_A, { deleted: true, updatedAt: 1700000009999 }), { merge: true })));
  await check('update hijacking ownerUid denied',
    assertFails(setDoc(doc(a, 'transcripts/tx_a'), transcript(UID_B), { merge: true })));
  await check('other-user update denied',
    assertFails(setDoc(doc(b, 'transcripts/tx_a'), transcript(UID_A), { merge: true })));
  await check('wrong type (timestamp as string) denied',
    assertFails(setDoc(doc(a, 'transcripts/badtype'), transcript(UID_A, { id: 'badtype', timestamp: 'nope' }), { merge: true })));
  await check('missing required field (text) denied',
    assertFails(setDoc(doc(a, 'transcripts/nofield'), (() => { const t = transcript(UID_A, { id: 'nofield' }); delete t.text; return t; })(), { merge: true })));
  await check('HARD delete denied',
    assertFails(deleteDoc(doc(a, 'transcripts/tx_a'))));

  results.push('\n── transcriptVersions ──');
  await check('owner create',
    assertSucceeds(setDoc(doc(a, 'transcriptVersions/nv_a'), version(UID_A, { id: 'nv_a' }), { merge: true })));
  await check('LIST with ownerUid filter',
    assertSucceeds(getDocs(query(collection(a, 'transcriptVersions'), where('ownerUid', '==', UID_A)))));
  await check('LIST by transcriptId only denied (old broken query shape)',
    assertFails(getDocs(query(collection(a, 'transcriptVersions'), where('transcriptId', '==', 'tx1')))));
  await check('other-user get denied',
    assertFails(getDoc(doc(b, 'transcriptVersions/v_a'))));
  await check('create with FOREIGN ownerUid denied',
    assertFails(setDoc(doc(a, 'transcriptVersions/steal'), version(UID_B, { id: 'steal' }), { merge: true })));
  await check('HARD delete denied',
    assertFails(deleteDoc(doc(a, 'transcriptVersions/v_a'))));

  results.push('\n── aiJobs ──');
  await check('owner create with all-null optionals',
    assertSucceeds(setDoc(doc(a, 'aiJobs/nj_a'), aiJob(UID_A, { id: 'nj_a' }), { merge: true })));
  await check('owner create with populated optionals',
    assertSucceeds(setDoc(doc(a, 'aiJobs/nj_a2'), aiJob(UID_A, {
      id: 'nj_a2', promptTemplateId: 'professional', startedAt: 1700000000001,
      completedAt: 1700000000900, processingTimeMs: 899, errorMessage: 'none',
    }), { merge: true })));
  await check('owner get',
    assertSucceeds(getDoc(doc(a, 'aiJobs/j_a'))));
  await check('LIST denied (write-only collection)',
    assertFails(getDocs(query(collection(a, 'aiJobs'), where('ownerUid', '==', UID_A)))));
  await check('create with FOREIGN ownerUid denied',
    assertFails(setDoc(doc(a, 'aiJobs/steal'), aiJob(UID_B, { id: 'steal' }), { merge: true })));

  results.push('\n── userPreferences ──');
  await check('self create/merge',
    assertSucceeds(setDoc(doc(a, 'userPreferences/' + UID_A), prefs(UID_A), { merge: true })));
  await check('self get',
    assertSucceeds(getDoc(doc(a, 'userPreferences/' + UID_A))));
  await check('write to ANOTHER uid path denied',
    assertFails(setDoc(doc(a, 'userPreferences/' + UID_B), prefs(UID_B), { merge: true })));
  await check('ownerUid not matching path denied',
    assertFails(setDoc(doc(a, 'userPreferences/' + UID_A), prefs(UID_B), { merge: true })));
  await check('other-user get denied',
    assertFails(getDoc(doc(b, 'userPreferences/' + UID_A))));
  await check('LIST denied',
    assertFails(getDocs(query(collection(a, 'userPreferences')))));

  results.push('\n── users ──');
  await check('self get',
    assertSucceeds(getDoc(doc(a, 'users/' + UID_A))));
  await check('self create',
    assertSucceeds(setDoc(doc(b, 'users/' + UID_B), user(UID_B))));
  await check('self merge update',
    assertSucceeds(setDoc(doc(a, 'users/' + UID_A), user(UID_A, { lastLogin: 1700000099999 }), { merge: true })));
  await check('uid field mismatching path denied',
    assertFails(setDoc(doc(a, 'users/' + UID_A), user(UID_B), { merge: true })));
  await check('other-user get denied',
    assertFails(getDoc(doc(b, 'users/' + UID_A))));
  await check('LIST (user directory enumeration) denied',
    assertFails(getDocs(query(collection(a, 'users')))));
  await check('delete denied',
    assertFails(deleteDoc(doc(a, 'users/' + UID_A))));

  results.push('\n── default deny ──');
  await check('undeclared collection write denied',
    assertFails(setDoc(doc(a, 'randomCollection/x'), { ownerUid: UID_A })));

  console.log(results.join('\n'));
  console.log(`\n════ ${pass} passed, ${fail} failed ════`);
  await testEnv.cleanup();
  process.exit(fail === 0 ? 0 : 1);
})();
