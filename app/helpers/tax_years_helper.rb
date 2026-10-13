module TaxYearsHelper
  # The URL is validated to be https:// on Household.
  def irs_payment_link(household)
    link_to "Pay on IRS.gov ↗", household.irs_payment_url, class: "button primary", target: "_blank", rel: "noopener noreferrer"
  end

  def tax_period_label(worksheet)
    if worksheet.elapsed_days.nil? then "annualized ×#{tax_factor_label(Tax::PeriodInput::FACTORS.fetch(worksheet.quarter))}"
    elsif worksheet.elapsed_days.zero? then "no activity yet"
    else "projected from #{pluralize(worksheet.elapsed_days, 'day')}"
    end
  end

  def tax_payment_debit_label(payment, visible_book_ids)
    debit = payment.debit
    if debit.nil? then "Entered by hand"
    elsif visible_book_ids.include?(debit.account.business_id) then "#{debit.payee} · #{debit.account.name}"
    else "Linked to a bank transaction"
    end
  end

  def tax_payment_link_sentence(payment, visible_book_ids)
    label = tax_payment_debit_label(payment, visible_book_ids)
    label.start_with?("Linked") ? "#{label}." : "Linked to #{label}."
  end

  def can_edit_home_office?(business_id)
    business = Current.user.accessible_businesses.find_by(id: business_id)
    business.present? && Current.user.can_edit_home_office?(business)
  end

  def can_edit_adjustments?(person_id)
    person = Household.instance.people.find_by(id: person_id)
    person.present? && Current.user.can_edit_adjustments?(person)
  end

  def tax_rate_label(bps) = "#{PercentAttribute.format_bps(bps)}%"

  private

  # A Rational factor as a plain decimal ("4", "2.4", "1.5"), never through Float.
  # Requires a terminating decimal expansion (denominator of only 2s and 5s), as every Tax::PeriodInput::FACTORS value has.
  def tax_factor_label(factor)
    factor = factor.to_r
    return factor.numerator.to_s if factor.denominator == 1

    whole, remainder = factor.numerator.divmod(factor.denominator)
    digits = +""
    while remainder.nonzero?
      remainder *= 10
      digit, remainder = remainder.divmod(factor.denominator)
      digits << digit.to_s
    end
    "#{whole}.#{digits}"
  end
end
