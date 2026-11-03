import { cp, mkdir, readFile, writeFile } from 'node:fs/promises';
import { join, resolve } from 'node:path';

const [output] = process.argv.slice(2);
if (!output) throw new Error('Pass a new output directory for the packages.');

const destination = resolve(output);
const scope = '@guptan404';
const registry = 'https://npm.pkg.github.com';
await mkdir(destination);

for (const name of ['core', 'express']) {
  const source = new URL(`../node/packages/${name}/`, import.meta.url);
  const target = join(destination, name);
  await mkdir(target);
  for (const file of ['dist', 'LICENSE', 'README.md', 'CHANGELOG.md']) {
    await cp(new URL(file, source), join(target, file), { recursive: true });
  }

  const manifest = JSON.parse(await readFile(new URL('package.json', source), 'utf8'));
  manifest.name = `${scope}/vigil-${name}`;
  manifest.publishConfig = { registry };
  delete manifest.scripts;
  delete manifest.devDependencies;

  const readme = join(target, 'README.md');
  const documentation = await readFile(readme, 'utf8');
  await writeFile(readme, documentation.replaceAll(
    /([\s"'])@vigiljs\/(core|express)\b/g,
    `$1${scope}/vigil-$2`,
  ));

  if (name === 'express') {
    const coreVersion = manifest.dependencies['@vigiljs/core'];
    delete manifest.dependencies['@vigiljs/core'];
    manifest.dependencies[`${scope}/vigil-core`] = coreVersion;
    for (const file of ['dist/index.js', 'dist/index.d.ts']) {
      const path = join(target, file);
      const content = await readFile(path, 'utf8');
      await writeFile(path, content.replaceAll('@vigiljs/core', `${scope}/vigil-core`));
    }
  }

  await writeFile(join(target, 'package.json'), JSON.stringify(manifest, null, 2) + '\n');
}
