# AI reader preview

- Ask questions about open documents and get answers linked to retrieved pages.
- Preview pages, organize groups, control the reader, and manage supported PDF comments.
- Request a separate PDF export, OCR copy or translated copy; stop work and undo eligible changes.
- Connect an OpenRouter model in Settings. Chat is optional; automatic analysis has its own opt-in.

---

## For readers

Open **Settings → AI & documents** to connect OpenRouter in a browser or save an API key in
Keychain. Select a provider model ID; ShenzhenPDF validates it and reports
whether document tools are supported. Enable document chat before sending a
question. Press **⌘K**, then Return with an empty search field to start a new
chat. Return sends a message, Shift-Return adds a line. With a nonempty search
query, Return continues to open the selected search result; use the explicit
Ask action to start a new chat with that query as a draft, then press Return to send. The chat can be stopped with
**Stop** or closed with Escape. Saved conversations are available from **Chats**;
deleting chats removes their transcripts and saved page previews from this Mac.

Answers can cite exact retrieved passages and show relevant page previews.
Selecting a citation returns to that document and page. The assistant can
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

Automatic analysis is a separate setting. When enabled, a successful open can
send a sample for a short summary, keywords and suggested chapters; authored
bookmarks/headings take precedence. The analysis is cached by content, layout
and model. Unchanged cached analysis is reused. A session is limited to 20 new
analysis requests, each sampling no more than 30 pages or 64,000 characters.
Analysis skips locked files, files over 256 MiB, and documents with no
extractable text.

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

Mutating tools return action receipts and validate current document revisions
or workspace state before committing. Undo checks the recorded post-action
state. Document jobs write into an app-owned output directory and use exclusive
file creation so an existing path is never replaced. Job Undo removes only a
file that still matches the generated receipt. File rename and comment edits
have explicit writable-file and size limits. Encrypted PDF jobs, arbitrary
deletion, unsupported read-only/Collection-working-copy rename, and tools not
listed in discovery remain unavailable.

Each provider request asks for OpenRouter no-data-collection and zero-data-
retention routing. If a selected provider cannot honor those parameters, the
request fails without a weaker-privacy retry. This is a routing request, not an
independent guarantee about all intermediaries. Chat may use account credits or
incur provider charges; pricing depends on the selected model and account, and
the reader does not estimate or cap that spend. Automatic analysis is opt-in;
interactive chat sends only the context retrieved for the user's request.

See the [document assistant guide](../document-assistant.md) for setup and
operational detail, and [AI control and Markdown authoring](../agent-interface.md)
for the separate headless CLI/MCP interface.
