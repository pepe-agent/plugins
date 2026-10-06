# Notion

Search, read, create and add text to Notion pages and databases from a Pepe agent.

```bash
pepe plugin install @jhonathas/notion
```

## Tools

| Tool | Does | Changes Notion? |
|---|---|---|
| `notion_search` | Searches pages and databases by title | no |
| `notion_get_page` | Reads a page: its properties and its content as text | no |
| `notion_query_database` | Lists the rows of a database with their properties, optionally narrowed with a Notion filter | no |
| `notion_create_page` | Creates a page with a title and text, under a page or as a row of a database | yes |
| `notion_append` | Adds text at the end of a page | yes |

## Set it up (about 5 minutes)

Notion works differently from most services: **an integration sees only the pages that were shared with it.** That is the step people miss, so it comes first.

1. **Create the integration.** Open <https://www.notion.so/profile/integrations>, choose **New integration**, name it (say, "Pepe"), pick the workspace, and keep the type **Internal**. Under **Capabilities** choose **Read content**. Add **Insert content** and **Update content** only if the agent should create pages and add text. Save.
2. **Copy the token.** On the integration's page, copy the **Internal Integration Secret** (it starts with `ntn_` or `secret_`).
3. **Share the pages with it.** Open each page or database the agent should reach, choose **...** (top right) → **Connections** → **Add connections**, and pick the integration. Sharing a page also shares everything inside it, so sharing one parent page is usually enough. Without this step every call answers "could not find it".
4. **Fill in the plugin.** In the Pepe dashboard open **Plugins**, find **notion** and choose **Configure**:

   | Field | What to put |
   |---|---|
   | Integration token | The token, written as `${NOTION_TOKEN}` with the real value in the Pepe server's environment, so it never sits in the settings file |
   | Allow writing | `no` (the default) means read only. Set `yes` to let it create pages and add text |

   The same settings can come from the environment: `NOTION_TOKEN`, `NOTION_WRITES` (`yes`).
5. **Give the tools to an agent.** Only the ones you list are available to it:

   ```bash
   pepe agent tools my-agent --add notion_search,notion_get_page,notion_query_database,notion_create_page,notion_append
   ```
6. **Try it.** Ask the agent: *"search Notion for the roadmap"*, then *"read that page"*. You can also hand it the address of a page; it understands both the address and the id.

If something is wrong the tool says what: Notion did not accept the token, the page or database is not shared with the integration (the message says where to share it), the integration lacks a capability, or Notion is rate limiting (the message says how long to wait).

## Keep it safe

- **Every tool asks before it runs**, unless you list it in the agent's `auto_approve`. A sensible split is to pre-approve the three that only read and leave the two that write to ask.
- **Writing is off until you turn it on** (*Allow writing*), and even then it can only write where the integration was shared. Share the integration with the smallest set of pages the agent needs; that is the real limit.
- **What comes back from Notion is written by whoever can edit the page**, so it reaches the model framed as quoted material, never as instructions. Be careful giving an agent that reads shared pages many tools.

## Notes

- Search looks at titles, not at the text inside pages.
- A page is read as plain text: headings, lists, to-dos, quotes, code, tables and nested blocks (a few levels, within a request budget). Images and files show as `[image]` or `[file]`. Very long pages are cut at 20,000 characters, and it says so.
- Created pages and added text are plain paragraphs (blank lines make paragraphs). Formatting such as bold, tables and mentions is not produced on write.
- Creating a row in a database sets only its title; other properties are left empty.
- It uses Notion API version `2022-06-28`.
- Installing shows a `caution` from Pepe's scan: the plugin reads environment variables (for the token) and uses the network. That is what it is for.
- The extra protection for text that comes from Notion (the run stops honoring `auto_approve` once it has read a page) needs a Pepe that knows `outside_content?/0`, from the release after 0.20. On an older Pepe the plugin works and still frames the text as quoted material, but pre-approved tools keep their approval, so do not pre-approve anything risky for an agent that reads shared pages.

---

**Em português:** [README.pt-BR.md](https://github.com/pepe-agent/plugins/blob/main/notion/README.pt-BR.md) (também na aba **Files** desta página).
