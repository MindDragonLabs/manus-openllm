# Five-minute demo once a host and accounts are ready

This is a **human-guided** demonstration. It does not install software, sign in, or spend quota automatically.

1. In a Manus chat, provide the commit-pinned `llms.txt` URL from the README and say: “Read its `llms.txt`. Use my authorized **[Mac or Linux host]**. Inspect first, then ask before setup or any model call. Please launch Claude Code through OpenLLM and show me the evidence.”
2. Manus checks that the machine is online and runs `scripts/doctor.sh` there. If either command is missing, review the official [OpenLLM](https://www.openllm.sh/llms.txt) and [Claude Code](https://code.claude.com/docs/en/setup) install steps, then explicitly approve installation before retrying. Do not paste your key or vault recovery phrase into chat.
3. Use OpenLLM's own onboarding to pair the machine. Choose **local** only if the daemon and subscription provider are connected on the serving device; choose **cloud** only if a configured BYOK provider is available. Ask Manus to report what it can verify, not assume `plus` or any particular model works.
4. Approve starting the Claude session and, separately, one small model request. Manus invokes `scripts/launch-claude.sh --route auto` (or the correct explicit route) from an empty demo directory, not the starter checkout. The default has memory auto-save/recall off; `--allow-memory` needs separate consent because it stores memory in OpenLLM cloud and can make extra inference requests. Inside Claude Code, inspect `/mcp` for OpenLLM tools, ask it to list the configured model catalog using the OpenLLM tool, then ask one short test question after approving quota use.
5. For a coding demo, choose a disposable or non-sensitive project. Ask Claude to make a small, reversible change and run its existing test. Manus reviews `git diff` and test output. A commit/push/deployment is a **separate** decision, not part of this demo.

## Pass/fail record

| Check | Required evidence |
| --- | --- |
| Host selected | Name/type of the actual authorized online machine. |
| Reviewed source and workspace | Pinned starter commit and confirmed demo/target directory. |
| Memory | Auto-save and auto-recall off, unless the user explicitly opted in. |
| Binaries | `openllm version` and `claude --version` succeed. |
| Pairing and route | Local daemon/auth status or configured hosted BYOK path, without exposing credentials. |
| MCP | OpenLLM's stdio tools visibly connected in Claude Code. |
| Model | A live discovered model ID/capability, not an assumed alias. |
| Request | One authorized answer and matching route/usage evidence. |
| Coding, if requested | Diff, tests, and explicit outcome; no silent publish. |

If the machine is offline, a login is pending, the MCP tools are absent, or a model call fails, report that exact stage rather than saying the whole integration worked.
