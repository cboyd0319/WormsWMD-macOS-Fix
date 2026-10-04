import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const workflow = readFileSync(new URL('../.github/workflows/codex-review.yml', import.meta.url), 'utf8');
const script = workflow.split('          script: |\n')[1];
assert.ok(script, 'workflow must contain one inline, trusted reviewer script');
assert.equal(workflow.match(/          script: \|/g).length, 1);
const credentialLine = '          github-token: ${{ secrets.CODEX_REVIEW_TOKEN }}';
assert.equal(workflow.split(credentialLine).length, 2, 'only the scoped user credential may be consumed');
assert.doesNotMatch(workflow.replace(credentialLine, ''), /actions\/checkout|\brun:|\brequire\(|\bimport\b|\beval\(|\bsecrets\b|contents:|id-token:|issues:|workflow_dispatch|issue_comment:/);
assert.match(workflow, /pull_request_target:\n    branches: \[main\]\n    types: \[opened, reopened, ready_for_review, edited\]/);
assert.match(workflow, /workflow_run:\n    workflows: \[CI\]\n    types: \[completed\]/);
assert.match(readFileSync(new URL('../.github/workflows/ci.yml', import.meta.url), 'utf8'), /^name: CI$/m);
assert.match(workflow, /    permissions: \{\}/);
assert.doesNotMatch(workflow, /pull-requests: write/);
assert.match(workflow, /cancel-in-progress: false/);
assert.match(workflow, /^  queue: max$/m, 'ignored CI completions must not evict pending review requests');
const groupTemplate = workflow.match(/^  group: (.+)$/m)[1].replace(/\$\{\{(.*?)\}\}/g, '${$1}');
const group = new Function('github', `return \`${groupTemplate}\`;`);
const groupFor = (action, changes = {}, number = 7) => group({ event_name: 'pull_request_target', event: { action, changes, pull_request: { number } } });
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
const reviewer = { id: 123, login: 'connected-reviewer', type: 'User' };
const bot = { id: 456, login: 'github-actions[bot]', type: 'Bot' };

async function check({ action = 'opened', pr = ready, latest = pr, comments = [], changes, eventName = 'pull_request_target', identity = reviewer, upstream } = {}) {
  const sent = [];
  let reads = 0;
  const github = {
    rest: {
      users: { getAuthenticated: async () => ({ data: identity }) },
      pulls: { get: async () => ({ data: reads++ ? latest : pr }) },
      issues: { listComments() {}, createComment: async payload => sent.push(payload) },
    },
    paginate: async () => comments,
  };
  await run(github, {
    repo: { owner: 'owner', repo: 'repo' }, eventName,
    payload: { action, number: 7, changes, workflow_run: upstream },
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
const changedHead = { ...ready, head: { sha: 'b'.repeat(40) } };
const changedBody = `@codex review\n\n<!-- codex-auto-review:7:${changedHead.head.sha} -->`;
for (const comments of [[], [{ user: reviewer, body: marker }]]) {
  assert.deepEqual(await check({ latest: changedHead, comments }),
    [{ owner: 'owner', repo: 'repo', issue_number: 7, body: changedBody }],
    'a push during metadata lookup must not lose the initial ready-PR review');
}
assert.equal((await check({ latest: changedHead, comments: [{ user: reviewer, body: changedBody }] })).length, 0);
await assert.rejects(check({ pr: { ...ready, head: { sha: 'invalid' } } }), /Invalid PR revision/);
assert.equal((await check({ comments: [{ user: reviewer, body: `@codex review\n\n${marker}` }] })).length, 0);
assert.equal((await check({ comments: [{ user: { ...reviewer, login: 'renamed-user' }, body: marker }] })).length, 0, 'deduplication must use the stable authenticated user ID');
assert.equal((await check({ comments: [{ user: bot, body: marker }] })).length, 1, 'ignored Actions-bot requests must not suppress a real user request');
await assert.rejects(check({ identity: bot }), /connected to Codex/);
await assert.rejects(check({ identity: { ...reviewer, id: undefined } }), /connected to Codex/);
assert.equal((await check({ comments: [{ user: { login: 'attacker', type: 'User' }, body: marker }] })).length, 1);
assert.equal((await check({ comments: [{ user: bot, body: '<!-- codex-auto-review:7:old -->' }] })).length, 1);
const upstream = {
  name: 'CI', event: 'pull_request', status: 'completed', actor: { id: 49699333, login: 'dependabot[bot]' },
  head_sha: sha,
  head_repository: { full_name: 'owner/repo' }, pull_requests: [{ number: 7, base: { ref: 'main' } }],
};
const jobExpression = workflow.match(/    if: >-\n([\s\S]*?)    runs-on:/)[1].trim();
const eligibleJob = new Function('github', `return Boolean(${jobExpression});`);
const prEvent = { action: 'opened', sender: { id: 123 }, pull_request: { ...ready, number: 7, user: { login: 'owner' } } };
assert.equal(eligibleJob({ event_name: 'pull_request_target', actor_id: '123', event: prEvent }), true);
const botEvent = { ...prEvent, sender: { id: 49699333 }, pull_request: { ...prEvent.pull_request, user: { id: 49699333, login: 'dependabot[bot]' } } };
assert.equal(eligibleJob({ event_name: 'pull_request_target', actor_id: '49699333', event: botEvent }), false, 'restricted Dependabot triggers must not consume the credential');
assert.equal(eligibleJob({ event_name: 'pull_request_target', actor_id: '123', event: { ...botEvent, sender: { id: 123 }, action: 'ready_for_review' } }), true);
assert.equal(eligibleJob({ event_name: 'pull_request_target', actor_id: '123', event: { ...prEvent, action: 'edited', changes: {} } }), false);
assert.equal(eligibleJob({ event_name: 'workflow_run', event: { workflow_run: upstream } }), true);
assert.equal(eligibleJob({ event_name: 'workflow_run', event: { workflow_run: { ...upstream, actor: { login: 'owner' } } } }), false);
const dependabotPR = { ...ready, user: { id: 49699333, login: 'dependabot[bot]' }, head: { sha, repo: { full_name: 'owner/repo' } } };
const fallback = { eventName: 'workflow_run', action: 'completed', upstream, pr: dependabotPR };
assert.equal((await check(fallback)).length, 1, 'Dependabot must receive reviews despite its restricted trigger credentials');
const newerDependabotPR = { ...dependabotPR, head: { ...dependabotPR.head, sha: 'b'.repeat(40) } };
assert.equal((await check({ ...fallback, pr: newerDependabotPR })).length, 0, 'old CI runs must not request newer revisions');
assert.equal((await check({ ...fallback, latest: newerDependabotPR })).length, 0, 'a push during lookup must wait for its own CI completion');
assert.equal((await check({ ...fallback, pr: newerDependabotPR, upstream: { ...upstream, head_sha: newerDependabotPR.head.sha } })).length, 1);
assert.equal((await check({ ...fallback, upstream: { ...upstream, head_sha: 'old', pull_requests: [{ ...upstream.pull_requests[0], head: { sha } }] } })).length, 0, 'mutable PR association metadata cannot replace the immutable run SHA');
assert.equal((await check({ ...fallback, comments: [{ user: reviewer, body: marker }] })).length, 0);
for (const pr of [ready, { ...dependabotPR, draft: true }, { ...dependabotPR, state: 'closed' }, { ...dependabotPR, base: { ref: 'develop' } }, { ...dependabotPR, head: { sha, repo: { full_name: 'fork/repo' } } }]) {
  assert.equal((await check({ ...fallback, pr })).length, 0);
  assert.equal((await check({ ...fallback, latest: pr })).length, 0);
}
for (const change of [
  { actor: { id: 999, login: 'dependabot[bot]' } }, { name: 'Untrusted workflow' }, { event: 'push' }, { status: 'in_progress' }, { actor: { login: 'attacker' } },
  { head_repository: { full_name: 'fork/repo' } }, { pull_requests: [] },
  { pull_requests: [{ number: 7 }, { number: 8 }] }, { pull_requests: [{ number: 7, base: { ref: 'develop' } }] },
]) assert.equal((await check({ ...fallback, upstream: { ...upstream, ...change } })).length, 0);
assert.equal(group({ event_name: 'workflow_run', event: { pull_request: {}, workflow_run: upstream } }), groupFor('opened'), 'both triggers must share one review queue');
console.log('Codex review scope, stale-state, and duplicate-request tests passed.');
