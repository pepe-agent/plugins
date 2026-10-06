# Google Drive

Search the files of a Google Drive and read them as text, from a Pepe agent. Read only.

```bash
pepe plugin install @jhonathas/drive
```

## Tools

| Tool | Does | Changes Drive? |
|---|---|---|
| `drive_search` | Searches files and folders by name or text, lists one folder, narrows by type (doc, sheet, slides, pdf, folder) | no |
| `drive_get_file` | Reads a file as text: a Google Doc or Slides deck as plain text, a Sheet as CSV (its first sheet), a text file as it is | no |

Other kinds (PDF, images, videos) give only their details: name, type, size, link. Reading a PDF's text is not covered yet.

## Set it up (about 10 minutes)

The plugin signs in as a **service account**: a robot account with its own e-mail address. It has **no access to anything until you share it**, so what you share is exactly what the agent can read. There is no consent screen and no token to renew by hand.

1. **Open a Google Cloud project.** Go to <https://console.cloud.google.com>, and pick or create a project (a free one is enough).
2. **Turn on the Drive API.** **APIs & Services** → **Library** → search **Google Drive API** → **Enable**.
3. **Create the service account.** **IAM & Admin** → **Service Accounts** → **Create service account**. Name it (say, "pepe-drive"). It needs no role. Create it.
4. **Create its key.** Open the account → **Keys** → **Add key** → **Create new key** → **JSON**. A file downloads. Keep it private: it is the account's password.
5. **Share what it should read.** Copy the account's e-mail (it looks like `pepe-drive@your-project.iam.gserviceaccount.com`). In Drive, open each folder or file the agent should reach, choose **Share**, paste that e-mail and give it **Viewer** access. Sharing a folder shares everything inside it, so one folder is usually enough. For a **shared drive**, add the e-mail as a member.
6. **Fill in the plugin.** In the Pepe dashboard open **Plugins**, find **drive** and choose **Configure**:

   | Field | What to put |
   |---|---|
   | Service account key | Any one of: the JSON file's contents pasted in; the path to the file on the machine where Pepe runs (like `/data/keys/pepe-drive.json`); or `${GOOGLE_SERVICE_ACCOUNT}` with the JSON in the Pepe server's environment |

   The same setting can come from the environment: `GOOGLE_SERVICE_ACCOUNT`.
7. **Give the tools to an agent.** Only the ones you list are available to it:

   ```bash
   pepe agent tools my-agent --add drive_search,drive_get_file
   ```
8. **Try it.** Ask the agent: *"list the files in Drive"*, then *"read the plan document"*. You can also hand it the address of a file or folder.

If something is wrong the tool says what: Google did not accept the service account (the message gives Google's reason, and a wrong or expired key is the usual one), the Drive API is not enabled, the file is not shared with the account's e-mail (the message says so), or Google is rate limiting (the message says how long to wait).

## Keep it safe

- **It can only read, and only what you shared.** Share the smallest set of folders the agent needs; that is the real limit. The plugin asks Google for read-only access, so even a mistake cannot change a file.
- **Every tool asks before it runs**, unless you list it in the agent's `auto_approve`. Reading is low risk, so pre-approving both is reasonable.
- **What comes back from Drive is written by whoever can edit the file**, so it reaches the model framed as quoted material, never as instructions. Be careful giving an agent that reads shared documents many other tools.
- **Treat the key file like a password.** Prefer a path on the server or an environment variable over pasting the JSON into the form, and never put it in a repository.

## Notes

- A text is cut at 20,000 characters (it says so). A plain text file over 1 MB is not read.
- A Sheet is read as CSV of its first sheet only.
- Search matches the name and the text inside files (Google's full text search), newest edits first.
- The service account has its own, empty Drive: it does not see yours unless you share.
- Installing shows a `caution` from Pepe's scan: the plugin reads environment variables, uses the network, and signs a request with the account's private key. That is what it is for.
- The extra protection for text that comes from Drive (the run stops honoring `auto_approve` once it has read a file) needs a Pepe that knows `outside_content?/0`, from the release after 0.20. On an older Pepe the plugin works and still frames the text as quoted material, but pre-approved tools keep their approval, so do not pre-approve anything risky for an agent that reads shared documents.

---

**Em português:** [README.pt-BR.md](https://github.com/pepe-agent/plugins/blob/main/drive/README.pt-BR.md) (também na aba **Files** desta página).
