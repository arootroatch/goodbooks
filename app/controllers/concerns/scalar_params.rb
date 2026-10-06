module ScalarParams
  private

  # Query-string filters are matched against already-scoped relations, never mass-assigned,
  # so they are read as plain strings instead of going through `permit`.
  def scalar_params(*keys)
    keys.index_with { params[_1] }.select { |_, value| value.is_a?(String) && value.present? }
  end
end
