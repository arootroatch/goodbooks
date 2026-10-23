// On phones, tables with three or more columns show each row as a card (responsive_table.css).
// Marks those tables data-stack and copies each column heading into its cells' data-label, so a card
// reads "Heading  value". Statement tables (.statement) and tables in a .table-scroll box stay tables.
// A MutationObserver covers Turbo visits, frames and streams.
function columnHeadings(table) {
  const headings = []
  for (const cell of table.tHead?.rows[0]?.cells ?? []) {
    for (let i = 0; i < cell.colSpan; i++) headings.push(cell.textContent.trim())
  }
  return headings
}

function stack(table) {
  if (table.matches(".statement, .table-scroll > table")) return
  const headings = columnHeadings(table)
  if (headings.length < 3) return

  table.dataset.stack = ""
  for (const body of [ ...table.tBodies, table.tFoot ].filter(Boolean)) {
    for (const row of body.rows) {
      let column = 0
      for (const cell of row.cells) {
        if (cell.colSpan === 1 && headings[column] && !cell.hasAttribute("data-label")) cell.dataset.label = headings[column]
        column += cell.colSpan
      }
    }
  }
}

function stackAll() {
  document.querySelectorAll(".app-main table").forEach(stack)
}

// Batched to one pass per frame; requestAnimationFrame still runs before the frame paints.
let queued = false
new MutationObserver(() => {
  if (queued) return
  queued = true
  requestAnimationFrame(() => { queued = false; stackAll() })
}).observe(document.documentElement, { childList: true, subtree: true })
stackAll()
