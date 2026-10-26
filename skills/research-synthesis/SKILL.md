---
name: research-synthesis
description: "Synthesize qualitative research (interview notes, transcripts, survey exports, support tickets) into evidence-backed themes. Each theme carries verbatim quotes with their source, a count of supporting sources, a confidence level, and the evidence that contradicts it, followed by open questions and the research that would settle them. Use for \"synthesize these interviews\", \"what are the themes in this research\", \"affinity-map these notes\", \"what are customers saying in these tickets\". Read-only; output is a private HTML artifact."
---

**Research synthesis** turns raw research into themes a team can act on, and makes each claim no stronger
than its evidence. The value is the traceability: anyone reading a theme can walk it back to the exact
words of the person who said it. Use any focus or research question supplied in the request.

**No quote without a source.** Every quote is verbatim from a file you read, attributed to that file and to
the participant label the source itself uses (`P3`, `ticket #4812`, `row 17`). Never invent participants,
quotes, counts, or demographics. Never paraphrase inside quotation marks. Never fill a gap with a
plausible-sounding person. If the data doesn't say who said something, attribute it to the file only.

### 1. Gather the sources, and say what was missing
- **Files and directories** named in the request: read every file in full. Don't sample, and don't stop
  at the first few that agree. Supported formats: notes and transcripts (`.md`, `.txt`, `.docx` text,
  `.vtt`/`.srt`), and exports (`.csv`, `.json`) for surveys and tickets.
- **Connected sources**, if the request points at them and the server is connected in this session:
  Notion (use the work workspace for work research, and never mix it with personal), Google Drive. Read
  and search only. Never create, comment on, or move anything there.
- Never edit, rename, or annotate a source file.
- List what you read (with the count of files and of rows or records), what you couldn't open, and every
  source the request named that wasn't reachable. That list goes at the top of the report.
- **Unit of evidence.** A "source" is one participant where the data labels participants, otherwise one
  file, ticket, or survey response. Say which unit you used. A count is only meaningful against that unit.

### 2. Code the data: observation first
Go through every source and pull out **observations**: what a person said or did, quoted verbatim with its
location (file, plus line, timestamp, or row where the source has one). Tag each with the participant
label as given. Keep observations separate from **interpretations**, meaning what you think they mean.
The report labels the two differently, and a theme's claim is always an interpretation.

For survey and ticket exports, **compute every count from the data**: read the file and count rows. State
the denominator ("14 of 52 responses"). Never estimate, round up, or say "most". If you can't compute a
number, leave it out.

### 3. Build the themes
Cluster the observations into themes. For each theme:
- **Claim.** One sentence, marked as interpretation.
- **Evidence.** The verbatim quotes that best support it, each with its source and location. Include
  enough of them that the strength is visible, not just the one best line.
- **Support.** The count of distinct sources behind it, in the stated unit, out of the total ("4 of 9
  participants"). Count sources, not mentions: a participant who says it five times counts once.
- **Contradicting evidence.** Quotes that cut against the theme, with their sources. If you looked and
  found none, write "none found". Never leave the field blank, because a blank reads as "didn't look".
- **Confidence**, by a rule printed in the report:
  - **high**: 3 or more independent sources and no unresolved contradiction
  - **medium**: 2 sources, or contradicting evidence present
  - **low / thin**: 1 source
  **A theme with one source is labeled thin evidence**, never presented as a pattern.
- **Who's missing.** Segments or participants who are silent on this theme, where the data shows the
  segments.

Keep the outliers: an observation that fits no theme goes in an "unclustered" list, not the bin. Order the
themes by support, then by confidence. Never order them by how interesting they are.

### 4. Open questions
List what the data raises but can't answer: thin themes, contradictions, segments with no voice in the
data, and questions nobody asked. For each one, give the research that would settle it (the method, who
to talk to, and roughly what you'd ask) and what deciding it would unblock. These are proposals. Don't
claim a sample size is adequate unless you can say why.

### 5. Check before writing
Re-read every quote against its source file to confirm the wording and attribution match exactly.
Re-count each theme's support. Drop or fix anything that doesn't hold, and say how many you corrected.
If you're unsure the synthesis holds up, have an in-tool `refuter` subagent attack the themes against the
same sources and report where it disagrees. **Participant data never goes to another vendor's CLI unasked.**
Sending it there is an external send: offer a cross-vendor refutation and run it only on an explicit yes.
On an unattended run, nobody can say yes, so report it as offered and not run.

### 6. Deliver a private artifact
This is participant data. The report is **private**: write a self-contained `report.html` to
`~/.ai-context/research-synthesis/<slug>-YYYY-MM-DD/`. Never write it inside a git repo, where it could
get committed, and never upload, share, post, or email it. Contact details that appear inside quotes
(emails, phone numbers) are masked as `[redacted]`, and the mask is shown. Participant labels stay as the
sources give them.

The report contains, in this order:
1. sources read and sources missing
2. the unit of evidence and the confidence rule
3. the themes, each with claim, evidence, support, contradictions, confidence, and who's missing
4. unclustered observations
5. open questions, each with the research that would settle it
6. limitations: sampling, who recruited the participants if known, and what the data can't speak to

Serve it on the tailnet only, per the preview rules (bind `0.0.0.0`, curl until you get a 200, hand over
the `http://<host>.ts.net:PORT/report.html` URL), unless the run is unattended (step 7). Never use a
public tunnel or a share link.

In chat, give a short summary: the number of themes with each one's support and confidence, which themes
are thin, the top open question, sources missing, and the URL. **Findings are never trimmed:** every theme
and outlier goes in the artifact. Then offer next steps (a deeper cut on one theme, a recruiting brief for
an open question) and do nothing beyond the report without a go-ahead.

### 7. Unattended runs and the result line
**An unattended run finishes; it doesn't wait.** A run is unattended when nobody can answer mid-run: a
`/goal` or `/loop` turn, a scheduled or headless run, or a request that says so. Wherever this skill says
ask, an unattended run takes the unit of evidence the data supports and the sources it can open, marks it
*assumed* in the report and lists it under open questions, then finishes. With no source it can open, it
reports `themes=0` with the sources missing. It starts no server either: it writes the file and gives its
path, because a loop that serves every run leaves a server behind each time.

**End the chat summary with one result line**, in exactly this shape:
`SYNTHESIS themes=N sources=N unit=participant|file|response quotes-reverified=N/N corrected=N sources-missing=N`
It is a record for a loop or a later reader, not a goal's done-condition: whether the themes hold is a
judgment, and `quotes-reverified` short of N/N means step 5 didn't finish.
