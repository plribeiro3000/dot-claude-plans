# Auxiliary source file — empirical studies index (technical debt / code smells / maintainability)

Raw fetched excerpts, abstracts, and per-tool figures. Fetched 2026-09-02.

---

## arXiv 2304.10778 — "Evaluating the Code Quality of AI-Assisted Code Generation Tools: An Empirical Study on GitHub Copilot, Amazon CodeWhisperer, and ChatGPT"

URL: https://arxiv.org/abs/2304.10778

> "The average technical debt, considering code smells, was found to be 8.9 minutes for ChatGPT, 9.1 minutes for GitHub Copilot, and 5.6 minutes for Amazon CodeWhisperer."

Per the WebSearch tool's synthesis (not independently re-verified sentence-by-sentence against the full PDF body): "newer versions of GitHub Copilot and Amazon CodeWhisperer showed improvement rates of 18% for GitHub Copilot and 7% for Amazon CodeWhisperer." Assessed by the study's evaluation criteria "Code Validity, Code Correctness, Code Security, Code Reliability, and Code Maintainability" per the abstract. This study predates Claude Code / current-generation coding agents (2023) — dated data point, cited as historical baseline only.

---

## arXiv 2603.28592 — "Debt Behind the AI Boom: A Large-Scale Empirical Study of AI-Generated Code in the Wild"

URL (HTML): https://arxiv.org/html/2603.28592v1
URL (abstract): https://arxiv.org/abs/2603.28592

Full abstract (verbatim, fetched from the abs page):
> "AI coding assistants are now widely used in software development. Software developers increasingly integrate AI-generated code into their codebases to improve productivity. Prior studies have shown that AI-generated code may contain code quality issues under controlled settings. However, we still know little about the real-world impact of AI-generated code on software quality and maintenance after it is introduced into production repositories. In other words, it remains unclear whether such issues are quickly fixed or persist and accumulate over time as technical debt. In this paper, we conduct a large-scale empirical study on the technical debt introduced by AI coding assistants in the wild. To achieve that, we built a dataset of 302.6k verified AI-authored commits from 6,299 GitHub repositories, covering five widely used AI coding assistants. For each commit, we run static analysis before and after the change to precisely attribute which code smells, correctness issues, and security issues the AI introduced. We then track each introduced issue from the introducing commit to the latest repository revision to study its lifecycle. Our results show that we identified 484,366 distinct issues, and that code smells are by far the most common type, accounting for 89.3% of all issues. We also find that more than 15% of commits from every AI coding assistant introduce at least one issue, although the rates vary across tools. More importantly, 22.7% of tracked AI-introduced issues still survive at the latest version of the repository. These findings show that AI-generated code can introduce long-term maintenance costs into real software projects and highlight the need for stronger quality assurance in AI-assisted development."

From the HTML body fetch (arxiv.org/html/2603.28592v1):
- Dataset: "we built a dataset of 304,362 verified AI-authored commits from 6,275 GitHub repositories, covering five widely used AI coding assistants" (Abstract as reproduced in HTML render — note the minor count discrepancy vs. the abs-page abstract above, 304,362/6,275 vs 302.6k/6,299; both numbers appear in different renders of the paper, likely different revisions — reported as found, not reconciled)
- Tools: "five assistants with more than 10,000 attributed commits: GitHub Copilot, Claude, Cursor, Gemini, and Devin" (Section 4.1)
- "For code smells, we can see that AI-authored commits fix more issues than they introduce (449,984 vs. 431,850)" (Section 5.3)
- "code smells are by far the most common type, accounting for 89.1% of all issues" (Abstract, HTML render)
- "Claude has the highest issue rate per commit (1.96), while Devin has the lowest (0.87)" (Section 5.2)
- "Claude Code updated the metadata loading logic in ArchiveBox. But the new code introduces two code smells" (Section 5.1, a worked example)
- "potentially insecure code patterns are also detected in 1,038 repositories and 4,158 commits" (Section 5.1)
- "about 40% of AI-generated code in security-sensitive contexts contains critical vulnerabilities" (Section 1)
- "Security issues are the most likely to remain at HEAD (41.1%)" (Section 5.3)
- Per the WebSearch tool's synthesis of the paper (not independently line-verified): "for security, the AI introduced 1.5 times more issues than it fixed, creating a net increase of 7,342 vulnerabilities" — flagged as synthesis, not a directly fetched quote; treat as lower-confidence than the directly-quoted figures above.

This paper does NOT report design/architecture/naming-specific findings — its taxonomy is code smells (mechanically detected, e.g. via static analysis), correctness issues, and security issues. It is the strongest available evidence that Claude specifically (among five tools studied) has a measurably higher per-commit issue rate, but "issue" here means static-analysis-detectable code smell/correctness/security defect, not a solution-altitude or domain-naming judgment failure.

