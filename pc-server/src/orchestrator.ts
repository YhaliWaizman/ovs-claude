import { spawnSync } from "child_process";
import * as fs from "fs";
import * as path from "path";
import * as os from "os";

// tasks.md lives at the repo root, two levels above pc-server/dist/
const TASKS_FILE = path.resolve(__dirname, "../../tasks.md");

// ─── Config ───────────────────────────────────────────────────────────────────

const AGENT_CLI = process.env.AGENT_CLI ?? "copilot"; // "copilot" or "claude"

// ─── Types ────────────────────────────────────────────────────────────────────

interface Task {
  description: string;
  priority: "high" | "medium" | "low";
  projectName: string;
  projectPath: string;
  projectContext: string;
  lineIndex: number;
}

interface RunResult {
  completed: number;
  skipped: number;
  tasks: string[];
  errors: string[];
}

interface SpawnConfig {
  cmd: string;
  args: string[];
  env: NodeJS.ProcessEnv;
}

interface AgentResult {
  status: number | null;
  stdout: string;
  stderr: string;
}

// ─── Path expansion ──────────────────────────────────────────────────────────

function expandPath(rawPath: string): string {
  // Expand leading ~
  if (rawPath.startsWith("~")) {
    rawPath = rawPath.replace("~", os.homedir());
  }

  // Expand ${VAR} tokens from process.env
  rawPath = rawPath.replace(/\$\{([^}]+)\}/g, (match, varName) => {
    const value = process.env[varName];
    if (value === undefined) {
      console.warn(`[orchestrator] Warning: env var not set: ${varName}`);
      return match; // leave as-is if not found
    }
    return value;
  });

  return rawPath;
}

// ─── Agent command builder ────────────────────────────────────────────────────

function buildAgentCommand(
  prompt: string,
  agentCli: string,
  platform: string
): SpawnConfig {
  const spawnEnv = { ...process.env, AGENT_PROMPT: prompt };

  if (agentCli === "claude") {
    if (platform === "win32") {
      // Windows: use PowerShell to pass prompt via env var
      return {
        cmd: "powershell.exe",
        args: [
          "-NoProfile",
          "-NonInteractive",
          "-Command",
          "claude -p $env:AGENT_PROMPT --dangerously-skip-permissions --allowedTools 'Read,Write,Edit,Bash,Glob,Grep' --max-turns 20 --output-format json",
        ],
        env: spawnEnv,
      };
    } else {
      // Linux/macOS: direct spawn
      return {
        cmd: "claude",
        args: [
          "-p",
          prompt,
          "--dangerously-skip-permissions",
          "--allowedTools",
          "Read,Write,Edit,Bash,Glob,Grep",
          "--max-turns",
          "20",
          "--output-format",
          "json",
        ],
        env: spawnEnv,
      };
    }
  } else if (agentCli === "copilot") {
    if (platform === "win32") {
      // Windows: use PowerShell to pass prompt via env var
      return {
        cmd: "powershell.exe",
        args: [
          "-NoProfile",
          "-NonInteractive",
          "-Command",
          "copilot -p $env:AGENT_PROMPT --allow-all-tools",
        ],
        env: spawnEnv,
      };
    } else {
      // Linux/macOS: direct spawn
      return {
        cmd: "copilot",
        args: ["-p", prompt, "--allow-all-tools"],
        env: spawnEnv,
      };
    }
  } else {
    throw new Error(`Unknown agent CLI: ${agentCli}`);
  }
}

// ─── Result evaluation ────────────────────────────────────────────────────────

function evaluateResult(result: AgentResult, agentCli: string): boolean {
  // Check for spawn errors
  if (result.status === null) {
    return false;
  }

  if (result.status !== 0) {
    console.error(`[orchestrator] ✗ agent exited ${result.status}`);
    console.error(result.stderr);
    return false;
  }

  if (agentCli === "copilot") {
    // Copilot CLI: success is just exit 0
    console.log(`[orchestrator] stdout: ${result.stdout.slice(0, 2000)}`);
    if (result.stderr) console.log(`[orchestrator] stderr: ${result.stderr.slice(0, 500)}`);
    return true;
  } else if (agentCli === "claude") {
    // Claude CLI: parse JSON output and check is_error
    console.log(`[orchestrator] stdout: ${result.stdout.slice(0, 2000)}`);
    if (result.stderr) console.log(`[orchestrator] stderr: ${result.stderr.slice(0, 500)}`);

    if (!result.stdout || !result.stdout.trim()) {
      console.error(`[orchestrator] ✗ no output from claude (command may not have run)`);
      return false;
    }

    try {
      const out = JSON.parse(result.stdout);
      if (out.is_error) {
        console.error(`[orchestrator] ✗ claude reported an error: ${JSON.stringify(out)}`);
        return false;
      }
      console.log(
        `[orchestrator] ✓ done — ${out.num_turns ?? "?"} turns, $${out.cost_usd?.toFixed(4) ?? "?"}`
      );
      return true;
    } catch {
      console.error(`[orchestrator] ✗ failed to parse claude output: ${result.stdout.slice(0, 500)}`);
      return false;
    }
  }

  return false;
}

