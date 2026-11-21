// Loads a workflow file with TAKT's own loader and prints its steps, rules and
// loop monitors as JSON, for takt/tests/test_workflows.py.
//
//   node dump-workflow.mjs <takt package dir> <workflow.yaml>
const [pkg, file] = process.argv.slice(2);
const { loadWorkflowByIdentifier } = await import(`${pkg}/dist/infra/config/loaders/workflowResolver.js`);
const workflow = loadWorkflowByIdentifier(file, process.cwd());
if (!workflow) {
  console.error(`could not load ${file}`);
  process.exit(1);
}
const out = {
  name: workflow.name,
  steps: workflow.steps.map((step) => ({
    name: step.name,
    kind: step.kind ?? null,
    call: step.call ?? null,
    args: step.args ?? null,
    promotion: step.promotion ?? null,
    next: (step.rules ?? []).map((rule) => rule.next ?? null),
  })),
  loopMonitors: (workflow.loopMonitors ?? []).map((monitor) => ({
    cycle: monitor.cycle,
    ignoreSteps: monitor.ignoreSteps ?? [],
    threshold: monitor.threshold,
    next: monitor.judge.rules.map((rule) => rule.next),
  })),
};
console.log(JSON.stringify(out));
