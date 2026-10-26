# Builds the test corpus (SPEC §12) from LaTeX sources in src/ with latexmk.
# Outputs land in this directory. Fixture 9 (ppt-export.pdf/.pptx) is supplied by Ben, not built here.
# Usage: make            build everything
#        make overlays.pdf
#        make clean

SRCS  := $(wildcard src/*.tex)
PDFS  := $(patsubst src/%.tex,%.pdf,$(SRCS)) malformed.pdf

LATEXMK := latexmk -pdf -interaction=nonstopmode -halt-on-error -cd

.PHONY: all clean

all: $(PDFS)

%.pdf: src/%.tex
	$(LATEXMK) $<
	cp src/$*.pdf $@

# A truncated file: must open without crashing (or fail cleanly).
malformed.pdf: basic-169.pdf
	head -c 20000 $< > $@

clean:
	-latexmk -C -cd $(SRCS)
	rm -f $(PDFS)
