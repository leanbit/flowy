module Flowy
  class Success
    include Flowy::Result

    attr_reader :data, :warnings

    def initialize(data: {}, warnings: [])
      @data = data
      @warnings = warnings
    end

    def +(other)
      self.class.new(data: Flowy::Result._deep_merge(data, other.data))
    end

    def to_hash
      {
        success: true,
        data: data,
        warnings: warnings
      }
    end

    def success?
      true
    end

    def failure?
      false
    end

    def on_success
      yield self
      self
    end

    def on_failure
      self
    end

    def and_then
      result = yield self
      unless result.is_a?(Flowy::Success) || result.is_a?(Flowy::Failure)
        raise TypeError, "and_then block must return a Flowy::Success or Flowy::Failure, got #{result.class}"
      end

      result
    end

    def or_else
      self
    end

    def map_failure(**)
      self
    end

    def raise!
      self
    end

    def tap
      yield self
      self
    end

    def merge_data(extra = nil)
      extra = block_given? ? yield(data) : extra
      raise ArgumentError, 'merge_data requires a Hash' unless extra.is_a?(Hash)

      self.class.new(data: Flowy::Result._deep_merge(data, extra), warnings: warnings)
    end
  end
end
