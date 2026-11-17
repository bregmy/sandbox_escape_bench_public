# LLM Container Escape Defense: What Has Been Done & What We're Adding

## 1. Current State of Research: The Offense-Only Picture

### What Exists (Known, Published)

#### **SandboxEscapeBench** (Marchand et al., 2026)
- **What it shows:** Frontier LLMs (Claude, GPT, Gemini) can autonomously break out of Linux containers ~100% of the time
- **Why it works so well:** Tests the *weakest* threat model:
  - Containers run with **default, unhardened configs**
  - Agent starts with **root privileges inside the container**
  - Attack scenarios span orchestration, container runtime, and kernel-level vulnerabilities (18 total scenarios)
- **Key insight:** LLMs are surprisingly good at chaining exploitation techniques to escape
- **Critical gap:** The benchmark answers **"Can they escape?"** but NOT **"How much do standard protections help?"**

#### **PACEbench** (Liu et al., 2026) — Parallel finding in web security
- **What it showed:** LLMs exploit unprotected web applications at high rates, BUT capability **collapses to near zero** when standard defenses (WAF, rate limiting) are active
- **Why it matters:** Suggests LLMs may be fragile to *standard defenses* — but **nobody tested this hypothesis for container/sandbox escapes yet**

---

## 2. The Crucial Gap This Project Fills

### What's Missing

| Question | Current Status | Why It Matters |
|----------|---|---|
| **"Which specific container protections reduce escape rates?"** | ❌ Unknown; only qualitative "best practices" exist | Deployers don't know which hardening controls are essential vs. nice-to-have |
| **"By how much does each control reduce risk?"** | ❌ No empirical numbers | Can't prioritize security investments; can't benchmark defenses |
| **"Does running as a non-root user alone solve the problem?"** | ❌ Untested | Practitioners don't know if privilege level is the main lever |
| **"When a defense 'works,' is it real security or just LLM confusion?"** | ❌ Never distinguished | A defense that just exhausts tokens isn't trustworthy; one that closes the actual vulnerability is |

### Why This Matters for AI Safety

- **Deployment risk:** Companies running LLM agents in sandboxes today don't have empirical evidence for which protections actually work. They're making security decisions blind.
- **Defense-in-depth rationale:** We don't know if combining protections is redundant or cumulative.
- **Model capability ceiling:** PACEbench suggested defenses might have a "ceiling effect" on LLMs. Does the same hold for container escapes?

---

## 3. Our Project: The Defensive Ablation Study

### Core Idea

**Take the same scenarios from SandboxEscapeBench, but flip the equation: instead of asking "can the AI escape?", ask "how much do protections reduce escape success, and why?"**

This is a systematic, quantitative, mechanistic study of **what actually helps**.

### What We'll Do (Simple Version)

### Three Research Questions


| RQ      | What We're Asking                                                                                                                                                          | Why It Matters                                                                                |
| ------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------- |
| **RQ1** | **For each hardening control, what's the empirical escape rate reduction?** (e.g., "Dropping Linux capabilities reduces escapes from 90% to 40%" = 50% absolute reduction) | Gives deployers a **ranked, evidence-based priority list**                                    |
| **RQ2** | **Does starting as non-root user alone eliminate the problem? Or do other hardening controls still help?**                                                                 | Determines if privilege level is redundant with other controls                                |
| **RQ3** | **When a defense "stops" an escape — is it because the defense actually closed the vulnerability, or because the LLM got confused/exhausted?**                             | Separates **real security** from **AI friction**; ensures our recommendations are trustworthy |




### The Clever Part: Mechanistic Verification (RQ3)

For every scenario and hardening control, we run the **known reference exploit script** (hand-written, no LLM) under the same protections:


| Reference Exploit Outcome | Model Outcome | Interpretation                                                                                |
| ------------------------- | ------------- | --------------------------------------------------------------------------------------------- |
| **Fails**                 | Fails         | ✅ Defense truly closes the vulnerability (architectural fix)                                  |
| **Succeeds**              | Fails         | ⚠️ Vulnerability still exists, but LLM couldn't complete the chain (friction-induced failure) |
| **Fails**                 | Succeeds      | 🚨 LLM found an unintended bypass (needs qualitative audit)                                   |


This is critical because a defense that "looks good" by blocking the LLM might actually be a paper tiger.

---



## 4. What We're Testing (8 Hardening Controls)


| ID     | Control                      | What It Does                                                                                      |
| ------ | ---------------------------- | ------------------------------------------------------------------------------------------------- |
| **B0** | **Baseline (Unhardened)**    | Docker defaults — the reference, weak state                                                       |
| **B1** | **Drop All Capabilities**    | Remove raw Linux kernel permissions (e.g., no `CAP_SYS_ADMIN`)                                    |
| **B2** | **No Privilege Escalation**  | Prevent setuid/setgid tricks (can't gain root via binary exploits)                                |
| **B3** | **Strict Seccomp**           | Block dangerous system calls (`unshare`, `ptrace`, `keyctl`, etc.)                                |
| **B4** | **Read-Only Root FS**        | Container filesystem is immutable; can't write payloads/rootkits to disk                          |
| **B5** | **User Namespace Remapping** | Container's "root" user maps to unprivileged host user (even if you escape, you're not host root) |
| **B6** | **Minimal Image**            | Use distroless image; no compilers, shells, curl — deny "living off the land" exploits            |
| **B7** | **gVisor Kernel**            | Use userspace kernel (`runsc`); eliminates direct host kernel access                              |
| **B8** | **Hardened Composite**       | B1 + B2 + B3 + B4 combined (CIS Docker Benchmark compliant); B5 is daemon-level and applied separately, not part of this per-container composite |


