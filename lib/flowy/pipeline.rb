module Flowy
  class Pipeline
    class BranchBuilder
      attr_reader :_branches, :_otherwise

      def initialize
        @_branches   = {}
        @_otherwise  = nil
      end

      def when(key, &block)
        @_branches[key] = block
        self
      end

      def otherwise(&block)
        @_otherwise = block
        self
      end
    end
    private_constant :BranchBuilder

    def initialize(steps: [])
      @steps = steps.freeze
    end

    # Two forms: block form (`step(:name) { |prev| ... }`) and symbolic form
    # (`step(:name)` with no block, resolved against `context:` at call time).
    def step(name, &callable)
      new_step =
        if callable
          { type: :step, name: name, callable: callable }
        elsif name.is_a?(Symbol)
          { type: :step, name: name, symbolic: true }
        else
          raise ArgumentError, "step requires a block or a Symbol name"
        end

      self.class.new(steps: @steps + [new_step.freeze])
    end

    def branch(on:, &builder_block)
      raise ArgumentError, "branch requires a block" unless builder_block

      builder = BranchBuilder.new
      builder_block.call(builder)

      new_step = {
        type:      :branch,
        name:      :"branch(#{on.is_a?(Symbol) ? on : 'λ'})",
        on:        on,
        branches:  builder._branches.transform_values(&:call).freeze,
        otherwise: builder._otherwise&.call
      }.freeze

      self.class.new(steps: @steps + [new_step])
    end

    def tap_step(name, &callable)
      raise ArgumentError, "tap_step requires a block" unless callable

      new_step = { type: :tap_step, name: name, callable: callable }.freeze
      self.class.new(steps: @steps + [new_step])
    end

    def >>(other)
      raise TypeError, ">> requires a Flowy::Pipeline, got #{other.class}" unless other.is_a?(Flowy::Pipeline)

      self.class.new(steps: @steps + other._raw_steps)
    end

    def call(starting_data: {}, rescue_errors: false, context: nil)
      initial = Flowy::Result.success(data: starting_data)

      @steps.reduce(initial) do |current, step_def|
        break current if current.failure?

        execute_step(step_def, current, rescue_errors: rescue_errors, context: context)
      end
    end

    def steps
      @steps.map do |s|
        case s[:type]
        when :branch
          {
            type:      :branch,
            name:      s[:name],
            on:        s[:on],
            branches:  s[:branches].transform_values { |sub| sub.is_a?(Flowy::Pipeline) ? sub.steps : sub },
            otherwise: s[:otherwise].is_a?(Flowy::Pipeline) ? s[:otherwise].steps : s[:otherwise]
          }
        else
          { type: s[:type], name: s[:name] }
        end
      end
    end

    def size
      @steps.size
    end

    def empty?
      @steps.empty?
    end

    # Exposed to support composition via #>>.
    def _raw_steps
      @steps
    end

    protected :_raw_steps

    private

    def execute_step(step_def, previous_result, rescue_errors:, context:)
      case step_def[:type]
      when :step
        invoke_callable(step_def, previous_result, rescue_errors: rescue_errors, context: context)
      when :tap_step
        invoke_callable(step_def, previous_result, rescue_errors: rescue_errors, context: context, must_return_flowy_result: false)
        previous_result
      when :branch
        execute_branch(step_def, previous_result, rescue_errors: rescue_errors, context: context)
      else
        raise ArgumentError, "Unknown step type: #{step_def[:type]}"
      end
    end

    # must_return_flowy_result: set to false by tap_step, whose return is
    # discarded and therefore should not be type-checked.
    def invoke_callable(step_def, previous_result, rescue_errors:, context:, must_return_flowy_result: true)
      result =
        if step_def[:symbolic]
          unless context
            raise ArgumentError,
              "symbolic step :#{step_def[:name]} requires a `context:` to be passed to #call"
          end
          context.send(step_def[:name], previous_result: previous_result)
        else
          callable = step_def[:callable]
          context ? callable.call(previous_result, context) : callable.call(previous_result)
        end

      if must_return_flowy_result && !result.is_a?(Flowy::Result)
        raise TypeError,
          "Step '#{step_def[:name]}' must return a Flowy::Success or Flowy::Failure, got #{result.class}"
      end

      result
    rescue StandardError => e
      raise unless rescue_errors

      Flowy::Failure.new(
        error_code: :step_raised_error,
        error_data: { step: step_def[:name], message: e.message }
      )
    end

    def execute_branch(step_def, previous_result, rescue_errors:, context:)
      key = resolve_branch_key(step_def[:on], previous_result.data)

      sub_pipeline = step_def[:branches][key] || step_def[:otherwise]

      unless sub_pipeline
        return Flowy::Failure.new(
          error_code: :unmatched_branch,
          error_data: { branch: step_def[:name], key: key }
        )
      end

      unless sub_pipeline.is_a?(Flowy::Pipeline)
        raise TypeError,
          "Branch '#{step_def[:name]}' value for key #{key.inspect} must be a Flowy::Pipeline, got #{sub_pipeline.class}"
      end

      sub_pipeline.call(
        starting_data: previous_result.data,
        rescue_errors:  rescue_errors,
        context:        context
      )
    end

    def resolve_branch_key(on, data)
      if on.is_a?(Symbol)
        data[on]
      elsif on.respond_to?(:call)
        on.call(data)
      else
        raise ArgumentError, "branch `on:` must be a Symbol or callable, got #{on.class}"
      end
    end
  end
end
