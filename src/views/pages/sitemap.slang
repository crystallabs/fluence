.container-fluid
  .row
    .col
      h1.page-header Sitemap
  .row
    .col
      h2 Pages
      #pages-hierarchy
        == add_page_tree tree, nil
    .col
      h2 Media
      #pages-hierarchy
        == add_media media
