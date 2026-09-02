h6.section-title Wiki Pages
- prev_page, up_page, next_page = page_neighbours tree, page.name
.btn-group.btn-group-sm.w-100.mb-2#page-nav role="group" aria-label="Previous, parent, and next page"
  - if prev_page
    a.btn.btn-outline-secondary.text-nowrap href="#{prev_page.url}" title="Previous: #{prev_page.title}" ‹ Prev
  - else
    span.btn.btn-outline-secondary.text-nowrap.disabled ‹ Prev
  - if up_page
    a.btn.btn-outline-secondary.text-nowrap href="#{up_page.url}" title="Up: #{up_page.title}" ↑ Up
  - else
    span.btn.btn-outline-secondary.text-nowrap.disabled ↑ Up
  - if next_page
    a.btn.btn-outline-secondary.text-nowrap href="#{next_page.url}" title="Next: #{next_page.title}" Next ›
  - else
    span.btn.btn-outline-secondary.text-nowrap.disabled Next ›
#pages-hierarchy
  == add_page_tree tree, page.name