---

## arXiv 2511.10271 — "Quality Assurance of LLM-generated Code: Addressing Non-Functional Quality Characteristics"

URL: https://arxiv.org/html/2511.10271v2

See altitude-gap_sources_axis-b-altitude_1.md for full quotes. Summary: a systematic literature review mapping studies onto ISO/IEC 25010 non-functional quality characteristics; found security most-studied (33.6% of studies), performance efficiency (23.3%), maintainability (17.2%); found LLM code "can produce readable and partially maintainable code, but maintainability is not ensured by default" and "often generate[s] code with poor modularity and structure."

---

## arXiv 2508.00700 — "Is LLM-Generated Code More Maintainable & Reliable than Human-Written Code?"

URL: https://arxiv.org/abs/2508.00700

Full abstract (verbatim):
> "Background: The rise of Large Language Models (LLMs) in software development has opened new possibilities for code generation. Despite the widespread use of this technology, it remains unclear how well LLMs generate code solutions in terms of software quality and how they compare to human-written code. Aims: This study compares the internal quality attributes of LLM-generated and human-written code. Method: Our empirical study integrates datasets of coding tasks, three LLM configurations (zero-shot, few-shot, and fine-tuning), and SonarQube to assess software quality. The dataset comprises Python code solutions across three difficulty levels: introductory, interview, and competition. We analyzed key code quality metrics, including maintainability and reliability, and the estimated effort required to resolve code issues. Results: Our analysis shows that LLM-generated code has fewer bugs and requires less effort to fix them overall. Interestingly, fine-tuned models reduced the prevalence of high-severity issues, such as blocker and critical bugs, and shifted them to lower-severity categories, but decreased the model's performance. In competition-level problems, the LLM solutions sometimes introduce structural issues that are not present in human-written code. Conclusion: Our findings provide valuable insights into the quality of LLM-generated code; however, the introduction of critical issues in more complex scenarios highlights the need for a systematic evaluation and validation of LLM solutions."

Key finding: "in competition-level problems, the LLM solutions sometimes introduce structural issues that are not present in human-written code" — i.e., the more complex/open-ended the problem, the more likely design-structural issues (not just bugs) appear. This is consistent with the "cognitive shortcutting under open-ended, low-guidance conditions" mechanism reported in arXiv 2511.20933 and with the team's own observed example (an open-ended "add validation" task, where the LLM chose per-child validation instead of the batch/aggregate design).

---

## arXiv 2401.14176 — "Copilot Refinement: Addressing Code Smells in Copilot-Generated Python Code" / "Copilot-in-the-Loop"

URL: https://arxiv.org/html/2401.14176v1

10 Python code smell types studied (Table 1): "Long Parameter List (LPL), Long Method (LM), Long Scope Chaining (LSC), Large Class (LC), Long Message Chain (LMC), Long Base Class List (LBCL), Long Lambda Function (LLF), Long Ternary Conditional Expression (LTCE), Complex Container Comprehension (CCC), [and] Multiply-Nested Container (MNC)"

> "MNC (over 40%) is the most common code smell in Copilot-generated Python code. Among the 8 types of code smells detected in Copilot-generated code, LPL (21.6%) ranks the second." (Section 4.1.2)

> "Copilot Chat achieves a highest fixing rate of 87.1%, showing promise in fixing Python code smells generated by Copilot itself." (Abstract)

> "new code smells might be introduced when using Copilot Chat to fix the code smells generated by Copilot itself." (Abstract)

Important scope note: all 10 smell types studied here are metric-based/mechanical (length, nesting depth, parameter count) — none relate to naming semantics or architectural/responsibility-placement choices. This paper is evidence that even the mechanically-detectable smell literature does not yet have a standard taxonomy entry for the "solution altitude" failure the engineer describes — that failure sits outside what static-analysis-style code-smell catalogs currently measure.

---

## Cross-cutting observation across all empirical studies gathered

Every peer-reviewed/arXiv-track empirical study found in this research measures quality via: (a) static-analysis code smells (mechanical: length, nesting, parameter count, duplication), (b) security vulnerability counts, (c) bug/defect counts, or (d) coupling/cohesion metrics computed after the fact. None of the empirical studies found define or measure "did the model place the responsibility/computation at the correct level of the system" as a first-class metric — the closest is arXiv 2605.19901's responsibility-separation/cohesion analysis and arXiv 2511.20933's cohesion/coupling-reasoning study. This absence is itself a finding, reported in SPIKE.md's "what remains uncertain" section.
