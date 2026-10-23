# What Transfer, Excluded, and Leave out of tithe do: shown under the edit form's checkboxes and as button tooltips.
module TransactionsHelper
  TRANSFER_HELP = "Money moving between your own accounts. Left out of income, spending, reports, and tithe; " \
                  "still counts in the account balance.".freeze
  EXCLUDED_HELP = "Ignore this transaction everywhere: reports, tithe, goals, exports, the inbox, and the account balance. " \
                  "For duplicates or rows that aren't real activity. Imported rows can't be deleted, so exclude them instead.".freeze
  TITHE_EXCLUDED_HELP = "Only the tithe ignores it; it still counts everywhere else.".freeze
end
