# The Book
The course typeset as a book with LuaLaTeX: twelve chapters, one per lecture, in the course plan's
four parts; then, as appendices, worked solutions to every exercise that is not code, and the two
self-assessment papers with their model answers.

---

## Building it

```bash
sudo apt -y install make texlive-luatex texlive-latex-extra fonts-texgyre fonts-texgyre-math \
                    fonts-dejavu-core
make -C book                   # Writes book/embedded-linux.pdf, dated today.
make -C book VERSION=book-v2   # The same, with the version on the title page.
make -C book clean             # Removes book/build/ and the PDF.
```

The build runs LuaLaTeX twice, so the contents and the cross-references settle, then prints any
overfull or underfull lines and LaTeX warnings it found, and fails if a reference is left undefined.
A clean build prints nothing after the two `lualatex` lines except a handful of mildly underfull
ones. Nothing in it needs the kernel, QEMU or the container: the book is built from the files in
this repository alone.

---

## Releasing a new edition
The PDF is committed, as `book/embedded-linux.pdf`, so the repository always holds a readable copy;
rebuild it with `make -C book` and commit it along with any change to the book. Each edition is
also published as a GitHub release, with its version on the title page. Push a tag named
`book-v*`:

```bash
git tag book-v2
git push origin book-v2
```

The [Book workflow](../.github/workflows/book.yml) then builds the PDF with the tag on its title
page and attaches it to a release of the same name.

---

## What is where

```text
book.tex                The book: front matter, twelve chapters in four parts, appendices, in order.
linuxbook.sty           Every visual decision: page, type, colours, code blocks, exercises.
linuxbook.lua           How \code{...} typesets inline C and shell (#, \n and line breaks).
front/                  Title pages and preface.
chapters/NN/            Chapter NN: chapter.tex (the opener), one file per theory appendix of
                        lecture LNN, summary.tex (the review) and exercises.tex.
back/solutions/         Appendix A: the solutions to the exercises that are not code.
back/exam/              Appendices B to F: what the papers are for, the papers, their answers.
```

Every `.tex` file typeset from course material starts with a comment naming its source, for
example:

```tex
% Section 5.2, from lectures/L05/appendix/b_the_driver.md.
```

---

## Updating the content
The course material is the source of truth, and the book follows it. **Three kinds of content
behave differently:**
* **The figures and the printed headers update themselves.** The book prints the lectures' own
  PNGs from `lectures/*/appendix/images` and `exam/images`, so `make diagrams` changes the book on
  its next build. The three headers the course ships as specifications, `qa_fifo.h` in §5.2,
  `qa-dev.h` in Chapter 6 and `qa_latency.h` in Chapter 12, are typeset straight from their files
  (`\cfile{...}`).
* **Prose and the code snippets in the text do not.** A chapter's text is a typeset copy of its
  lecture's markdown. When you change a lecture appendix, make the same change in the `.tex` file
  whose header names it. The same holds for `exam/*.md` and `back/exam/`. A README's lecture plan
  is the plan for the live hour, not the material, and is not typeset; its agenda, objectives,
  questions and next-lecture list are, in the chapter's opener and review.
* **The solutions exist only here.** `back/solutions/` is written for the book, and the repository
  publishes no other copy. When an exercise that is not code changes, its solution changes with it.
  The Code exercises have no solution, here or anywhere: each is checked by running it.

A few conventions, so an edit reads like the rest of the book:
* Code blocks: `ccode` (C), `shell`, `makecode` (Makefiles and Kbuild; recipe lines keep their
  tab), and `console` (program output, device trees, Kconfig entries, plain text).
* Inline code: `\code{...}`, written exactly as in the source. Inside it, write `\%` for `%`,
  `\{` or `\}` for a brace, `\\` for a backslash and `\#` for `#`. A path is `\file{...}`.
* References: `\secref{c5:app:b2}` is the section typeset from B.2 of L05, printed §5.2.2, and
  `\secref{c5:app:a:read-and-write}` is a `###` heading, labelled with its GitHub anchor.
  `Exercise~\ref{c5:ex:4}` is C.4 of L05; the book gives each exercise its lecture's number.
* Exercises: `\exercise[fill]{Title}{Kind}`, with the fill that goes with the kind (Recall
  `fillaccent2`, Hand calculation `fillaccent3`, Design `fillaccent4`, Code none, Cross-check
  `fillaccent`), `\xpart{a}` for a lettered part, and `\checkyourself` for a Check yourself line.
  A solution is headed `\solution[fill]{c5:ex:4}{Title}{Kind}`.
* Figures: `\lecturefigure[fraction]{path}{caption}{label}`, where the fraction is the PNG's width
  in pixels over 1100, so that every figure is printed at the same scale.
* A new lecture appendix is a new file in `chapters/NN/`, `\input` from that chapter's
  `chapter.tex`.
* The repository's URL is named once, as `\repourl` in `linuxbook.sty`.

---

## License
The book, its text, figures and solutions and the PDF built from them, is licensed under
[CC BY-NC-SA 4.0](../LICENSE-CONTENT), like the course material it is typeset from. This
directory's build files (`linuxbook.sty`, `linuxbook.lua`, `Makefile`) are released under the
repository's [MIT License](../LICENSE), like the rest of the course's code, and so may the code
examples printed in the book be used, apart from excerpts quoted from the kernel's own source,
which remain under its license, GPL-2.0.
