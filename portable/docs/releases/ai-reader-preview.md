# AI reader preview

- Ask questions about open documents; click cited sources to open the page and highlight the passage.
- Keep chat in a separate window, pin it above the reader or all apps, and see questions, replies and work status.
- Preview pages, organize groups, control the reader, and manage supported PDF comments.
- Request a separate PDF export, OCR copy or translated copy; stop work and undo eligible changes.
- Complete the four-step first-run setup; new installations default chat and summaries on.
- Cloud requests wait until setup is complete and OpenRouter is connected.

---

## For readers

The first normal launch opens a four-step setup after the reader is ready:
**Full Disk Access**, **Collection**, **OpenRouter**, then **Default reader**.
Full Disk Access is optional; you can continue and macOS will prompt if a later
open needs it. Collection offers an adjustable dynamic limit of 50–80% (default 80%) of free
space plus existing Collection storage, a fixed limit, or Unlimited. Move
location verifies the transfer and removes the old stored files. Editable
Collection documents can move between folders on the same disk; cross-disk moves
are refused when editable documents exist, protecting in-progress saves. Startup
Keychain reads cannot show password prompts. OpenRouter connects in
the browser or through an API key field revealed on request; keys stay in
Keychain. Open the model picker to load and search the catalog of models that
support tool calls. The final step lets you search file types and independently
set ShenzhenPDF as their default reader. Setup explains that document text is
sent to OpenRouter for summaries and missing chapters and that usage spends
account credits. It has no Accessibility step. **Done** returns to the reader;
Settings does not appear on each startup.

New installations default document chat and automatic analysis to on, and
existing saved preferences are preserved. This does not start cloud work before
the wizard is complete and an OpenRouter account is connected. You can change
these preferences later under **Settings → Settings & AI… → AI settings**. Select a model
from the catalog; availability can change and is checked with OpenRouter.
Press **⌘K**, then Return with an empty search field to open
chat; choose **New chat** for a separate conversation. Return sends a message, Shift-Return adds a line. With a nonempty search
query, Return continues to open the selected search result; use the explicit
Ask action to start a new chat with that query as a draft, then press Return to send. The chat can be stopped with
**Stop** or closed with Escape. Saved conversations are available from **Chats**;
deleting chats removes their transcripts and saved page previews from this Mac.
Chat now has its own native resizable window with independent search, normal
macOS Close/Minimize behavior, and two remembered pin modes: above Shenzhen PDF
or above all apps. Closing it preserves the unsent draft and conversation.
Activity shows when the model is thinking, which tool is working, when a reply
is ready, and actionable failures. User messages remain in the saved history. Muted blue user messages and neutral
assistant messages distinguish the two speakers in both themes. Replies are
brief by default and follow the user’s requested scope and wording.
The authorization-send path no longer loses the user message when its composer
clears, which previously could stop the first tool call with a false save conflict.

Answers can cite exact retrieved passages and show relevant page previews.
Selecting a text-search citation opens that document and page with the passage
highlighted; page-only links support visual sources. Source revision and layout
checks reject stale links, and opening a citation keeps chat available. The assistant can
organize tab groups, change supported reader controls, read and edit PDF
comments, close/reopen tabs, safely rename eligible files, find and open
Collection documents, and perform supported document jobs. It asks tools for
evidence as needed rather than sending every open document with each question.

**Stop cancels future work.** If a requested change already completed, it stays
in effect until undone. **Undo action** reverses the latest assistant change
when its result still matches the receipt. If the user or another process has
changed that state or file, Undo refuses rather than replacing the newer work.
This is action-scoped undo, not a general file rollback facility.

Document jobs create separate outputs under `Assistant Exports` in the
application-support directory; originals remain unchanged. PDF export converts
an open supported text document to PDF or makes a PDF copy. OCR and translation
run locally and require their tools to be installed already. Protected PDFs
must first be copied without a password. Scanned documents need OCR before
translation or text-based answers can work. Stop cancels a running job. Undo
closes its generated tab and deletes the output only while that exact output is
unchanged.

