# Document assistant (macOS)

The document assistant answers questions about PDFs, Markdown and other open
documents, with citations that lead back to retrieved pages. It can show page
previews, organize open tabs, adjust reader controls, edit PDF comments, and run
some document jobs. It is optional and uses an OpenRouter model you connect.
This guide describes the current macOS implementation; Linux and Windows do not
provide this chat interface.

## Set it up

Open **Settings → AI & documents** from the chat, or open **Settings** from the reader.
Connect OpenRouter in the browser, or enter an OpenRouter API key. The key is
stored in this Mac's Keychain; model settings and chat transcripts are stored
locally under `~/Library/Application Support/ShenzhenPDF/`. Choose a model in
Settings; ShenzhenPDF checks the selected identifier against OpenRouter and
reports whether document tools are supported. The default identifier is
`deepseek/deepseek-v4.1-flash`, but availability can change and the connection
status is the authority.

Enable **document chat** to send questions. Automatic document analysis is a
separate option: when enabled, after a document is opened it can send a bounded
sample to generate a short summary, keywords and suggested chapters. It does
not replace authored PDF bookmarks or Markdown headings. No document content is
sent by automatic analysis while that option is off. Disconnecting removes the
saved key and disables chat. Turning chat off also cancels an active request.

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
