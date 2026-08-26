#ifndef SPDF_SELECTION_H
#define SPDF_SELECTION_H

#include "mupdf/fitz.h"
#include "shenzhen_pdf_core.h"

/* Core-private bridge: keeps spdf_document opaque outside its owning module. */
int spdf_selection_document_access(spdf_document* doc, int page_index, fz_context** ctx_out, fz_document** doc_out,
                                   char* err, size_t err_len);

#endif
