module Flowy
  class Error < StandardError
    
    attr_reader :code, :title, :detail, :meta
    
    def self.initialize_from_failure(failure:)
      unless failure.is_a?(Flowy::Failure)
        raise ArgumentError, "Flowy::Error requires a Flowy::Failure instance, got #{failure.class}"
      end

      new(
        code: failure.error_code,
        title: failure.error_title,
        detail: failure.error_description,
        meta: failure.error_data
      )
    end
    
    def initialize(code:, title: nil, detail: nil, meta: nil)
      @code = code
      @title = title
      @detail = detail
      @meta = meta
      super(build_message(code, title, detail))
    end
    
    def to_failure
      Flowy::Failure.new(
        error_code: code,
        error_data: meta || {},
        error_title: title,
        error_description: detail
      )
    end

    def to_hash
      to_failure.to_hash
    end

    private

    def build_message(code, title, detail)
      description = [title, detail].compact.map(&:to_s).reject(&:empty?).join(': ')
      [code.to_s, description].reject(&:empty?).join(' - ')
    end
  end
end
