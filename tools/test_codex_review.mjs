import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const workflow = readFileSync(new URL('../.github/workflows/codex-review.yml', import.meta.url), 'utf8');
const script = workflow.split('          script: |\n')[1];
assert.ok(script, 'workflow must contain one inline, trusted reviewer script');
assert.equal(workflow.match(/          script: \|/g).length, 1);
assert.doesNotMatch(workflow, /actions\/checkout|\brun:|\brequire\(|\bimport\b|\beval\(|\$\{\{\s*secrets\.|contents:|id-token:|issues:|workflow_dispatch|workflow_run:|issue_comment:/);
assert.match(workflow, /pull_request_target:\n    branches: \[main\]\n    types: \[opened, reopened, ready_for_review, edited\]/);
assert.match(workflow, /pull-requests: write/);
assert.match(workflow, /cancel-in-progress: false/);
const groupTemplate = workflow.match(/^  group: (.+)$/m)[1].replace(/\$\{\{(.*?)\}\}/g, '${$1}');
const group = new Function('github', `return \`${groupTemplate}\`;`);
const groupFor = (action, changes = {}, number = 7) => group({ event: { action, changes, pull_request: { number } } });
assert.notEqual(groupFor('opened'), groupFor('edited'), 'ignored edits must not evict a pending review');
for (const action of ['reopened', 'ready_for_review']) assert.equal(groupFor(action), groupFor('opened'));
assert.equal(groupFor('edited', { base: {} }), groupFor('opened'), 'eligible requests must serialize together');
assert.notEqual(groupFor('opened', {}, 8), groupFor('opened'), 'PRs must have independent queues');
assert.match(workflow, /actions\/github-script@ed597411d8f924073f98dfc5c65a23a2325f34cd/);
assert.equal(workflow.match(/\buses:/g).length, 1, 'only the pinned metadata action may run');
assert.doesNotMatch(script, /\$\{\{/);
const run = new (Object.getPrototypeOf(async function () {}).constructor)(
  'github', 'context', 'core', script.replace(/^ {12}/gm, ''));
const sha = 'a'.repeat(40);
const ready = { state: 'open', draft: false, base: { ref: 'main' }, head: { sha } };
const marker = `<!-- codex-auto-review:7:${sha} -->`;
const bot = { login: 'github-actions[bot]', type: 'Bot' };

async function check({ action = 'opened', pr = ready, latest = pr, comments = [], changes, eventName = 'pull_request_target' } = {}) {
  const sent = [];
  let reads = 0;
  const github = {
    rest: {
      pulls: { get: async () => ({ data: reads++ ? latest : pr }) },
      issues: { listComments() {}, createComment: async payload => sent.push(payload) },
    },
    paginate: async () => comments,
  };
  await run(github, {
    repo: { owner: 'owner', repo: 'repo' }, eventName,
    payload: { action, number: 7, changes },
  }, { info() {} });
  return sent;
}

for (const action of ['opened', 'reopened', 'ready_for_review']) {
  assert.deepEqual(await check({ action }), [{ owner: 'owner', repo: 'repo', issue_number: 7, body: `@codex review\n\n${marker}` }]);
}
assert.equal((await check({ action: 'edited', changes: { base: {} } })).length, 1);
for (const pr of [{ ...ready, draft: true }, { ...ready, state: 'closed' }, { ...ready, base: { ref: 'develop' } }]) {
  assert.equal((await check({ pr })).length, 0);
  assert.equal((await check({ latest: pr })).length, 0);
}
for (const action of ['synchronize', 'converted_to_draft', 'edited']) {
  assert.equal((await check({ action })).length, 0);
}
assert.equal((await check({ eventName: 'issue_comment' })).length, 0);
assert.equal((await check({ latest: { ...ready, head: { sha: 'b'.repeat(40) } } })).length, 0);
assert.equal((await check({ comments: [{ user: bot, body: `@codex review\n\n${marker}` }] })).length, 0);
assert.equal((await check({ comments: [{ user: { login: 'attacker', type: 'User' }, body: marker }] })).length, 1);
assert.equal((await check({ comments: [{ user: bot, body: '<!-- codex-auto-review:7:old -->' }] })).length, 1);
console.log('Codex review scope, stale-state, and duplicate-request tests passed.');
