# Notation Guide

## Mathematical Expressions

Use LaTeX for all equations in documentation:
- Inline: `$I_x^2$` renders as $I_x^2$
- Display: `$$\sum I_x^2$$` renders centered: $$\sum I_x^2$$

## Diagrams

Use plain text descriptive labels:
- **Yes**: "Gradient Accumulation"
- **No**: "ΣIx² Accumulation" (breaks Mermaid parser)

Ensure blocks have a white background so they do not break if the viewer is using Dark Mode.

## Code

Use ASCII-safe notation:
- Variables: `Ix`, `Iy`, `It`
- Squared: `Ix_sq` or `Ix^2` (in comments)
