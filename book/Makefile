# Build the book: two LuaLaTeX passes, the second for the contents and the references.
#
#   make                   build embedded-linux.pdf, dated today
#   make VERSION=book-v2   the same, with the release's version on the title page
#   make clean             remove everything the build writes
#
# The figures are the lectures' own PNGs, and the three headers the course ships as
# specifications are typeset straight from their files, so a change to either is a change to the
# book on the next build.

ROOT    := $(abspath $(dir $(lastword $(MAKEFILE_LIST)))/..)
BOOK    := $(ROOT)/book
BUILD   := $(BOOK)/build
VERSION ?=
LATEX   := lualatex -interaction=nonstopmode -halt-on-error -file-line-error \
           -output-directory=$(BUILD)
# The book, with its version defined before anything is read; -jobname keeps the output book.pdf.
BOOKTEX := $(LATEX) -jobname=book '\def\bookversion{$(VERSION)}\input{book.tex}'

SOURCES := book.tex linuxbook.sty linuxbook.lua \
           $(wildcard front/*.tex chapters/*/*.tex back/*/*.tex)
CODE    := $(ROOT)/tools/qa-dev/qa-dev.h $(ROOT)/lectures/L05/lab/qa_fifo.h \
           $(ROOT)/lectures/L12/lab/qa_latency.h \
           $(wildcard $(ROOT)/lectures/*/appendix/images/*.png $(ROOT)/exam/images/*.png)

.PHONY: all clean FORCE

all: embedded-linux.pdf

# The version the last build was made for. The file is rewritten only when VERSION changes, so a
# new version, or none after one, rebuilds the title page and nothing else does.
$(BUILD)/version: FORCE
	@mkdir -p $(BUILD)
	@echo '$(VERSION)' | cmp -s - $@ || echo '$(VERSION)' > $@

# LuaLaTeX has to run until the contents and the cross-references stop moving. Two passes are
# usually enough; a change that shifts the contents by a page needs a third, and a book built one
# pass short carries page numbers that are quietly wrong, which is not a failure anything reports.
embedded-linux.pdf: $(SOURCES) $(CODE) $(BUILD)/version
	@mkdir -p $(BUILD)
	@pass=1; while [ $$pass -le 4 ]; do \
	    cp -f $(BUILD)/book.aux $(BUILD)/book.aux.prev 2>/dev/null || true; \
	    cp -f $(BUILD)/book.toc $(BUILD)/book.toc.prev 2>/dev/null || true; \
	    echo "lualatex pass $$pass"; \
	    (cd $(BOOK) && $(BOOKTEX) >/dev/null) \
	        || (tail -40 $(BUILD)/book.log; exit 1) || exit 1; \
	    if [ $$pass -ge 2 ] \
	        && cmp -s $(BUILD)/book.aux $(BUILD)/book.aux.prev \
	        && cmp -s $(BUILD)/book.toc $(BUILD)/book.toc.prev; then break; fi; \
	    pass=$$((pass + 1)); \
	done
	@grep -E "^(Overfull|Underfull)|Warning" $(BUILD)/book.log | sort | uniq -c | sort -rn | head -20 || true
	@! grep -q "There were undefined references" $(BUILD)/book.log || \
	    (echo "error: undefined references; see $(BUILD)/book.log"; exit 1)
	cp $(BUILD)/book.pdf $@

clean:
	rm -rf $(BUILD) embedded-linux.pdf
