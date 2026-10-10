# Document assistant (macOS)

The document assistant answers questions about PDFs, Markdown and other open
documents, with citations that lead back to retrieved pages. It can show page
previews, organize open tabs, adjust reader controls, edit PDF comments, and run
some document jobs. It is optional and uses an OpenRouter model you connect.
This guide describes the current macOS implementation; Linux and Windows do not
provide this chat interface.

## First setup and account

On the first normal launch, a four-step setup appears after the reader is
ready. It does not appear on every launch after you finish. The steps are:

1. **Full Disk Access.** Open macOS System Settings to grant access to protected
   folders such as Mail and Safari downloads. You can continue without it;
   macOS will ask for access if a later open needs it. ShenzhenPDF may need to
   be reopened after granting access. Setup does not add an Accessibility step.
2. **Collection.** Choose whether to keep local copies and history, set its
   location, and choose storage management. Dynamic uses a selectable 50–80% (80% by default) of free disk
   space plus the space already used by Collection, adjusting as disk use
   changes. Move location transfers and verifies Collection files, then removes
   the old stored data; small routing records keep existing tabs working. If editable
   Collection documents exist, moving to a different disk is refused to protect
   in-progress saves; moving to another folder on the same disk is supported.
   Static sets a fixed limit; Unlimited is also available. Cleanup
   applies to stored history, never to originals.
3. **OpenRouter.** Connect in your browser, or reveal the API-key field when
   you choose to use a key. Keys are stored in this Mac's Keychain. Open the
   model picker to load its searchable catalog; it includes models that support
   tool calls. The default model ID is `deepseek/deepseek-v4.1-flash`, subject
   to current catalog availability.
4. **Default reader.** Search supported file types and set ShenzhenPDF as the
   default independently for each type you choose.

The AI step explains that document text is sent to OpenRouter for background
summaries and missing chapters, and that this uses account credits. New
installations default document chat and automatic analysis to on; saved choices
from existing installations are preserved. Defaults do not permit cloud work
until setup is complete and an OpenRouter account is connected. **Done** returns
you to the reader and does not make Settings appear at every startup. You can
change chat and automatic analysis later under **Settings → Settings & AI… → AI settings**.
Startup and background Keychain access are non-interactive: a locked or denied
credential does not trigger a Keychain password prompt. Credentials remain in
Keychain, and can be reconnected from AI settings when needed.

Turning chat off cancels an active chat request; turning automatic analysis off
stops analysis work.

Model settings, setup progress and chat transcripts are stored locally under
`~/Library/Application Support/ShenzhenPDF/`; the credential itself is not
written there. ShenzhenPDF validates the selected model through OpenRouter and
shows the catalog's document-tool support status. Availability may change, so
the current catalog and connection status are authoritative.

## Ask and manage chats

Press **⌘K**, then press **Return** while the search field is empty to open a new
chat. Type a question and press **Return** to send; **Shift-Return** inserts a
line break. With text in the search field, Return keeps its usual search-result
behavior. Use the explicit **Ask** action to start a new chat with that query as a draft, then press Return to send.
Press **Escape** or **Close** to leave chat.

The chat toolbar offers **New chat**, **Chats**, **Undo action**, **Settings**,
and **Close**. Chats are saved on this Mac. The Chats view lets you reopen a
conversation or delete one or all conversations; deletion asks for confirmation
and removes transcripts and their saved page previews, not documents or
Collection history. Answers render Markdown and can include local page previews
and clickable citations. A citation is accepted only when it matches evidence
retrieved in that conversation and the document revision/layout remains valid.

Use **Stop** to cancel the current model request or queued tool work. A change
that already completed remains in place; use **Undo action** to reverse the
latest assistant action when the result has not changed since. Undo never
overwrites intervening edits. Up to 32 workspace/reader actions and 8
file/document actions are retained for Undo. A failed or stale Undo reports
that it could not safely apply.

## What the assistant can access and change

The model receives opaque document IDs and titles from the current reader
workspace, then retrieves evidence as needed. Its tools can:

- page through groups and open tabs without reading their files, then request
  cached summaries, keywords and chapters for a selected document;
- search open documents and read bounded page text;
- render a requested page preview and show a document at a cited page;
- create, rename, move, collapse, hide or expand tab groups;
- read the current reader state and change supported controls such as page,
  zoom, theme, sidebar, map, find query, text size and rotation;
- read, add, edit or delete comments in the currently displayed writable PDF;
- close and reopen tabs, rename a supported open file, and list/open documents
  in Collection;
- run a requested PDF export, OCR or translation job as a separate output.

