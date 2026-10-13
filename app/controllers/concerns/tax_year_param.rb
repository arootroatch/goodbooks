# A tax year from the URL: four digits in 2000–2100, else 404. Never Integer(): "010" is octal.
module TaxYearParam
  private

  def tax_year_from(value)
    text = value.to_s
    raise ActiveRecord::RecordNotFound unless text.match?(/\A\d{4}\z/) && (2000..2100).cover?(text.to_i)

    text.to_i
  end
end
