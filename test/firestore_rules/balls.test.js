const { initializeTestEnvironment, assertSucceeds, assertFails } = require('@firebase/rules-unit-testing');
const { doc, setDoc, getDoc, updateDoc, deleteDoc, serverTimestamp, collection, getDocs } = require('firebase/firestore');
const fs = require('fs');

const results = [];
async function check(name, fn) {
  try { await fn(); results.push(['PASS', name]); } catch (e) { results.push(['FAIL', name + ' :: ' + String(e.message).split('\n')[0]]); }
}

(async () => {
  const env = await initializeTestEnvironment({
    projectId: 'demo-flow-test',
    firestore: { rules: fs.readFileSync(process.env.RULES_FILE, 'utf8'), host: '127.0.0.1', port: Number(process.env.FIRESTORE_EMULATOR_HOST.split(':')[1]) },
  });
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, 'admins/admin1'), { role: 'owner' });
    await setDoc(doc(db, 'matches/m1'), { status: 'live', sport: 'cricket' });
  });
  const admin = env.authenticatedContext('admin1').firestore();
  const viewer = env.authenticatedContext('viewer1').firestore();
  const anon = env.unauthenticatedContext().firestore();

  const ball = (over = {}) => ({
    seq: 1, innings: 0, kind: 'ball', delivery: 'legal', runType: 'bat', runs: 4, boundary: 'four',
    wicket: null, completedRunsOverride: null, bowlerId: 'b1', acknowledgedFlags: [],
    createdAt: serverTimestamp(), ...over,
  });
  const ballRef = (db, id = 'b000001') => doc(db, 'matches/m1/balls', id);

  await check('admin can append a valid ball', () => assertSucceeds(setDoc(ballRef(admin), ball())));
  await check('anyone can read balls (viewers)', () => assertSucceeds(getDoc(ballRef(anon))));
  await check('anyone can list balls', () => assertSucceeds(getDocs(collection(anon, 'matches/m1/balls'))));
  await check('viewer cannot write a ball', () => assertFails(setDoc(ballRef(viewer, 'b000002'), ball({ seq: 2 }))));
  await check('anonymous cannot write a ball', () => assertFails(setDoc(ballRef(anon, 'b000003'), ball({ seq: 3 }))));
  await check('viewer cannot delete a ball', () => assertFails(deleteDoc(ballRef(viewer))));
  await check('viewer cannot edit a ball', () => assertFails(updateDoc(ballRef(viewer), { runs: 6 })));
  await check('create needs a real server timestamp', () =>
    assertFails(setDoc(ballRef(admin, 'b000004'), ball({ seq: 4, createdAt: new Date(2020, 1, 1) }))));
  await check('rejects an unknown delivery', () => assertFails(setDoc(ballRef(admin, 'b000005'), ball({ seq: 5, delivery: 'foo' }))));
  await check('rejects an unknown run type', () => assertFails(setDoc(ballRef(admin, 'b000006'), ball({ seq: 6, runType: 'x' }))));
  await check('rejects absurd runs', () => assertFails(setDoc(ballRef(admin, 'b000007'), ball({ seq: 7, runs: 99 }))));
  await check('rejects negative runs', () => assertFails(setDoc(ballRef(admin, 'b000008'), ball({ seq: 8, runs: -1 }))));
  await check('rejects a bad innings number', () => assertFails(setDoc(ballRef(admin, 'b000009'), ball({ seq: 9, innings: 7 }))));
  await check('rejects a bad kind', () => assertFails(setDoc(ballRef(admin, 'b000010'), ball({ seq: 10, kind: 'zzz' }))));
  await check('rejects seq 0 / non-int seq', () => assertFails(setDoc(ballRef(admin, 'b000011'), ball({ seq: 0 }))));
  await check('rejects an unknown wicket kind', () =>
    assertFails(setDoc(ballRef(admin, 'b000012'), ball({ seq: 12, wicket: { kind: 'wizard', outBatterId: 'a1' } }))));
  await check('accepts a real wicket', () =>
    assertSucceeds(setDoc(ballRef(admin, 'b000013'), ball({ seq: 13, wicket: { kind: 'runOut', outBatterId: 'a1', newBatterId: 'a3', newBatterEnd: 'onStrike', crossed: false, fielderId: null } }))));
  await check('accepts control events (swap strike)', () =>
    assertSucceeds(setDoc(ballRef(admin, 'b000014'), { seq: 14, innings: 0, kind: 'swapStrike', delivery: 'legal', runType: 'none', runs: 0, boundary: 'none', createdAt: serverTimestamp() })));
  await check('admin can edit a ball (no timestamp needed)', () =>
    assertSucceeds(updateDoc(ballRef(admin), { runs: 1, boundary: 'none', delivery: 'legal', runType: 'bat', kind: 'ball', seq: 1, innings: 0 })));
  await check('an edit that makes it invalid is refused', () => assertFails(updateDoc(ballRef(admin), { delivery: 'nope' })));
  await check('admin can accept flags (field update)', () => assertSucceeds(updateDoc(ballRef(admin), { acknowledgedFlags: ['bowlerChangedMidOver'] })));
  await check('admin can delete a ball (undo)', () => assertSucceeds(deleteDoc(ballRef(admin, 'b000013'))));

  // Audit trail
  const edit = (db, id = 'e1') => doc(db, 'matches/m1/ballEdits', id);
  const auditBody = (over = {}) => ({ action: 'edit', ballSeq: 1, before: { runs: 4 }, after: { runs: 1 }, editedBy: 'admin1', editedAt: serverTimestamp(), ...over });
  await check('admin can write an audit entry', () => assertSucceeds(setDoc(edit(admin), auditBody())));
  await check('audit needs a server timestamp', () => assertFails(setDoc(edit(admin, 'e2'), auditBody({ editedAt: new Date(2020, 1, 1) }))));
  await check('viewer cannot read the audit trail', () => assertFails(getDoc(edit(viewer))));
  await check('anonymous cannot read the audit trail', () => assertFails(getDoc(edit(anon))));
  await check('admin can read the audit trail', () => assertSucceeds(getDoc(edit(admin))));
  await check('audit entries are never updated', () => assertFails(updateDoc(edit(admin), { action: 'x' })));
  await check('audit entries cannot be deleted while the match exists', () => assertFails(deleteDoc(edit(admin))));
  await check('viewer cannot write audit', () => assertFails(setDoc(edit(viewer, 'e3'), auditBody())));

  // The match doc: admin writes cached summary fields; viewers still limited.
  await check('admin can write the cached summary on the match', () =>
    assertSucceeds(updateDoc(doc(admin, 'matches/m1'), { innings: [{ batting: 'A', runs: 4 }], live: { strikerId: 'a1' }, summaryText: 'x', scoreA: 4, scoreB: 0, lastCommentaryText: 'hi', lastCommentaryAt: serverTimestamp(), resultText: null })));
  await check('viewer cannot write the match summary', () => assertFails(updateDoc(doc(viewer, 'matches/m1'), { summaryText: 'hacked', scoreA: 99 })));
  await check('viewer can still react (unchanged)', () => assertSucceeds(updateDoc(doc(viewer, 'matches/m1'), { reactionCounts: { fire: 1 } })));
  await check('viewer reaction with extra key still refused (unchanged)', () => assertFails(updateDoc(doc(viewer, 'matches/m1'), { reactionCounts: { fire: 1, evil: 1 } })));
  await check('viewer can still predict (unchanged)', () => assertSucceeds(updateDoc(doc(viewer, 'matches/m1'), { predictionCounts: { teamA: 1 } })));

  // Deleting the match then its audit trail (the reset / delete-match path)
  await check('admin deletes the match', () => assertSucceeds(deleteDoc(doc(admin, 'matches/m1'))));
  await check('audit entries can be cleared once the match is gone', () => assertSucceeds(deleteDoc(edit(admin))));
  await check('balls can still be deleted after the match is gone', () => assertSucceeds(deleteDoc(ballRef(admin))));

  await env.cleanup();
  let fail = 0;
  for (const [s, n] of results) { console.log(s, n); if (s === 'FAIL') fail++; }
  console.log(`\n${results.length - fail}/${results.length} passed`);
  process.exit(fail ? 1 : 0);
})();
