module Enumerable
  # On failure produces `error_code: :partial_failure`.
  def all_success(&block)
    results = Flowy::Result._collect_results(self, &block)

    if results.all?(&:success?)
      Flowy::Result.success(data: { results: results })
    else
      Flowy::Failure.new(
        error_code: :partial_failure,
        error_data: { results: results }
      )
    end
  end

  # On failure produces `error_code: :all_failed`.
  def any_success(&block)
    results = Flowy::Result._collect_results(self, &block)

    if results.any?(&:success?)
      Flowy::Result.success(data: { results: results })
    else
      Flowy::Failure.new(
        error_code: :all_failed,
        error_data: { results: results }
      )
    end
  end
end
