module Flowy
  class Failure
    include Flowy::Result

    attr_reader :error_code, :error_data, :error_title, :error_description, :parent_failure

    def initialize(error_code:, error_data: {}, error_title: nil, error_description: nil, parent_failure: nil)
      @error_code = error_code
      @error_data = error_data
      @error_title = error_title
      @error_description = error_description
      @parent_failure = parent_failure
    end

    def to_hash
      {
        success: false,
        error_code: error_code,
        error_data: error_data,
        error_title: error_title,
        error_description: error_description
      }
    end

    def is?(error_code:)
      self.error_code == error_code
    end

    def raise!
      raise Flowy::Error.initialize_from_failure(failure: self)
    end

    def success?
      false
    end

    def failure?
      true
    end

    def on_success
      self
    end

    def on_failure
      yield self
      self
    end

    def and_then
      self
    end

    def or_else
      result = yield self
      unless result.is_a?(Flowy::Success) || result.is_a?(Flowy::Failure)
        raise TypeError, "or_else block must return a Flowy::Success or Flowy::Failure, got #{result.class}"
      end

      result
    end

    def tap
      yield self
      self
    end

    def failures_chain
      return [self] unless parent_failure

      parent_failure.failures_chain + [self]
    end

    # In block form, when the block-returned Failure omits parent_failure,
    # self is wired in as parent_failure so the chain is never broken.
    def map_failure(error_code: nil, error_data: {}, error_title: nil, error_description: nil)
      if block_given?
        result = yield self
        unless result.is_a?(Flowy::Failure)
          raise TypeError,
            "map_failure block must return a Flowy::Failure, got #{result.class}"
        end
        if result.parent_failure.nil?
          result.class.new(
            error_code:        result.error_code,
            error_data:        result.error_data,
            error_title:       result.error_title,
            error_description: result.error_description,
            parent_failure:    self
          )
        else
          result
        end
      else
        raise ArgumentError, 'map_failure requires either a block or error_code:' if error_code.nil?

        self.class.new(
          error_code:        error_code,
          error_data:        error_data,
          error_title:       error_title,
          error_description: error_description,
          parent_failure:    self
        )
      end
    end

    def merge_data(extra = nil)
      extra = block_given? ? yield(error_data) : extra
      raise ArgumentError, 'merge_data requires a Hash' unless extra.is_a?(Hash)

      self.class.new(
        error_code: error_code,
        error_data: Flowy::Result._deep_merge(error_data, extra),
        error_title: error_title,
        error_description: error_description,
        parent_failure: parent_failure
      )
    end
  end
end