Automatic analysis sends a bounded sample for a short summary, keywords and
suggested chapters after a successful document open when its setting is on;
authored bookmarks/headings take precedence. The analysis is cached by
content, layout and model. Unchanged cached analysis is reused. A session is
limited to 20 uncached analysis requests, each sampling no more than 30 pages
or 64,000 characters. Collection historical previews and editable copies of
older revisions are excluded; only the current/latest source is analyzed.
Analysis skips locked files, files over 256 MiB, and documents with no
extractable text.

When a compatible latest revision changes, the assistant can update its prior
summary using that summary plus a bounded exact text delta (up to 32,000 changed
UTF-16 code units), rather than sending the full excerpt again. If page
coverage, outline, layout or change size is incompatible, it uses the bounded
excerpt path instead.

## For AI agents

The in-reader assistant is an OpenRouter chat client with a fixed tool schema.
Model-facing tools use opaque IDs, and document text is untrusted evidence. The
assistant can page through the current workspace without opening document
files, then retrieve cached analysis and chapters with `document_metadata`;
read at most 20 pages per call;
search a bounded set of open documents; render page previews; navigate to
revision-checked evidence; organize groups; inspect and alter supported reader
state; read/edit comments; list/open Collection documents; close/reopen tabs;
rename eligible files; and run explicitly requested `document_job` operations
(`ocr`, `translate`, `export-pdf`). It cannot choose arbitrary filesystem
paths, execute shell commands, browse the web, or delete arbitrary originals.

Document reads are bounded to files in the active reader workspace, with
Collection documents accessible only through Collection discovery/open tools.
Cross-document search checks at most 100 pages per document and 16 documents,
and returns at most 50 matches. Search output reports per-document continuation
and partial coverage. Page text reads return at most 20 pages per request.
Responses, messages and tool rounds also have limits; when they are reached,
the assistant reports that the user should narrow the request or start a new
chat. It does not claim that a partial search covered the entire workspace.

The `document_metadata` tool returns cached summary/keyword/chapter metadata
and can list Collection revision IDs, dates, file sizes and diff status without
reading archived document bytes. Supplying a `revisionID` explicitly requests
a lazy text diff against the preceding revision. The diff uses saved text
indexes only; it measures neither image changes nor full-file byte changes. It
compares at most 30 pages and 128,000 combined text characters, with a 4 MiB
limit per index, and labels coverage partial. Missing, encrypted or oversized
indexes report an unavailable status and reason. A first revision and an
identical revision also have explicit statuses.

Mutating tools return action receipts and validate current document revisions
or workspace state before committing. Undo checks the recorded post-action
state. Document jobs write into an app-owned output directory and use exclusive
file creation so an existing path is never replaced. Job Undo removes only a
file that still matches the generated receipt. File rename and comment edits
have explicit writable-file and size limits. Encrypted PDF jobs, arbitrary
deletion, read-only original rename without Save As, and tools not
listed in discovery remain unavailable.

Each provider request asks for OpenRouter no-data-collection and zero-data-
retention routing. If a selected provider cannot honor those parameters, the
request fails without a weaker-privacy retry. This is a routing request, not an
independent guarantee about all intermediaries. Chat may use account credits or
incur provider charges; pricing depends on the selected model and account, and
the reader does not estimate or cap that spend. Interactive chat sends only
the context retrieved for the user's request. Automatic analysis defaults on
for new installations, but cloud requests require completed setup and a
connected OpenRouter account. Existing saved preferences are preserved.

See the [document assistant guide](../document-assistant.md) for setup and
operational detail, and [AI control and Markdown authoring](../agent-interface.md)
for the separate headless CLI/MCP interface. See the [revision analysis validation](../journals/ai-reader/revision-analysis-validation.md)
for the bounded text-delta and history-index implementation details.

Collection working copies can be renamed directly by the assistant. The action
preserves the document’s original source reference, group and version history.
Undo restores both the previous filename and Collection title, and refuses to
overwrite a subsequent rename or edit.
