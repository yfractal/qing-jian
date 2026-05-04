module ApplicationHelper
  def primary_site_nav_links
    links = [
      {
        label: "Review",
        path: main_app.root_path,
        active: request.path == main_app.multiple_choice_review_path
      },
      {
        label: "Today",
        path: main_app.today_words_path,
        active: request.path == main_app.today_words_path
      },
      {
        label: "Browse",
        path: main_app.word_browse_path,
        active: request.path == main_app.word_browse_path
      },
      {
        label: "Words",
        path: main_app.words_path,
        active: controller_name == "words"
      },
      {
        label: "Statistics",
        path: main_app.statistics_words_path,
        active: request.path == main_app.statistics_words_path
      },
      {
        label: "Books",
        path: "/books",
        active: request.path.start_with?("/books") && controller_path != "book_plugin/flash_card_remember"
      }
    ]

    links.insert(1, {
      label: "Book flash review",
      path: book_plugin.remember_flash_cards_path,
      active: controller_path == "book_plugin/flash_card_remember"
    })

    links
  end
end
