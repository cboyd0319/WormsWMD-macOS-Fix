import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const workflow = readFileSync(new URL('../.github/workflows/ci.yml', import.meta.url), 'utf8');
import reuseValidation from './ci_reuse_validation.cjs';
assert.ok(workflow.includes("return await require('./tools/ci_reuse_validation.cjs')({ github, context, core });"));
const sha = n => String(n).repeat(40);
const current = sha(1), head = sha(2), base = sha(3), tested = sha(4), tree = sha(5);
const now = new Date().toISOString();
const candidate = {
  id: 7, workflow_id: 8, path: '.github/workflows/ci.yml', event: 'pull_request',
  status: 'completed', conclusion: 'success', head_sha: head,
  repository: { id: 9 }, head_repository: { id: 9 },
  updated_at: now,
};
const checkout = { name: `Checkout ${tested}`, status: 'completed', conclusion: 'success' };
const job = name => ({ name, status: 'completed', conclusion: 'success', completed_at: now, steps: [checkout] });
async function check(options = {}) {
  const context = {
    eventName: 'push', ref: 'refs/heads/main', sha: current, runId: 10,
    repo: { owner: 'owner', repo: 'repo' }, payload: { repository: { id: 9 } },
    ...options.context,
  };
  const commits = {
    [current]: { sha: current, tree: { sha: tree }, parents: [{ sha: base }, { sha: head }] },
    [head]: { sha: head, tree: { sha: tree }, parents: [{ sha: base }] },
    [tested]: { sha: tested, tree: { sha: tree }, parents: [{ sha: base }, { sha: head }] },
    ...options.commits,
  };
  let lookups = 0;
  const github = { rest: {
    git: { getCommit: async ({ commit_sha }) => {
      if (options.apiFailure) throw Error('API unavailable');
      assert.ok(commits[commit_sha], 'only validated immutable SHAs may be queried');
      return { data: commits[commit_sha] };
    } },
    actions: {
      getWorkflowRun: async () => ({ data: { workflow_id: 8 } }),
      listWorkflowRuns: async args => {
        lookups++;
        assert.equal(args.head_sha, head);
        assert.equal(args.event, 'pull_request');
        return { data: { workflow_runs: options.runs ?? [{ ...candidate, ...options.candidate }] } };
      },
      listJobsForWorkflowRun: async args => {
        if (options.jobsFailure) throw Error('Job metadata unavailable');
        assert.equal(args.filter, 'latest');
        return { data: { jobs: options.jobs ?? [job('ShellCheck'), job('Validate Scripts')] } };
      },
    },
  } };
  const result = await reuseValidation({ github, context, core: { info() {}, warning() {} } });
  return { result, lookups };
}
assert.equal((await check()).result, true);
assert.equal((await check({ candidate: { path: '.github/workflows/ci.yml@refs/pull/40/merge' } })).result, true);
for (const context of [{ eventName: 'pull_request' }, { ref: 'refs/heads/dev' }, { sha: 'bad' }]) {
  assert.deepEqual(await check({ context }), { result: false, lookups: 0 });
}
for (const change of [
  { event: 'push' }, { status: 'in_progress' }, { conclusion: 'failure' },
  { conclusion: 'cancelled' }, { head_sha: sha(6) }, { workflow_id: 99 },
  { path: '.github/workflows/other.yml' }, { repository: { id: 99 } },
  { head_repository: { id: 99 } },
  { updated_at: '2020-01-01T00:00:00Z' }, { updated_at: 'invalid' },
  { updated_at: '2100-01-01T00:00:00Z' },
]) assert.equal((await check({ candidate: change })).result, false, JSON.stringify(change));
for (const commits of [
  { [current]: { sha: current, tree: { sha: tree }, parents: [{ sha: base }] } },
  { [head]: { sha: head, tree: { sha: sha(6) }, parents: [{ sha: base }] } },
  { [tested]: { sha: tested, tree: { sha: sha(6) }, parents: [{ sha: base }, { sha: head }] } },
  { [tested]: { sha: tested, tree: { sha: tree }, parents: [{ sha: sha(6) }, { sha: head }] } },
]) assert.equal((await check({ commits })).result, false);
for (const jobs of [[], [job('ShellCheck')], [job('ShellCheck'), { ...job('Validate Scripts'), conclusion: 'skipped' }],
  [job('ShellCheck'), job('Validate Scripts'), job('Validate Scripts')],
  [job('ShellCheck'), { ...job('Validate Scripts'), completed_at: '2020-01-01T00:00:00Z' }],
  [job('ShellCheck'), { ...job('Validate Scripts'), status: 'in_progress' }]]) {
  assert.equal((await check({ jobs })).result, false);
}
assert.equal((await check({ runs: [] })).result, false);
assert.equal((await check({ apiFailure: true })).result, false);
assert.equal((await check({ jobsFailure: true })).result, false);
for (const steps of [[], [{ ...checkout, name: 'Checkout' }], [{ ...checkout, name: 'Checkout attacker;command' }],
  [checkout, checkout], [{ ...checkout, conclusion: 'failure' }]]) {
  assert.equal((await check({ jobs: [job('ShellCheck'), { ...job('Validate Scripts'), steps }] })).result, false);
}
assert.equal((await check({ candidate: { display_title: 'Untrusted title' } })).result, true, 'PR titles are irrelevant');
assert.equal((await check({ runs: [{ ...candidate, conclusion: 'failure' }, candidate] })).result, false,
  'an earlier success cannot override the latest failure');
assert.match(workflow, /^name: CI$/m);
assert.doesNotMatch(workflow, /^run-name:/m, 'keep workflow_run name compatibility');
assert.equal((workflow.match(/name: Checkout \$\{\{ github.sha \}\}/g) ?? []).length, 2);
assert.equal((workflow.match(/ref: \$\{\{ github.sha \}\}/g) ?? []).length, 2, 'both runners must check out the recorded immutable revision');
assert.match(workflow, /if: needs.shellcheck.outputs.macos-required == 'true' && needs.shellcheck.outputs.macos-reused != 'true'/);
assert.match(workflow, /id: reuse\n        if: github.event_name == 'push' && steps.changes.outputs.macos-required == 'true'/);
assert.match(workflow, /macos-reused: \$\{\{ steps.reuse.outputs.result \}\}/);
console.log('CI exact-tree reuse and fail-safe regression checks passed.');
