ifndef SPDF_AI_READER_TESTS_INCLUDED
SPDF_AI_READER_TESTS_INCLUDED := 1
# Production-linked AI acceptance binaries. No user app or network is launched.
include mac/tests/workspace-probe.mk
AI_READER_BASE_OBJS := $(filter-out $(BUILD)/workspace-probe/mac/tests/SPDFMacWorkspaceProbe.o,$(MAC_WORKSPACE_PROBE_OBJS))
AI_CONTEXT_TEST := $(BUILD)/SPDFMacAIDocumentContextTests
AI_ANALYSIS_TEST := $(BUILD)/SPDFMacAIAnalysisServiceTests
AI_CHAT_VIEW_TEST := $(BUILD)/SPDFMacAIChatViewTests
$(AI_CONTEXT_TEST): $(AI_READER_BASE_OBJS) $(BUILD)/workspace-probe/mac/tests/SPDFMacAIDocumentContextTests.o $(CORE_OBJS) $(YAML_OBJ) $(MAC_MD4C_OBJ) $(MAC_GUMBO_OBJS) mupdf-libs
	clang++ $(MAC_TARGET_FLAGS) -std=c++17 -fobjc-arc $(AI_READER_BASE_OBJS) $(BUILD)/workspace-probe/mac/tests/SPDFMacAIDocumentContextTests.o $(CORE_OBJS) $(YAML_OBJ) $(MAC_MD4C_OBJ) $(MAC_GUMBO_OBJS) $(MUPDF_LIBS) -framework Cocoa -framework QuartzCore -framework PDFKit -framework ImageIO -framework UniformTypeIdentifiers -framework CoreServices -framework Security -framework LocalAuthentication -lm -Wl,-dead_strip -o "$@"
$(AI_ANALYSIS_TEST): $(AI_READER_BASE_OBJS) $(BUILD)/workspace-probe/mac/tests/SPDFMacAIAnalysisServiceTests.o $(CORE_OBJS) $(YAML_OBJ) $(MAC_MD4C_OBJ) $(MAC_GUMBO_OBJS) mupdf-libs
	clang++ $(MAC_TARGET_FLAGS) -std=c++17 -fobjc-arc $(AI_READER_BASE_OBJS) $(BUILD)/workspace-probe/mac/tests/SPDFMacAIAnalysisServiceTests.o $(CORE_OBJS) $(YAML_OBJ) $(MAC_MD4C_OBJ) $(MAC_GUMBO_OBJS) $(MUPDF_LIBS) -framework Cocoa -framework QuartzCore -framework PDFKit -framework ImageIO -framework UniformTypeIdentifiers -framework CoreServices -framework Security -framework LocalAuthentication -lm -Wl,-dead_strip -o "$@"
$(AI_CHAT_VIEW_TEST): mac/tests/SPDFMacAIChatViewTests.mm mac/SPDFMacAIChatView.mm mac/SPDFMacAIChatMarkdown.mm mac/SPDFMacAIChatStore.mm mac/SPDFMacCollectionStyle.mm mac/SPDFMacGroupActionButton.mm $(patsubst %.mm,$(BUILD)/workspace-probe/%.o,$(MAC_MARKDOWN_SRCS)) $(MAC_MD4C_OBJ) $(MAC_GUMBO_OBJS) $(CORE_RECOLOR_OBJ)
	clang++ $(MAC_TARGET_FLAGS) -std=c++17 -fobjc-arc -Imac mac/tests/SPDFMacAIChatViewTests.mm mac/SPDFMacAIChatView.mm mac/SPDFMacAIChatMarkdown.mm mac/SPDFMacAIChatStore.mm mac/SPDFMacCollectionStyle.mm mac/SPDFMacGroupActionButton.mm $(patsubst %.mm,$(BUILD)/workspace-probe/%.o,$(MAC_MARKDOWN_SRCS)) $(MAC_MD4C_OBJ) $(MAC_GUMBO_OBJS) $(CORE_RECOLOR_OBJ) -framework Cocoa -framework QuartzCore -framework ImageIO -Wl,-dead_strip -o "$@"
.PHONY: mac-ai-reader-acceptance
mac-ai-reader-acceptance: $(AI_CONTEXT_TEST) $(AI_ANALYSIS_TEST) $(AI_CHAT_VIEW_TEST)
	"$(AI_CONTEXT_TEST)"
	"$(AI_ANALYSIS_TEST)"
	"$(AI_CHAT_VIEW_TEST)"

endif
