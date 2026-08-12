---
description: Scaffold a new ADR from the template and write it in place.
---

Optional args: `<slug>` or `<slug> "<title>"`. Example: `/new-adr widget-bundling` or
`/new-adr widget-bundling "Widget ships as an appex embedded by Xcode"`.

Steps:

1. **Sanity check first.** If the conversation does not contain an actual decision to record
   (alternatives considered, a choice made, consequences identified), stop and say we need to decide
   something concrete first. This command commits a decision to disk; it does not invent one.

2. **Find the next number.** `ls docs/adr/ | rg '^[0-9]{4}-' | sort | tail -1`, parse the four-digit
   prefix, add 1, zero-pad → `NNNN`.

3. **Slug.** Use the arg if given; otherwise ask — kebab-case, short, matching existing ADRs.

4. **Title.** Use the arg if given; otherwise ask for a one-line title (no `ADR-NNNN:` prefix — that
   is added for you).

5. **Create the file.** Copy `docs/adr/0000-template.md` to `docs/adr/NNNN-<slug>.md`, substituting
   the real number and title in the H1, `YYYY-MM-DD` → today, `<who>` → `git config user.name`
   (fall back to `Justin`). `Status:` stays `Proposed` — the operator flips it to Accepted.

6. **Write the content** in place: Context / Decision / Consequences / Alternatives, plus the
   `> **TL;DR:**` line. 3–5 paragraphs — long ADRs decay. At least one rejected alternative with two
   or three lines on why not. Consequences must include the negatives.
