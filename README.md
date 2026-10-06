# Pepe plugins

Plugins for [Pepe](https://github.com/pepe-agent/pepe), the agent runtime. Each folder is one plugin you can install on its own, published on [PepeHub](https://hub.pepe-agent.com):

```bash
pepe plugin install @jhonathas/jira
```

| Plugin | What it connects | Status |
|---|---|---|
| [`jira`](jira/) | Jira Cloud: search, read, create, comment, move issues | ready to try |
| [`github`](github/) | GitHub: search and read issues and pull requests, read repository files, open issues, comment | ready to try |
| [`notion`](notion/) | Notion: search, read pages, list database rows, create pages, add text | ready to try |
| [`drive`](drive/) | Google Drive (read only): search files, read Docs, Sheets, Slides and text files | ready to try |
| [`instagram`](instagram/) | Instagram (Business or Creator account): see the account and recent posts, publish a photo, a carousel or a reel | ready to try |
| [`meta-ads`](meta-ads/) | Meta Ads (Facebook and Instagram): read campaigns and results, research audiences, build campaigns, ad sets, creatives and ads (always paused), edit, pause, duplicate and turn on within a budget limit | ready to try |

More are planned: Zapier and Stripe (read only).

Every plugin has a README with a step by step setup, the fields to fill in, how to test it and what to be careful with. The same text is what shows on the plugin's page on the hub.

## How a plugin is laid out

```
jira/
  manifest.json   name, version, the tools it provides, and the settings the dashboard asks for
  jira.exs        the code (Pepe compiles it when it is installed)
  README.md       what it does and how to set it up (README.pt-BR.md in Portuguese)
```

The settings in `manifest.json` become the **Configure** form in the Pepe dashboard. A value written as `${ENV_VAR}` is kept as that reference and read from the environment only when used, so secrets never sit in a settings file.

## Working on a plugin

```bash
mix deps.get
mix test
```

The tests run each plugin against a fake of the service it talks to, so they need no account and no network. The Pepe runtime is **not** a dependency (it is large); the few modules a plugin leans on are stood in for under `test/support/`. Keep that file in step with Pepe's own contract.

What a plugin must hold to:

- **Read and write are separate tools**, so an agent can be given one without the other.
- **Writing is off until the operator says where**: a plugin installed with no list can only read, and a write outside the list is refused before any request is made (`*` allows everything, on purpose).
- **Text that came from the service** (a ticket, a page) is returned framed with `Pepe.Security.ExternalContent.mark_untrusted/2`, and a tool that returns such text says so with `outside_content?/0` (a Pepe from the release after 0.20 on; older ones ignore it).
- **No secret in the code.** Settings come from the plugin's configuration, falling back to environment variables.
- **A clear message for every failure** (bad credentials, not found, refused field), written for the model to read.

## Packing and publishing

```bash
bin/pack jira        # writes dist/jira-<version>.tgz
```

The script puts the plugin's files at the **root** of the archive. That matters: PepeHub shows a plugin's README only when `README.md` is at the root of the archive (the Pepe installer finds the package either way, so a wrongly packed plugin installs fine and just has an empty README tab). Publish the result from the PepeHub site, or through its API with a login from the GitHub device flow.

## License

MIT
