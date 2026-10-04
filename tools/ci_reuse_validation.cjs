// Reuse only a recent, fully successful run of the identical merge tree.
module.exports = async ({ github, context, core }) => {
  const validSHA = value => typeof value === 'string' && /^[a-f0-9]{40}$/.test(value);
  if (context.eventName !== 'push' || context.ref !== 'refs/heads/main' ||
      !validSHA(context.sha)) return false;
  const { owner, repo } = context.repo;
  try {
    const commit = async sha => (await github.rest.git.getCommit({ owner, repo, commit_sha: sha })).data;
    const merged = await commit(context.sha);
    // Other merge methods and direct commits take the normal validation path.
    if (merged.parents?.length !== 2 || !validSHA(merged.tree?.sha) ||
        !merged.parents.every(parent => validSHA(parent.sha))) return false;
    const [base, head] = merged.parents.map(parent => parent.sha);
    if ((await commit(head)).tree?.sha !== merged.tree.sha) return false;
    const { data: current } = await github.rest.actions.getWorkflowRun({ owner, repo, run_id: context.runId });
    // Inspect the latest run, including failures; never fall back to an older green run.
    const { data: runs } = await github.rest.actions.listWorkflowRuns({
      owner, repo, workflow_id: current.workflow_id, event: 'pull_request', head_sha: head, per_page: 1,
    });
    const run = runs.workflow_runs?.[0];
    const repoID = context.payload.repository.id;
    const recent = date => {
      const age = Date.now() - Date.parse(date);
      return Number.isFinite(age) && age >= 0 && age <= 24 * 60 * 60 * 1000;
    };
    if (!run || !Number.isSafeInteger(repoID) || run.repository?.id !== repoID ||
        run.head_repository?.id !== repoID || run.workflow_id !== current.workflow_id ||
        run.path !== '.github/workflows/ci.yml' || run.event !== 'pull_request' ||
        run.head_sha !== head || run.status !== 'completed' || run.conclusion !== 'success' ||
        !recent(run.updated_at)) return false;
    const { data: result } = await github.rest.actions.listJobsForWorkflowRun({
      owner, repo, run_id: run.id, filter: 'latest', per_page: 100,
    });
    if (!['ShellCheck', 'Validate Scripts'].every(name =>
        result.jobs.filter(job => job.name === name).length === 1 &&
        result.jobs.some(job => job.name === name && job.status === 'completed' &&
          job.conclusion === 'success' && recent(job.completed_at)))) return false;
    // Job metadata records the immutable checkout without changing the workflow name
    // consumed by Codex's workflow_run trigger. Titles and PR text are never proof.
    const validation = result.jobs.find(job => job.name === 'Validate Scripts');
    const checkouts = validation.steps.filter(step => /^Checkout [a-f0-9]{40}$/.test(step.name));
    if (checkouts.length !== 1 || checkouts[0].status !== 'completed' ||
        checkouts[0].conclusion !== 'success') return false;
    const tested = await commit(checkouts[0].name.slice('Checkout '.length));
    if (tested.tree?.sha !== merged.tree.sha || tested.parents?.length !== 2 ||
        tested.parents[0].sha !== base || tested.parents[1].sha !== head) return false;
    core.info(`Reusing macOS validation from run ${run.id}: identical tree ${merged.tree.sha}.`);
    return true;
  } catch {
    core.warning('Prior validation could not be verified; running the normal macOS checks.');
    return false;
  }
};
