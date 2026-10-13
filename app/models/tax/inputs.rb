module Tax
  # Everything the estimator reads, as plain values.
  Inputs = Data.define(:year, :params, :businesses, :people, :periods, :prior_year, :payments, :today)
end
