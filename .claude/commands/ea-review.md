# /ea-review — Review an Expert Advisor for Quality & Safety

Audit an EA file for convention compliance, risk rule adherence, and common bugs.

## Usage
```
/ea-review <path/to/EA.mq5>
/ea-review          # reviews all EAs in ea/ directory
```

## What this skill does

Runs two agents in sequence:

### 1. `ea-developer` agent — Code quality review
Checks for:
- [ ] Mandatory structure: `OnInit`, `OnDeinit`, `OnTick` present
- [ ] New-bar guard implemented
- [ ] All adjustable values are `input` parameters
- [ ] Magic number defined as `input`
- [ ] `NormalizeDouble()` used on all prices before orders
- [ ] `OrderSend` / `OrderSend(req,res)` return code checked
- [ ] No `Sleep()` in `OnTick()`
- [ ] Indicator handles released in `OnDeinit()`
- [ ] No hardcoded account IDs, API keys, or file paths

### 2. `risk-validator` agent — Risk rule audit
Checks for:
- [ ] SL defined and ≥ 10 pips minimum
- [ ] TP defined (or documented trailing/time exit)
- [ ] Position sizing uses account balance (not fixed lots)
- [ ] Daily loss cap implemented
- [ ] Max open trades gate implemented
- [ ] Spread check before order placement

## Output

Produces a review report listing:
- PASS / FAIL for each checklist item
- Line number references for failures
- Required fixes (blocking) vs suggestions (non-blocking)
- Overall verdict: READY / NEEDS FIXES / REJECT