Changes are scoped to the current reader and the tools listed above. Creating a
group, changing controls, navigation, comments, closing tabs, renaming, opening
Collection items and document jobs return action receipts for safe Undo. Group
or control Undo is refused if the relevant state has changed. File Undo checks
the resulting file identity/content before restoring or removing anything.

OCR, translation and export make a new PDF; the source stays unchanged. Outputs
go into an `Assistant Exports` folder in the application state directory. OCR and translation
need their local tools already installed. Assistant jobs do not install tools
or ask to install them, and protected PDFs must first be made into an
unprotected copy. Translation requires supported source and target language
codes and extractable text; scan-only PDFs need OCR first. Undo closes the
generated tab and removes the output only if it is still the exact generated
file.

## Automatic summaries and Collection history

Automatic analysis is cached by source content, document layout and model.
For Collection documents it applies to the current/latest source only; an
immutable historical preview or an editable copy based on an older saved
revision does not receive a separate automatic summary. Authored bookmarks and
Markdown headings remain authoritative. Scans without extractable text are
reported as unavailable for analysis rather than given invented chapters.

The assistant's `document_metadata` tool can return Collection revision count,
date, file sizes and whether a text diff has been computed. Listing that history
reads Collection metadata only; it does not read or compare archived file
bytes. A caller can pass a specific `revisionID` to request a diff against the
preceding revision. That request lazily uses the saved text indexes. It reports
added and removed UTF-16 text units and marks the result partial. It does not
compare images or full file bytes. It checks at most 30 pages and 128,000
combined indexed text characters, with a 4 MiB read limit per index. Missing,
encrypted or oversized indexes return an explicit unavailable status and
reason; a first revision and identical revisions also have explicit statuses.

When a compatible latest-document revision changes, automatic analysis can
update its prior summary, keywords and chapters using the previous analysis and
a bounded text delta, instead of resending the full excerpt. The delta is
limited to 32,000 changed UTF-16 code units. If page coverage, outline, layout
or change size is incompatible, analysis falls back to the normal bounded
excerpt. In either case, analysis remains limited to up to 30 pages and 64,000
characters. See [revision analysis validation](journals/ai-reader/revision-analysis-validation.md)
for the implementation record.

## Privacy, model use and limits

Each model request goes to OpenRouter over HTTPS and requests provider
no-data-collection and zero-data-retention routing. A model that cannot honor
those options may reject the request; ShenzhenPDF does not retry with weaker
privacy settings. These routing parameters are a request to OpenRouter, not a
claim that every network intermediary has independently verified retention
behavior. Only context needed for the current question is retrieved and sent;
automatic analysis sends its own bounded sample when separately enabled.
Document text and tool results are treated as untrusted evidence, not as
instructions. Filesystem paths are resolved locally and not included in the
model-facing tool fields.

OpenRouter account usage may incur charges or require credits, depending on the
selected model and account. ShenzhenPDF does not estimate or cap chat spending.
Automatic analysis is limited to 20 uncached requests per reader session;
cached hits do not use that allowance. It samples up to 30 pages and 64,000
characters per request, and only proposes chapters for documents without an
authored outline. Documents larger than 256 MiB, locked files and documents
without extractable text are not automatically analyzed. A changed file or
layout invalidates an in-flight result.

Chat has a 32,000-character message limit, a 160-message conversation limit,
up to 12 model/tool rounds per send, and a 400,000-byte serialized context
limit. Start a new chat or narrow the question when a limit is reached. Tool
requests are also bounded: workspace discovery returns 50 items by default
(up to 100) with independent continuation cursors for groups and documents;
page reads return at most 20 pages per call; a
cross-document search inspects at most 100 pages per document, up to 16 open
documents, and returns at most 50 matches. The result reports partial coverage
and documents/pages not reached. It does not silently stand for a full-library
search.

Other current boundaries:

- The assistant reads only documents open in this reader workspace, plus
  documents explicitly discovered and opened through Collection. It does not
  browse arbitrary folders or the web, run shell commands, or access another
  app's documents.
- OCR and translation are local jobs, but the assistant does not install or
  configure their dependencies. Encrypted PDFs are not supported by assistant
  export/OCR/translation jobs.
- Safe rename supports regular writable files up to 32 MiB in their current
  folder. Collection working copies and read-only files use the native Rename
  or Save As flow.
- Reversible PDF comment editing and page rotation are limited to supported
  writable PDFs up to 32 MiB. Other PDF edits are not exposed.
- There is no arbitrary original-file deletion tool. Undo is conditional on
  the result still matching the receipt; it is not a general rollback system.

See [AI control and Markdown authoring](agent-interface.md) for the separate
command-line/MCP interface. Its inspect/open commands are explicit integrations
and do not use the chat provider.
