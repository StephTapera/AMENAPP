const fs = require("fs");
const path = require("path");
const ts = require("typescript");

const contextDir = path.join(__dirname, "..", "context");
const compilerOptions = {
  module: ts.ModuleKind.CommonJS,
  target: ts.ScriptTarget.ES2020,
  esModuleInterop: true,
  skipLibCheck: true,
  strict: false,
};

for (const fileName of fs.readdirSync(contextDir)) {
  if (!fileName.endsWith(".ts")) {
    continue;
  }

  const sourcePath = path.join(contextDir, fileName);
  const outputPath = path.join(contextDir, fileName.replace(/\.ts$/, ".js"));
  const source = fs.readFileSync(sourcePath, "utf8");
  const result = ts.transpileModule(source, {
    compilerOptions,
    fileName,
  });

  fs.writeFileSync(outputPath, result.outputText);
}
