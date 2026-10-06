# Jira

Search, read, create, comment on and move Jira Cloud issues from a Pepe agent.

```bash
pepe plugin install @jhonathas/jira
```

Jira **Cloud** only (REST API v3). Jira Server and Data Center authenticate differently and are not covered.

## Tools

| Tool | Does | Changes Jira? |
|---|---|---|
| `jira_search` | Lists issues matching a JQL query | no |
| `jira_get_issue` | Reads one issue: people, labels, description and the latest comments | no |
| `jira_create_issue` | Creates an issue and gives back its link | yes |
| `jira_comment` | Adds a comment | yes |
| `jira_transition` | Moves an issue through its workflow (leave the target empty to list the moves it allows) | yes |

## Set it up (about 5 minutes)

1. **Create an API token.** Open <https://id.atlassian.com/manage-profile/security/api-tokens>, choose **Create API token**, name it (say, "Pepe") and copy it. It is shown only once.
2. **Know your site.** It is the address you use to open Jira, like `yourcompany.atlassian.net` (no `https://`).
3. **Fill in the plugin.** In the Pepe dashboard open **Plugins**, find **jira** and choose **Configure**:

   | Field | What to put |
   |---|---|
   | Jira site | `yourcompany.atlassian.net` |
   | Account e-mail | The e-mail of the account the token belongs to |
   | API token | The token, written as `${JIRA_API_TOKEN}` with the real value in the Pepe server's environment, so it never sits in the settings file |
   | Default project key | Optional. Like `CNSUP`. Used when a new issue names no project |
   | Projects the agent may change | Needed to create, comment or move issues. Like `CNSUP, OPS`, or `*` for any. Empty means read only. See *Keep it safe* |

   The same settings can come from the environment instead: `JIRA_SITE`, `JIRA_EMAIL`, `JIRA_API_TOKEN`, `JIRA_PROJECT`, `JIRA_ALLOWED_PROJECTS`.
4. **Give the tools to an agent.** Only the ones you list are available to it:

   ```bash
   pepe agent tools my-agent --add jira_search,jira_get_issue,jira_create_issue,jira_comment,jira_transition
   ```
5. **Try it.** Ask the agent, in any channel: *"list the open issues in project CNSUP"*. You should get keys and summaries back. Then *"open CNSUP-1"*. To try writing, list a project in *Projects the agent may change* first.

If something is wrong the tool says what: Jira did not accept the e-mail and token (check the e-mail and that the token is current), the issue does not exist or this account cannot see it, or Jira refused a field (the message names the field).

## Keep it safe

- **Every tool asks before it runs**, unless you list it in the agent's `auto_approve`. A sensible split is to pre-approve the two that only read (`jira_search`, `jira_get_issue`) and leave the three that write to ask.
- **Writing is off until you say where.** With *Projects the agent may change* empty, the plugin only reads: creating, commenting and moving are refused before any request. List the projects (`CNSUP, OPS`) to allow them there, or `*` to allow every project. Reading is never limited by it.
- **What comes back from Jira is written by whoever filed the issue**, so it reaches the model framed as quoted material, never as instructions. Do not give an agent that reads tickets from customers more tools than it needs.
- Use a **dedicated account** for the token (a service user), not a person's, so you can see what it did and revoke it without affecting anyone.

## Notes

- The extra protection for text that comes from Jira (the run stops honoring `auto_approve` once it has read a ticket) needs a Pepe that knows `outside_content?/0`, from the release after 0.20. On an older Pepe the plugin still works and still frames the text as quoted material, but pre-approved tools keep their approval, so do not pre-approve anything risky for an agent that reads tickets.
- Descriptions and comments are Jira's rich text; the plugin reads them as plain text and writes plain text back (blank lines make paragraphs). Formatting such as bold, tables and mentions is not produced on write.
- Search returns up to 50 issues per call.
- Attachments are listed as `[attachment]`, not downloaded.

---

**Em português:** [README.pt-BR.md](https://github.com/pepe-agent/plugins/blob/main/jira/README.pt-BR.md) (também na aba **Files** desta página).
