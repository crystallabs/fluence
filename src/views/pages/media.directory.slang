ul.list-unstyled
  - names = entries.keys.sort!
  - names.each do |name|
    - entry = entries[name][1]
    li
      - stack_join = stack.empty? ? nil : (stack.join("/") + "/")
      - if entry
        - if entry.directory?
          = entry.name
        - else
          a href="#{entry.url}" = entry.title || entry.name
      - else
        = name
    - if !entry || entry.directory?
      == add_media(Fluence::MEDIA.children1(name), stack << entries[name][0])
