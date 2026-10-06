# GitHub

Search, read, open and comment on GitHub issues and pull requests, and read the files of a repository, from a Pepe agent.

```bash
pepe plugin install @jhonathas/github
```

Works with github.com and with GitHub Enterprise Server.

## Tools

| Tool | Does | Changes GitHub? |
|---|---|---|
| `github_search` | Searches issues and pull requests (GitHub's search syntax: `repo:`, `is:open`, `is:pr`, `label:`...) | no |
| `github_get_issue` | Reads one issue or pull request: who opened it, state, labels, text, latest comments, and for a pull request the branches and whether it was merged | no |
| `github_get_file` | Reads a text file of a repository, or lists a folder, at a branch, tag or commit | no |
| `github_create_issue` | Opens an issue and gives back its link | yes |
| `github_comment` | Comments on an issue or pull request | yes |

## Set it up (about 5 minutes)

1. **Create an access token.** Use a *fine-grained* token, which can be limited to the repositories and permissions you choose. Open <https://github.com/settings/personal-access-tokens>, choose **Generate new token** and:
   - give it a name and an expiry (90 days is a good start);
   - **Resource owner**: you, or your organization (an organization has to allow fine-grained tokens first);
   - **Repository access**: **Only select repositories**, and pick just the ones the agent needs;
   - **Repository permissions**: **Contents: Read-only**, **Issues: Read-only** to read (or **Read and write** if the agent should open issues and comment), and **Pull requests: Read-only** (or **Read and write** if it should comment on pull requests). Metadata is added for you. GitHub's page shows the exact names, which can change.

   Copy the token; it is shown only once.
2. **Fill in the plugin.** In the Pepe dashboard open **Plugins**, find **github** and choose **Configure**:

   | Field | What to put |
   |---|---|
   | Access token | The token, written as `${GITHUB_TOKEN}` with the real value in the Pepe server's environment, so it never sits in the settings file |
   | Default repository | Optional. Like `acme/app`. Used when a call names no repository |
   | Repositories the agent may change | Needed to open issues or comment. Like `acme/app, acme/docs` or `acme/*`, or `*` for any. Empty means read only. See *Keep it safe* |
   | API address | Only for GitHub Enterprise Server, like `https://git.example.com/api/v3`. Empty for github.com |

   The same settings can come from the environment: `GITHUB_TOKEN`, `GITHUB_REPO`, `GITHUB_ALLOWED_REPOS`, `GITHUB_API_URL`.
3. **Give the tools to an agent.** Only the ones you list are available to it:

   ```bash
   pepe agent tools my-agent --add github_search,github_get_issue,github_get_file,github_create_issue,github_comment
   ```
4. **Try it.** Ask the agent: *"list the open issues labeled bug in acme/app"*, then *"read issue 7"*, then *"show me lib/app.ex"*. To try writing, list a repository in *Repositories the agent may change* first.

If something is wrong the tool says what: GitHub did not accept the token (check that it is current), the repository or issue was not found (a private repository the token cannot see looks the same), the token is not allowed to do that (a missing permission), or GitHub is rate limiting the token.

## Keep it safe

- **Every tool asks before it runs**, unless you list it in the agent's `auto_approve`. A sensible split is to pre-approve the three that only read and leave the two that write to ask.
- **Writing is off until you say where.** With *Repositories the agent may change* empty, the plugin only reads: opening issues and commenting are refused before any request. List the repositories (`acme/app`, or `acme/*` for all of an owner) to allow them there, or `*` for any. Reading is never limited by it, only by what the token can see.
- **Give the token only what the agent needs.** The token is the real limit: a read-only token cannot write even if a setting is wrong.
- **What comes back from GitHub is written by whoever opened the issue or pushed the file**, so it reaches the model framed as quoted material, never as instructions. Be careful giving an agent that reads outside issues many tools.

## Notes

- Files over 500 KB are not read, and a text is cut at 20,000 characters (it says so). Files that are not text are reported, not shown.
- The latest comments come from the last page of the thread (up to 100 comments).
- Installing shows a `caution` from Pepe's scan: the plugin reads environment variables (for the token), uses the network, and decodes the base64 content GitHub returns for a file. That is what it is for.
- The extra protection for text that comes from GitHub (the run stops honoring `auto_approve` once it has read an issue or a file) needs a Pepe that knows `outside_content?/0`, from the release after 0.20. On an older Pepe the plugin works and still frames the text as quoted material, but pre-approved tools keep their approval, so do not pre-approve anything risky for an agent that reads outside issues.

---

**Em português:** [README.pt-BR.md](https://github.com/pepe-agent/plugins/blob/main/github/README.pt-BR.md) (também na aba **Files** desta página).
