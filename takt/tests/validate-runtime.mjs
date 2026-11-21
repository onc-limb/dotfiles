// Validate a generated runtime.yaml with TAKT's own loader and reference checks,
// once for the default section and once per named assignment.
//
//   node validate-runtime.mjs <takt package dir> <runtime.yaml>
//
// `takt list` does not check profile references, so a typo in a generated file
// would only fail when a step runs. This uses the same functions TAKT runs
// before a workflow starts (schema parse + validateRuntimeProviderSection).
import { pathToFileURL } from 'node:url';
import { join } from 'node:path';

const [taktDir, file] = process.argv.slice(2);
if (!taktDir || !file) {
  console.error('usage: node validate-runtime.mjs <takt package dir> <runtime.yaml>');
  process.exit(2);
}
const mod = (rel) => import(pathToFileURL(join(taktDir, 'dist', rel)).href);
const { loadRuntimeProviderFileAt } = await mod('infra/config/runtime-provider/loader.js');
const { validateRuntimeProviderSection } = await mod('infra/config/runtime-provider/policy.js');

const parsed = loadRuntimeProviderFileAt(file);
if (!parsed?.provider) {
  console.error(`${file}: no provider section`);
  process.exit(1);
}
const provider = parsed.provider;
validateRuntimeProviderSection(provider);
console.log('ok default');
for (const [name, assignment] of Object.entries(provider.assignments ?? {})) {
  validateRuntimeProviderSection({
    ...provider,
    defaults: assignment.defaults ?? provider.defaults,
    targets: assignment.targets ?? provider.targets,
  });
  console.log(`ok ${name}`);
}
