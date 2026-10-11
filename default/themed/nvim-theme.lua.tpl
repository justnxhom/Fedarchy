-- Neovim colours.
--
-- Generated from default/themed/nvim-theme.lua.tpl. Edit that template, not
-- this copy: a theme switch rewrites this file.
--
-- This file is `dofile`d by colors/nahom.lua, which also watches this path and
-- re-runs it when the file changes. That means it has to APPLY the colours by
-- side effect. Returning a value instead -- a plugin spec, a colourscheme name --
-- is silently discarded by dofile, the editor keeps whatever highlights it had,
-- and the switcher reports success. That is why this is a script of
-- nvim_set_hl calls and not a LazyVim spec.
--
-- The separate neovim.lua payload is the opposite contract: a plugin spec for
-- LazyVim to read at startup. The two are not interchangeable.

local colors = {
  bg = "{{ background }}",
  fg = "{{ foreground }}",
  accent = "{{ accent }}",
  red = "{{ red }}",
  green = "{{ green }}",
  yellow = "{{ yellow }}",
  blue = "{{ blue }}",
  cyan = "{{ cyan }}",
  magenta = "{{ magenta }}",
  orange = "{{ orange }}",
  muted = "{{ muted }}",
  surface = "{{ lighter_background }}",
  selection = "{{ selection }}",
}

local hl = vim.api.nvim_set_hl

hl(0, "Normal", { fg = colors.fg, bg = colors.bg })
hl(0, "NormalFloat", { fg = colors.fg, bg = colors.bg })
hl(0, "FloatBorder", { fg = colors.muted, bg = colors.bg })
hl(0, "CursorLine", { bg = colors.surface })
hl(0, "CursorColumn", { bg = colors.surface })
hl(0, "ColorColumn", { bg = colors.surface })
hl(0, "LineNr", { fg = colors.muted })
hl(0, "CursorLineNr", { fg = colors.accent })
hl(0, "SignColumn", { fg = colors.muted, bg = colors.bg })
hl(0, "FoldColumn", { fg = colors.muted, bg = colors.bg })
hl(0, "Visual", { bg = colors.selection })
hl(0, "Search", { fg = colors.bg, bg = colors.yellow })
hl(0, "IncSearch", { fg = colors.bg, bg = colors.accent })
hl(0, "Pmenu", { fg = colors.fg, bg = colors.surface })
hl(0, "PmenuSel", { fg = colors.fg, bg = colors.selection })
hl(0, "StatusLine", { fg = colors.fg, bg = colors.surface })
hl(0, "StatusLineNC", { fg = colors.muted, bg = colors.surface })
hl(0, "TabLine", { fg = colors.muted, bg = colors.bg })
hl(0, "TabLineFill", { bg = colors.bg })
hl(0, "TabLineSel", { fg = colors.fg, bg = colors.surface })
hl(0, "Title", { fg = colors.accent, bold = true })
hl(0, "Directory", { fg = colors.blue })
hl(0, "ErrorMsg", { fg = colors.red })
hl(0, "WarningMsg", { fg = colors.yellow })
hl(0, "MoreMsg", { fg = colors.green })
hl(0, "Question", { fg = colors.blue })
hl(0, "VertSplit", { fg = colors.muted })
hl(0, "WinSeparator", { fg = colors.muted })
hl(0, "WildMenu", { fg = colors.fg, bg = colors.selection })
hl(0, "MatchParen", { bg = colors.selection, bold = true })
hl(0, "NonText", { fg = colors.muted })
hl(0, "SpecialKey", { fg = colors.muted })

-- Syntax
hl(0, "Comment", { fg = colors.muted, italic = true })
hl(0, "Constant", { fg = colors.magenta })
hl(0, "String", { fg = colors.green })
hl(0, "Character", { fg = colors.green })
hl(0, "Number", { fg = colors.orange })
hl(0, "Boolean", { fg = colors.orange })
hl(0, "Float", { fg = colors.orange })
hl(0, "Identifier", { fg = colors.fg })
hl(0, "Function", { fg = colors.blue })
hl(0, "Statement", { fg = colors.accent })
hl(0, "Conditional", { fg = colors.accent })
hl(0, "Repeat", { fg = colors.accent })
hl(0, "Label", { fg = colors.accent })
hl(0, "Operator", { fg = colors.fg })
hl(0, "Keyword", { fg = colors.accent })
hl(0, "Exception", { fg = colors.accent })
hl(0, "PreProc", { fg = colors.cyan })
hl(0, "Include", { fg = colors.cyan })
hl(0, "Define", { fg = colors.cyan })
hl(0, "Macro", { fg = colors.cyan })
hl(0, "PreCondit", { fg = colors.cyan })
hl(0, "Type", { fg = colors.yellow })
hl(0, "StorageClass", { fg = colors.yellow })
hl(0, "Structure", { fg = colors.yellow })
hl(0, "Typedef", { fg = colors.yellow })
hl(0, "Special", { fg = colors.cyan })
hl(0, "SpecialChar", { fg = colors.cyan })
hl(0, "Tag", { fg = colors.red })
hl(0, "Delimiter", { fg = colors.muted })
hl(0, "SpecialComment", { fg = colors.muted, bold = true })
hl(0, "Debug", { fg = colors.red })
hl(0, "Underlined", { underline = true })
hl(0, "Ignore", { fg = colors.muted })
hl(0, "Error", { fg = colors.red })
hl(0, "Todo", { fg = colors.yellow, bold = true })

-- Diff backgrounds are the background tinted towards the diff's own colour
-- rather than a fixed pair, so they stay legible on a light theme as well.
hl(0, "DiffAdd", { bg = "{{ mix background green 15% }}" })
hl(0, "DiffDelete", { fg = colors.muted, bg = "{{ mix background red 15% }}" })
hl(0, "DiffChange", { bg = "{{ mix background cyan 12% }}" })
hl(0, "DiffText", { bg = "{{ mix background cyan 20% }}" })

-- Diagnostics
hl(0, "DiagnosticError", { fg = colors.red })
hl(0, "DiagnosticWarn", { fg = colors.yellow })
hl(0, "DiagnosticInfo", { fg = colors.blue })
hl(0, "DiagnosticHint", { fg = colors.cyan })
hl(0, "DiagnosticUnderlineError", { undercurl = true, sp = colors.red })
hl(0, "DiagnosticUnderlineWarn", { undercurl = true, sp = colors.yellow })
hl(0, "DiagnosticUnderlineInfo", { undercurl = true, sp = colors.blue })
hl(0, "DiagnosticUnderlineHint", { undercurl = true, sp = colors.cyan })
