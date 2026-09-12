-- linuxbook.lua - the one piece of the design that TeX macros cannot do cleanly.
--
-- \code{...} typesets C and shell exactly as they are written in the lectures. \detokenize gets
-- most of the way, but leaves two artifacts: it doubles every #, so #include would print as
-- ##include, and it puts a space after every control word, so "\n" would print as "\n ". Both are
-- undone here, and a line is allowed to break inside a long name, so that
-- /sys/bus/platform/drivers or dma_set_mask_and_coherent(dev,DMA_BIT_MASK(32)) can break rather
-- than run into the margin.

local catcode_other = -2

-- How much each break costs. A comma, a slash and an arrow are where a reader expects a long name
-- to break; an underscore is not, so a break there is a last resort that TeX takes only when the
-- line cannot otherwise be set.
local function break_after(s, i)
  local c, prev, nxt = s:sub(i, i), s:sub(i - 1, i - 1), s:sub(i + 1, i + 1)
  if nxt == "" or nxt == " " then return nil end
  if c == "," then return 100 end
  if c == "/" and i > 1 and nxt ~= "/" then return 200 end
  if c == ">" and prev == "-" then return 200 end
  if c == "_" and i > 1 and prev ~= "_" and nxt ~= "_" then return 5000 end
  return nil
end

function linuxbook_code(s)
  -- \detokenize doubles a #; halving each pair keeps C's token-pasting ## intact.
  s = s:gsub("##", "#")
  s = s:gsub("(\\%a+) ", "%1")
  -- \%, \{ and \} are how a literal percent sign or an unbalanced brace has to be written inside
  -- a TeX argument, \# is how a # has to be written in a heading or a caption, and \\ is a
  -- lone backslash.
  s = s:gsub("\\([%%{}#\\])", "%1")
  -- Each tex.sprint is read as a line of its own and TeX skips the spaces a line starts with, so
  -- no chunk may begin with one; break_after never breaks before a space for that reason.
  local start = 1
  for i = 1, #s do
    local p = break_after(s, i)
    if p then
      tex.sprint(catcode_other, s:sub(start, i))
      tex.sprint("\\penalty" .. p .. " ")
      start = i + 1
    end
  end
  tex.sprint(catcode_other, s:sub(start))
end
