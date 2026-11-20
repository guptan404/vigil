import { spawn } from "node:child_process";
import { fileURLToPath } from "node:url";
import { createServer } from "node:net";

const root = fileURLToPath(new URL("../", import.meta.url));
const port = Number(process.env.PORT ?? 4010);

function run(command, args, options = {}) {
  return new Promise((resolve, reject) => {
    const child = spawn(command, args, { cwd: root, stdio: "inherit", ...options });
    child.once("error", reject);
    child.once("exit", (code, signal) => {
      if (code === 0) resolve();
      else reject(new Error(command + " exited with " + (signal ?? code)));
    });
  });
}

try {
  if (!Number.isInteger(port) || port < 1 || port > 65535) {
    throw new Error("PORT must be an integer between 1 and 65535.");
  }
  await new Promise((resolve, reject) => {
    const probe = createServer();
    probe.once("error", reject);
    probe.listen(port, "127.0.0.1", () => probe.close(resolve));
  });
  await run("npm", ["run", "build"]);
  await run("flutter", ["build", "web", "--debug", "--no-web-resources-cdn"], {
    cwd: fileURLToPath(new URL("../example/flutter_app/", import.meta.url)),
  });
  console.log("Opening Vigil preview at http://127.0.0.1:" + port);
  await run("npm", ["run", "dev", "--workspace", "vigil-node-server-example"], {
    env: { ...process.env, PORT: String(port), NODE_ENV: "development", VIGIL_WEB_PREVIEW: "true" },
  });
} catch (error) {
  console.error(error.code === "EADDRINUSE"
    ? "Port " + port + " is in use. Run PORT=4011 npm run preview to use another port."
    : error.message);
  process.exitCode = 1;
}