// ─── Parser ───────────────────────────────────────────────────────────────────

export function parseTasks(): Task[] {
  const content = fs.readFileSync(TASKS_FILE, "utf-8");
  const lines = content.split("\n");
  const tasks: Task[] = [];

  const priorityScore: Record<string, number> = { high: 3, medium: 2, low: 1 };

  let currentProject = "";
  let currentPath = "";
  let currentContext = "";

  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];

    const projectMatch = line.match(/^## project:\s*(.+)/);
    if (projectMatch) {
      currentProject = projectMatch[1].trim();
      currentPath = "";
      currentContext = "";
      continue;
    }

    const pathMatch = line.match(/^path:\s*(.+)/);
    if (pathMatch) {
      currentPath = expandPath(pathMatch[1].trim());
      continue;
    }

    const contextMatch = line.match(/^context:\s*(.+)/);
    if (contextMatch) {
      currentContext = contextMatch[1].trim();
      continue;
    }

    const taskMatch = line.match(/^- \[ \] (.+?) \| priority: (high|medium|low)/);
    if (taskMatch && currentProject && currentPath) {
      tasks.push({
        description: taskMatch[1].trim(),
        priority: taskMatch[2] as Task["priority"],
        projectName: currentProject,
        projectPath: currentPath,
        projectContext: currentContext,
        lineIndex: i,
      });
    }
  }

  tasks.sort((a, b) => priorityScore[b.priority] - priorityScore[a.priority]);

  return tasks;
}

// ─── Mark done ────────────────────────────────────────────────────────────────

function markDone(task: Task) {
  const content = fs.readFileSync(TASKS_FILE, "utf-8");
  const updated = content.replace(
    `- [ ] ${task.description} | priority: ${task.priority}`,
    `- [x] ${task.description} | priority: ${task.priority}`
  );
  fs.writeFileSync(TASKS_FILE, updated, "utf-8");
}

// ─── Run a single task ────────────────────────────────────────────────────────

function runTask(task: Task, stopSignal: { stop: boolean }): "ok" | "stopped" | "error" {
  if (stopSignal.stop) return "stopped";

  const prompt =
    `Project: ${task.projectName}. ` +
    (task.projectContext ? `Context: ${task.projectContext}. ` : "") +
    `Task: ${task.description}. ` +
    `Instructions: work in the current directory, make only the changes needed for this task, ` +
    `commit your changes with a meaningful commit message when done, do not ask for confirmation.`;

  console.log(`\n[orchestrator] ▶ "${task.description}"`);
  console.log(`[orchestrator]   project: ${task.projectName}`);
  console.log(`[orchestrator]   path:    ${task.projectPath}`);

  if (!fs.existsSync(task.projectPath)) {
    console.error(`[orchestrator] ✗ path does not exist: ${task.projectPath}`);
    return "error";
  }

  const spawnConfig = buildAgentCommand(prompt, AGENT_CLI, process.platform);

  const result = spawnSync(spawnConfig.cmd, spawnConfig.args, {
    cwd: task.projectPath,
    stdio: ["ignore", "pipe", "pipe"],
    encoding: "utf-8",
    shell: false,
    env: spawnConfig.env,
  });

  if (result.error) {
    console.error(`[orchestrator] ✗ spawn error: ${result.error.message}`);
    return "error";
  }

  const success = evaluateResult(
    { status: result.status, stdout: result.stdout ?? "", stderr: result.stderr ?? "" },
    AGENT_CLI
  );

  return success ? "ok" : "error";
}

// ─── Main loop ────────────────────────────────────────────────────────────────

export async function runAll(stopSignal: { stop: boolean }): Promise<RunResult> {
  const tasks = parseTasks();
  const result: RunResult = { completed: 0, skipped: 0, tasks: [], errors: [] };

  if (tasks.length === 0) {
    console.log("[orchestrator] No pending tasks.");
    return result;
  }

  console.log(`[orchestrator] Found ${tasks.length} pending task(s).`);
  console.log(`[orchestrator] Using agent: ${AGENT_CLI}`);

  for (const task of tasks) {
    if (stopSignal.stop) {
      console.log("[orchestrator] Stop signal received — halting.");
      break;
    }

    const status = runTask(task, stopSignal);

    if (status === "stopped") break;

    if (status === "ok") {
      markDone(task);
      result.completed++;
      result.tasks.push(`[${task.projectName}] ${task.description}`);
    } else {
      result.skipped++;
      result.errors.push(`[${task.projectName}] ${task.description}`);
    }
  }

  return result;
}
