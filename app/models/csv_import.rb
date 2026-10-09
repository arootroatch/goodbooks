class CsvImport < ApplicationRecord
  MAX_BYTES = 5.megabytes

  class NotPreviewed < StandardError; end

  belongs_to :account
  has_one_attached :file

  enum :status, { previewed: "previewed", committed: "committed", discarded: "discarded" },
    validate: true, instance_methods: false

  validate :file_present_and_small, on: :create

  before_create { self.mapping ||= account.csv_mapping }

  # The enum would also define committed!, which clashes with ActiveRecord's own committed! callback hook.
  def previewed? = status == "previewed"
  def committed? = status == "committed"
  def discarded? = status == "discarded"

  # Legacy imports have no stored mapping and fall back to the account's current one.
  def effective_mapping = mapping.present? ? CsvImport::Mapping.new(mapping) : account.mapping

  def content = file.download

  def transcoded? = CsvImport::Parser.decode(content).last

  def preview = CsvImport::Preview.build(self)

  def commit!
    with_lock do
      raise NotPreviewed, "This import was already #{status}." unless previewed?

      result = preview
      created = result.new_entries.map do |entry|
        row = entry.row
        account.transactions.create!(posted_on: row.posted_on, amount_cents: row.amount_cents, payee: row.payee,
                                     memo: row.memo, external_id: row.external_id)
      end
      RuleApplier.new(account.business).apply(created)
      result.synced_entries.each { _1.match.update!(external_id: _1.row.external_id) }
      update!(status: "committed", committed_at: Time.current, row_count: result.entries.size, new_count: created.size,
              duplicate_count: result.duplicate_entries.size, synced_count: result.synced_entries.size, error_count: result.error_entries.size)
    end
  end

  private

  def file_present_and_small
    if !file.attached?
      errors.add(:file, "must be attached")
    elsif file.blob.byte_size > MAX_BYTES
      errors.add(:file, "must be 5 MB or smaller")
    end
  end
end
