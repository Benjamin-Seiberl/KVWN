#!/usr/bin/env node
// PreToolUse hook — warns when an Edit/Write targets source code.
// Prints reminder to stderr (non-blocking). Exits 0 so the tool call proceeds.

const chunks = [];
process.stdin.on('data', (c) => chunks.push(c));
process.stdin.on('end', () => {
  let input;
  try {
    input = JSON.parse(Buffer.concat(chunks).toString('utf8'));
  } catch {
    process.exit(0);
  }
  const path = (input && input.tool_input && input.tool_input.file_path) || '';
  const isSource = /(^|[\\/])(src|supabase[\\/]migrations)[\\/]/.test(path);
  if (isSource) {
    process.stderr.write(
      '[hook] KVWN: direct code edits by the orchestrator are discouraged — ' +
      'delegate to the "frontend-dev" or "db-dev" agent via the Agent tool. ' +
      `File: ${path}\n`
    );
  }
  process.exit(0);
});
