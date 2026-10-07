module Tithe
  def self.ledger_for(book, today: Date.current)
    return unless book.tithe_start_on

    Ledger.new(entries: Entries.for(book), start_on: book.tithe_start_on, today: today)
  end
end
