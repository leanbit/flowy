module Flowy
  # Tag module + factory namespace. Both Flowy::Success and Flowy::Failure
  # include this module so `result.is_a?(Flowy::Result)` matches either.
  # The instance interface is defined on Success and Failure — see the README.
  module Result
    def self._deep_merge(a, b)
      a.merge(b) do |_, va, vb|
        if va.is_a?(Hash) && vb.is_a?(Hash)
          _deep_merge(va, vb)
        else
          vb
        end
      end
    end

    def self._collect_results(enumerable)
      enumerable.map do |item|
        result = yield item
        unless result.is_a?(Flowy::Result)
          raise TypeError,
            "all_success/any_success block must return a Flowy::Result, got #{result.class}"
        end
        result
      end
    end

    def self.success(data: {}, warnings: [])
      Flowy::Success.new(data: data, warnings: warnings)
    end

    def self.failure(error_code:, error_data: {}, error_title: nil, error_description: nil, parent_failure: nil)
      Flowy::Failure.new(
        error_code: error_code,
        error_data: error_data,
        error_title: error_title,
        error_description: error_description,
        parent_failure: parent_failure
      )
    end

    # `rescue:` is captured via **opts because `rescue` is a Ruby reserved word
    # and cannot be referenced as a bare local variable inside a method body.
    def self.wrap(error_code: :wrapped_error, error_title: nil, **opts)
      unknown = opts.keys - [:rescue]
      raise ArgumentError, "unknown keyword: #{unknown.first}" if unknown.any?

      rescued_classes = Array(opts.fetch(:rescue, [StandardError]))

      value = yield

      return value if value.is_a?(Flowy::Result)

      Flowy::Success.new(data: { value: value })
    rescue *rescued_classes => e
      Flowy::Failure.new(
        error_code: error_code,
        error_data: { error_class: e.class.name, message: e.message },
        error_title: error_title,
        error_description: e.message
      )
    end
  end
end
