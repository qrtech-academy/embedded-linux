# Written Examinations

Two complete four-hour papers for **Embedded Linux and Kernel Drivers**.

```text
paper_a.md              Paper A, questions only. Hand this out.
paper_a_solutions.md    Paper A, model answers with marks.
paper_b.md              Paper B, questions only.
paper_b_solutions.md    Paper B, model answers with marks.
```

---

## What these are for

The course as written has **no exam and nothing is marked**. What you get instead is a lab per
lecture, checked on the target by `make test`, and eight to ten exercises per lecture ending in a
Cross-check that makes you compute a number by hand and then measure it.

These papers do not replace that. **They are here to test your own skills and knowledge, nothing
more.** They gate nothing, they are not a qualification, and no part of the course requires them.
Nothing in the repository depends on them and `make test` does not know they exist. They are useful
where a written result is wanted anyway, for a certifying employer or a formal course credit, and
useful on their own for finding out what you can reconstruct with nothing in front of you.

**Take one after the course is over.** Every paper draws on all twelve lectures, so sitting one
partway through examines material nobody has taught you yet, and the result says more about how far
you have read than about what you have understood. The intended point is after L12, once the driver
probes off a device tree, services interrupts, blocks readers correctly, registers with two
subsystems, and has had its latency characterised.

---

## The two papers

Both cover the whole course, L01 to L12, and share no question. Either can be used alone; use both
as a main sitting and a resit, or in alternate years.

They do **not** weight the course identically, and that is deliberate.

### Paper A

| Question | Topic                                   | Lectures | Marks   |
| -------- | --------------------------------------- | -------- | ------- |
| 1        | The image, and the licence on it        | L01      | 12      |
| 2        | Asking a running kernel a question      | L02      | 8       |
| 3        | Configuring a kernel, and what it costs | L03      | 10      |
| 4        | A module, written out                   | L04      | 12      |
| 5        | The character device contract           | L05      | 12      |
| 6        | An address, translated and mapped       | L06, L10 | 12      |
| 7        | A race, traced                          | L07      | 10      |
| 8        | An interrupt, acknowledged              | L08      | 10      |
| 9        | A reader put to sleep                   | L09      | 8       |
| 10       | Frameworks, and the trade               | L11, L12 | 6       |
|          |                                         |          | **100** |

### Paper B

| Question | Topic                                          | Lectures | Marks   |
| -------- | ---------------------------------------------- | -------- | ------- |
| 1        | What leaves the building, and when it does not | L01      | 10      |
| 2        | A number that is not what it says              | L02, L09 | 12      |
| 3        | An option that did not survive                 | L03      | 10      |
| 4        | A module that will not load                    | L04      | 12      |
| 5        | A read that returns zero                       | L05, L09 | 12      |
| 6        | A mapping that is wrong                        | L06      | 10      |
| 7        | A deadlock that has not happened               | L07      | 12      |
| 8        | An interrupt that never stops                  | L08      | 10      |
| 9        | A driver that finds its own hardware           | L10, L11 | 6       |
| 10       | Worse average, better maximum                  | L12      | 6       |
|          |                                                |          | **100** |

**Paper A leans towards tracing a mechanism forwards**: an address translated through a device
tree, a module written from nothing, a `read()` traced through its four cases, an interrupt
acknowledged in the right order.

**Paper B leans towards the conditions under which the mechanism stops working**: an option
silently dropped by `olddefconfig`, a module refused at load, a read that returns end of file when
it meant "not yet", a mapping that reads plausible zeros, a deadlock reported by a tool without the
deadlock occurring.

---

## Code on a written paper

Both papers **do ask a candidate to write kernel C**. That is deliberate. This course teaches by
building a driver: the specification of every lab is prose in an appendix and a test suite that
tells you whether what you wrote satisfies it, and a paper that avoided code entirely would be
examining a different course.

The code questions come in two shapes, and neither is a typing exercise:

* **Write one function.** An init function, a `read()`, an interrupt handler. The answers are ten
  to twenty lines each. What carries the marks is the algorithm: the error path, the return value,
  the accessor used, the context the code is running in. Not the syntax.
* **Find what is wrong.** Both papers hand over a listing that compiles and does something other
  than what its author intended. The defects are the ones the course's own appendices single out.

Both papers state in their rubric that answers may be written in kernel C **or in unambiguous
pseudocode**, and that nothing is marked on syntax. A missing semicolon costs nothing. A
`copy_to_user` replaced by `memcpy` costs everything.

---

## Conventions the papers assume

Both papers state these in their own rubric, so a candidate never has to have read this file.

* **The kernel is 6.12 as pinned by the course.** Where an interface has changed within recent
  memory the paper says which version it means, because L03, L05 and L11 all make the point that
  the internal API is not stable.
* **`HZ` is 250** unless a question says otherwise, so a jiffy is 4 ms.
* **The device is `qa-dev`**, whose register map is the one in the course, and any register a
  question depends on is quoted in the question.
* **Only the values nobody could be expected to carry are supplied**: the SPI base of 32, the page
  size, a register offset where one is needed. Address translations, jiffy arithmetic and latency
  budgets are derived, because deriving them is the examinable skill.
* **"State the consequence"** means naming the defect earns half the marks and saying what it does
  to the running system earns the other half. "This is wrong" scores nothing.
* **Where a question asks you to find defects, the number is stated.** Listing more is not
  penalised, but only the stated number is marked, so put your strongest answers first.

---

## Marking

Every solution is written to be marked by somebody who has read the appendices and does not
otherwise write kernel code, so each carries the reasoning rather than the answer alone. Marks are
shown per part.

Three conventions worth agreeing before a paper is marked:

* **Method carries the marks.** A correct approach with an arithmetic slip in it is worth more than
  a correct number with no working, and both papers are built so that later parts consume earlier
  answers. Follow through an error rather than penalising it twice. A candidate who translates a
  device tree address wrongly and then maps their own wrong address correctly has demonstrated the
  examinable skill.

* **The named traps are worth full marks on their own.** Several questions exist entirely to see
  whether a candidate avoids one specific mistake: `read` returning 0 when it meant "not yet", a
  `memcpy` where `copy_to_user` was needed, dividing `/proc/stat` by `HZ` rather than by
  `USER_HZ`, taking `reg` at face value without translating through `ranges`, concluding from a
  clean unlocked run that a lock is unnecessary. Where a solution flags one of these, a candidate
  who walks into it loses those marks and no others.

* **The discussion parts are not decoration.** "State the consequence" and "say what this is blind
  to" are where the course's actual content is, and a paper marked only on the code and the
  arithmetic would pass a candidate who has understood none of it. Paper B in particular is mostly
  these.

**The code questions are answered as checklists, not as listings.** Where a paper asks a candidate
to write a function, the solution states what a correct answer must contain and what each element
is worth, rather than printing a reference implementation. That is deliberate twice over: it is how
these answers are actually marked, since two correct answers will not look alike; and a worked
listing here would be a published solution to the lecture lab that asks for the same thing, which
this course does not provide.

**Where a solution says a candidate may reasonably disagree, they may.** Two questions ask for a
judgement rather than a fact: Paper A's Question 10c and Paper B's Question 8d. Both solutions
state a position and say what an answer arguing the other way must contain to earn the marks.

---
