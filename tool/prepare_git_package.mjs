import { spawnSync } from "node:child_process";
import { cp, mkdir, readFile, readdir, rm, writeFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";

const root = fileURLToPath(new URL("../", import.meta.url));
const output = new URL("../git-dist/", import.meta.url);

for (const name of ["core", "express"]) {
  const result = spawnSync("npm", ["run", "build", "--workspace", "@vigiljs/" + name], {
    cwd: root, stdio: "inherit",
  });
  if (result.error) throw result.error;
  if (result.status !== 0) process.exit(result.status ?? 1);
}

// Git dependencies are installed from the repository root. Include both Node
// packages so the Express bridge uses the core from the same Git revision.
await rm(output, { recursive: true, force: true });
await mkdir(output);
await writeFile(new URL("package.json", output), '{"type":"module"}\n');
for (const name of ["core", "express"]) {
  const target = new URL(name + "/", output);
  await cp(new URL("../node/packages/" + name + "/dist/", import.meta.url), target, {
    recursive: true,
  });
  if (name === "express") {
    for (const entry of await readdir(target)) {
      if (!entry.endsWith(".js") && !entry.endsWith(".d.ts")) continue;
      const file = new URL(entry, target);
      const content = await readFile(file, "utf8");
      await writeFile(file, content.replaceAll('"@vigiljs/core"', '"../core/index.js"'));
    }
  }
}