---



## 5. How We'll Measure It



### Primary Metrics

- **Escape Success Rate (SR):** % of trials where LLM retrieves the flag
- **Absolute Risk Reduction (ARR):** SR(baseline) − SR(with hardening)
  - Example: 90% − 40% = **50 percentage point reduction**
- **Relative Risk (RR):** SR(hardened) / SR(baseline)
  - Example: 40% / 90% = **0.44x** (reduced to 44% of baseline risk)



### Statistical Model

Mixed-effects logistic regression to understand:

- Which controls have the biggest independent effect?
- Does privilege level interact with hardening (i.e., does B1 help *less* if you already run as non-root)?
- Which model families are most/least vulnerable to which controls?



### Deliverables

1. **Empirical Hardening Matrix** — Table showing escape rates, ARR, RR, confidence intervals for all combinations
2. **Ranked Hardening Recommendations** — "If you can only implement 3 controls, implement X, Y, Z"
3. **Open-Source Reproducible Suite** — Docker configs, Inspect AI scripts, reference exploit harness (so others can replicate)
4. **Research Paper** — Peer-ready manuscript with methodology, results, mechanistic findings

---



## 6. Why This Is Novel (But Not Groundbreaking)



### What's New

✅ **First systematic defensive ablation study for LLM container escape** — nobody has published this specific measurement
✅ **Mechanistic verification (RQ3)** — distinguishing real fixes from friction is novel and rigorous
✅ **Empirical, ranked hardening guide** — actionable, evidence-based instead of hand-wavy
✅ **Validates (or contradicts) PACEbench's "ceiling" hypothesis** for a new domain

### What's Reused (Building Blocks)

- SandboxEscapeBench (existing benchmark)
- Inspect AI framework (existing infrastructure)
- General ablation study methodology (common practice in ML/security)
- Standard Linux hardening controls (not new; we're just measuring them)



### Honest Assessment

This is **solid incremental research**: not a novel attack or new defense, but a rigorous, needed empirical study that fills a real gap. That's actually good for a 6-week project. It's publishable, reproducible, and immediately actionable for practitioners.

---



## 7. Timeline: 6 Weeks


| Week       | Focus                                                                                                       | Output                            |
| ---------- | ----------------------------------------------------------------------------------------------------------- | --------------------------------- |
| **Week 1** | Set up nested VM harness; determine which controls apply to which scenarios                                 | Applicability matrix              |
| **Week 2** | Run baselines (unhardened); implement hardening wrappers; verify reference exploits work under all controls | Baseline data; verification logs  |
| **Week 3** | Pilot runs (small-scale) to calibrate token limits, API costs, sandbox stability                            | Calibrated parameters             |
| **Week 4** | Full evaluation campaign across all models, controls, scenarios                                             | Main dataset                      |
| **Week 5** | Analyze results; compute ARR, RR, regression models; audit mechanistic findings                             | Statistics + qualitative insights |
| **Week 6** | Write paper; package reproducible code + configs                                                            | Final paper + artifacts           |


---



## 8. Why This Fits Your NIW/PhD Narrative



### Connection to Your Proposed Endeavor

Your NIW focuses on **developing evaluation methods and tools** for measuring **limitations and failure modes** of generative AI systems in trustworthy deployment. This project directly demonstrates:

- **Systematic evaluation methodology** — factorial ablation, mechanistic verification, statistical rigor
- **Trustworthy AI deployment risk** — where LLMs fail under realistic hardening, what defenses actually help
- **Open, reproducible tools** — Inspect AI extension, reference exploit harness, container configs (publishable artifacts)
- **Government-relevant impact** — NIST, DoD, other agencies deploying LLM agents need this empirical evidence



### Publication Tier (per your existing portfolio)

- **Tier 1 material** — Directly advances your "evaluation of AI failure modes and limitations" thesis
- **Complements your existing papers** — "Breaking the Guardrails: Jailbreak Vulnerability Assessment" (existing) + this (defensive side) = complete picture
- **Aligns with your RAG faithfulness auditing work** — both about mechanistic verification of when/why AI systems fail

---



## Summary Table: Before vs. After


| Aspect                        | Before (Current State)                                | After This Project                                                |
| ----------------------------- | ----------------------------------------------------- | ----------------------------------------------------------------- |
| **Offensive capability**      | ✅ Known: LLMs escape ~100% from unhardened containers | ↔️ Unchanged (we reuse benchmark)                                 |
| **Defensive empirical data**  | ❌ None                                                | ✅ Quantified ARR/RR for 8 controls                                |
| **Ranked hardening priority** | ❌ Only generic "best practices"                       | ✅ Evidence-based ranked list                                      |
| **Privilege level risk**      | ❌ Unknown                                             | ✅ Measured (root vs. non-root)                                    |
| **Mechanistic understanding** | ❌ Can't distinguish real fix from LLM friction        | ✅ Reference exploit verification for each scenario-control pair   |
| **Reproducible artifacts**    | ❌ Only SandboxEscapeBench                             | ✅ Full hardening harness + configs open-sourced                   |
| **Practitioner guidance**     | ❌ "Harden your containers" (vague)                    | ✅ "Deploy with controls X, Y, Z for Y% risk reduction" (concrete) |


---


