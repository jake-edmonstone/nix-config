; extends

; Math environments: indent body, dedent the closing $.
(math) @indent.begin
(math "$" @indent.branch .)

; Parenthesised groups: function args, tuples, arrays, dicts, math parens.
; Per-row dedup in the indent engine handles multiple `(` on the same line
; (e.g. `#skills((`) as a single indent level, matching typstyle.
(group) @indent.begin

; [...] content blocks.
; Excluded when the content is the body of a statement/call that already
; owns the indent via upstream @indent.begin on (branch)/(for)/(call),
; or when it's a markup flow content (source_file/section) without brackets.
((content) @indent.begin
  (#not-has-parent? @indent.begin
    "source_file" "section" "branch" "for" "call"))

; { ... } code blocks.
; Excluded when the block body belongs to (branch)/(for) — the upstream
; capture already indents. Critical for `} else { ... }` on different rows.
((block) @indent.begin
  (#not-has-parent? @indent.begin "branch" "for"))

; else-if chains: the grammar nests `#if ... else if ...` as (branch (branch ...)).
; Cancel the inner-branch indent so the chain stays at one level total.
((branch) @indent.dedent
  (#has-parent? @indent.dedent "branch"))

; Multi-line imports: #import "foo": ( ... ) owns its parens directly.
(import) @indent.begin

; Markup list and enum items: "- item" and "+ item".
; Typstyle indents continuation lines one level under the item.
(item) @indent.begin
