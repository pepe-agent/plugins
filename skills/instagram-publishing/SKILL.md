---
name: instagram-publishing
description: Prepares and publishes Instagram posts safely (photo, carousel or reel), checking media, caption and the daily limit first. Use when the user asks to post, schedule or publish something on Instagram, or to draft a caption ("posta isso no Instagram", "publica esse reel", "escreve a legenda").
compatibility: Needs the instagram plugin (pepe plugin install @jhonathas/instagram) and "Allow publishing" turned on for the publish tools. Media must be at public https addresses.
metadata:
  author: jhonathas
  version: "0.1.0"
---

# Instagram publishing

A post goes live the moment it is published and the API cannot take it back. So the work is in the checks, not the click.

## Before anything

1. `instagram_account` to confirm the right account and how many API posts it may still make in the last 24 hours (the limit is small; if it is nearly used up, say so and stop).
2. `instagram_recent_posts` to match the account's tone, caption length and hashtag habits, so the new post does not look foreign.

## Check the media

- It must be reachable at a public `https://` address, because Instagram downloads it itself. A local file or a link behind a login fails.
- **Photo**: JPEG works best. **Carousel**: 2 to 10 items. **Reel**: a vertical video; processing takes a moment and the tool waits for it.
- Confirm the picture or video is the right one and is the user's to publish. If unsure, ask.

## The caption

- Draft it in the account's voice, from the recent posts. Put the hook in the first line, because feeds cut the rest.
- Keep hashtags relevant and few, matching what the account usually does.
- Do not promise results, invent facts or prices, or claim things the user did not give you.
- Show the caption and the media address to the user and wait for a clear yes. Publishing asks for approval anyway; your job is that the approval is about the right thing.

## Publish and confirm

Use `instagram_publish_photo`, `instagram_publish_carousel` or `instagram_publish_reel` once. If it fails, read the message (an unreachable image, a processing error, a rate limit), fix that one thing, and do not loop through retries: a retry after an unclear failure can publish twice. Check `instagram_recent_posts` before trying again.

When it succeeds, give the user the link.

## Rules

- One post per approval. Never publish several in a row from a single yes.
- Never publish on a guess about timing or content. Ask.
- This plugin has no scheduling: if the user wants a later time, say so and offer a Pepe scheduled task to do it then, with the media and caption saved.
